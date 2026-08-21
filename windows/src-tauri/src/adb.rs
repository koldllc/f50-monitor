use tokio::io::{AsyncReadExt, AsyncWriteExt};
use tokio::net::TcpStream;
use tokio::time::{timeout, Duration};

const A_CNXN: u32 = 0x4e58_4e43;
const A_OPEN: u32 = 0x4e45_504f;
const A_OKAY: u32 = 0x5941_4b4f;
const A_CLSE: u32 = 0x4553_4c43;
const A_WRTE: u32 = 0x4554_5257;
const MAX_PACKET_SIZE: usize = 1024 * 1024;

fn packet(command: u32, arg0: u32, arg1: u32, data: &[u8]) -> Vec<u8> {
    let checksum = data.iter().fold(0_u32, |sum, byte| sum.wrapping_add(*byte as u32));
    let mut result = Vec::with_capacity(24 + data.len());
    for value in [
        command,
        arg0,
        arg1,
        data.len() as u32,
        checksum,
        command ^ u32::MAX,
    ] {
        result.extend_from_slice(&value.to_le_bytes());
    }
    result.extend_from_slice(data);
    result
}

async fn read_packet(stream: &mut TcpStream) -> Option<(u32, u32, Vec<u8>)> {
    let mut header = [0_u8; 24];
    stream.read_exact(&mut header).await.ok()?;
    let command = u32::from_le_bytes(header[0..4].try_into().ok()?);
    let arg0 = u32::from_le_bytes(header[4..8].try_into().ok()?);
    let data_len = u32::from_le_bytes(header[12..16].try_into().ok()?) as usize;
    let magic = u32::from_le_bytes(header[20..24].try_into().ok()?);
    if magic != command ^ u32::MAX || data_len > MAX_PACKET_SIZE {
        return None;
    }
    let mut data = vec![0_u8; data_len];
    if data_len > 0 {
        stream.read_exact(&mut data).await.ok()?;
    }
    Some((command, arg0, data))
}

/// 直接连接设备的原生 ADB 5555 Socket，不依赖本机 adb.exe。
pub async fn execute_shell(host: &str, command: &str, timeout_secs: u64) -> Option<String> {
    timeout(Duration::from_secs(timeout_secs), async {
        let mut stream = TcpStream::connect((host, 5555)).await.ok()?;
        stream
            .write_all(&packet(A_CNXN, 0x0100_0000, 0x0010_0000, b"host::\0"))
            .await
            .ok()?;

        let (command_reply, _, _) = read_packet(&mut stream).await?;
        // 当前采集通道仅支持设备已允许的免认证 ADB；AUTH 时立即回退 2333。
        if command_reply != A_CNXN {
            return None;
        }

        let local_id = 1_u32;
        let mut service = format!("shell:{command}").into_bytes();
        service.push(0);
        stream
            .write_all(&packet(A_OPEN, local_id, 0, &service))
            .await
            .ok()?;

        let mut output = Vec::new();
        loop {
            let (reply, remote_id, body) = read_packet(&mut stream).await?;
            match reply {
                A_WRTE => {
                    output.extend_from_slice(&body);
                    stream
                        .write_all(&packet(A_OKAY, local_id, remote_id, &[]))
                        .await
                        .ok()?;
                }
                A_CLSE => {
                    let _ = stream
                        .write_all(&packet(A_CLSE, local_id, remote_id, &[]))
                        .await;
                    break;
                }
                A_OKAY => {}
                _ => return None,
            }
        }
        String::from_utf8(output).ok()
    })
    .await
    .ok()
    .flatten()
}

pub async fn execute_at(host: &str, command: &str) -> Option<String> {
    let escaped_command = shell_single_quoted(command);
    let legacy_payload = shell_single_quoted(&format!("sendAt 0 {command}"));
    let shell_command = format!(
        "if [ \"$(getprop ro.build.version.sdk)\" -gt 33 ]; then service call vendor.sprd.hardware.tool.IToolControl/default 3 i32 0 s16 '{escaped_command}'; else service call vendor.sprd.hardware.log.ILogControl/default 1 s16 'miscserver' s16 '{legacy_payload}'; fi"
    );
    let output = execute_shell(host, &shell_command, 3).await?;
    let decoded = decode_binder_parcel(&output);
    (!decoded.is_empty()).then_some(decoded)
}

fn decode_binder_parcel(output: &str) -> String {
    let mut result = String::new();
    let mut skipped_headers = 0;
    for line in output.lines() {
        let hex_section = line.split('\'').next().unwrap_or(line);
        for token in hex_section.split(|character: char| character.is_whitespace() || character == ':') {
            if token.len() != 8 || !token.bytes().all(|byte| byte.is_ascii_hexdigit()) {
                continue;
            }
            if skipped_headers < 2 {
                skipped_headers += 1;
                continue;
            }
            let Some(word) = u32::from_str_radix(token, 16).ok() else {
                continue;
            };
            for unit in [word as u16, (word >> 16) as u16] {
                if unit >= 32 || unit == 10 || unit == 13 {
                    if let Some(character) = char::from_u32(unit as u32) {
                        result.push(character);
                    }
                }
            }
        }
    }
    result.trim().to_string()
}

fn shell_single_quoted(value: &str) -> String {
    value.replace('\'', "'\\''")
}
