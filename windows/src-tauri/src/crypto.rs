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
    for ch in text.chars() {
        let mut buf = [0u16; 2];
        let encoded = ch.encode_utf16(&mut buf);
        for &unit in encoded {
            utf16_bytes.push((unit >> 8) as u8);
            utf16_bytes.push((unit & 0xFF) as u8);
        }
    }
    hex::encode(utf16_bytes)
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
