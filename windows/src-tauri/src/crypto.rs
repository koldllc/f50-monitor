use hmac::{Hmac, Mac};
use md5::Md5;
use sha2::{Digest, Sha256};

type HmacMd5 = Hmac<Md5>;

pub const KANO_SIGN_KEY: &str = "minikano_kOyXz0Ciz4V7wR0IeKmJFYFQ20jd";

/// UFI-TOOLS 请求签名：
/// HMAC-MD5(data) 拆前后两半，各自对【原始字节】做 SHA-256，拼接后再 SHA-256，输出小写 hex。
pub fn kano_sign(key: &str, data: &str) -> String {
    let mut mac = HmacMd5::new_from_slice(key.as_bytes()).expect("HMAC can take key of any size");
    mac.update(data.as_bytes());
    let hmac_bytes = mac.finalize().into_bytes();

    let half = hmac_bytes.len() / 2;
    let sha1 = Sha256::digest(&hmac_bytes[..half]);
    let sha2 = Sha256::digest(&hmac_bytes[half..]);

    let mut combined = Vec::with_capacity(64);
    combined.extend_from_slice(&sha1);
    combined.extend_from_slice(&sha2);

    let final_sha = Sha256::digest(&combined);
    hex::encode(final_sha)
}

pub fn sha256_hex(data: &str) -> String {
    let hash = Sha256::digest(data.as_bytes());
    hex::encode(hash)
}

pub fn md5_hex(data: &str) -> String {
    let hash = Md5::digest(data.as_bytes());
    hex::encode(hash)
}

/// UFI-TOOLS 短信发送的消息体编码：UTF-16BE 的 hex 字符串
pub fn gsm_encode(text: &str) -> String {
    let mut utf16_bytes = Vec::new();
    for unit in text.encode_utf16() {
        utf16_bytes.push((unit >> 8) as u8);
        utf16_bytes.push((unit & 0xFF) as u8);
    }
    hex::encode(utf16_bytes)
}

/// URL 百分比编码（保留字母数字与 -_.~）
pub fn percent_encode_form(s: &str) -> String {
    let mut out = String::new();
    for b in s.bytes() {
        match b {
            b'a'..=b'z' | b'A'..=b'Z' | b'0'..=b'9' | b'-' | b'_' | b'.' | b'~' => {
                out.push(b as char);
            }
            _ => {
                out.push_str(&format!("%{:02X}", b));
            }
        }
    }
    out
}

/// Base64 编码
pub fn base64_encode(input: &[u8]) -> String {
    const B64_CHARS: &[u8; 64] = b"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
    let mut out = String::new();
    let mut i = 0;
    while i < input.len() {
        let b0 = input[i] as u32;
        let b1 = if i + 1 < input.len() { input[i + 1] as u32 } else { 0 };
        let b2 = if i + 2 < input.len() { input[i + 2] as u32 } else { 0 };

        let triple = (b0 << 16) | (b1 << 8) | b2;

        out.push(B64_CHARS[((triple >> 18) & 0x3F) as usize] as char);
        out.push(B64_CHARS[((triple >> 12) & 0x3F) as usize] as char);

        if i + 1 < input.len() {
            out.push(B64_CHARS[((triple >> 6) & 0x3F) as usize] as char);
        } else {
            out.push('=');
        }

        if i + 2 < input.len() {
            out.push(B64_CHARS[(triple & 0x3F) as usize] as char);
        } else {
            out.push('=');
        }

        i += 3;
    }
    out
}

/// Base64 解码，支持标准与 URL-safe 格式并自动忽略换行空格
pub fn base64_decode(input: &str) -> Option<Vec<u8>> {
    let clean: String = input.chars().filter(|c| !c.is_whitespace()).collect();
    if clean.is_empty() {
        return Some(Vec::new());
    }

    const B64_CHARS: &[u8; 64] = b"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
    let mut lookup = [255u8; 256];
    for (i, &b) in B64_CHARS.iter().enumerate() {
        lookup[b as usize] = i as u8;
    }
    lookup[b'-' as usize] = 62;
    lookup[b'_' as usize] = 63;

    let bytes = clean.as_bytes();
    let len = bytes.len();
    let mut out = Vec::with_capacity((len * 3) / 4);

    let mut buf = 0u32;
    let mut bits = 0u32;

    for &b in bytes {
        if b == b'=' {
            break;
        }
        let val = lookup[b as usize];
        if val == 255 {
            continue;
        }
        buf = (buf << 6) | (val as u32);
        bits += 6;
        if bits >= 8 {
            bits -= 8;
            out.push((buf >> bits) as u8);
            buf &= (1 << bits) - 1;
        }
    }

    Some(out)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_kano_sign_format() {
        let sig = kano_sign(KANO_SIGN_KEY, "minikanoGET/api/goform/goform_get_cmd_process1723900000000");
        assert_eq!(sig.len(), 64);
    }

    #[test]
    fn test_gsm_encode() {
        let encoded = gsm_encode("你好");
        assert_eq!(encoded, "4f60597d");
    }
}
