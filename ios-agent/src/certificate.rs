// SPDX-License-Identifier: Apache-2.0
//! Small, bounded DER encoder for the device's self-signed identity certificate.
//! It does not implement cryptography or parse untrusted certificates. The native
//! SDK supplies an RSA PKCS#1 public key and signs the returned TBSCertificate.

pub const MAX_DER: usize = 2048;
const SHA384_RSA: &[u8] = &[
    0x30, 0x0d, 0x06, 0x09, 0x2a, 0x86, 0x48, 0x86, 0xf7, 0x0d, 0x01, 0x01, 0x0c, 0x05, 0,
];
const RSA_ENCRYPTION: &[u8] = &[
    0x30, 0x0d, 0x06, 0x09, 0x2a, 0x86, 0x48, 0x86, 0xf7, 0x0d, 0x01, 0x01, 0x01, 0x05, 0,
];

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum CertificateError {
    InvalidInput,
    OutputTooSmall,
}

struct Der {
    bytes: [u8; MAX_DER],
    len: usize,
}
impl Der {
    fn new(tag: u8, parts: &[&[u8]]) -> Result<Self, CertificateError> {
        let length = parts
            .iter()
            .try_fold(0_usize, |n, p| n.checked_add(p.len()))
            .ok_or(CertificateError::InvalidInput)?;
        if length > MAX_DER - 4 {
            return Err(CertificateError::InvalidInput);
        }
        let mut result = Self {
            bytes: [0; MAX_DER],
            len: 0,
        };
        result.bytes[0] = tag;
        result.len = if length < 128 {
            result.bytes[1] = length as u8;
            2
        } else if length <= 255 {
            result.bytes[1..3].copy_from_slice(&[0x81, length as u8]);
            3
        } else {
            result.bytes[1..4].copy_from_slice(&[0x82, (length >> 8) as u8, length as u8]);
            4
        };
        for part in parts {
            result.bytes[result.len..result.len + part.len()].copy_from_slice(part);
            result.len += part.len();
        }
        Ok(result)
    }
    fn data(&self) -> &[u8] {
        &self.bytes[..self.len]
    }
    fn copy_to(&self, output: &mut [u8]) -> Result<usize, CertificateError> {
        if output.len() < self.len {
            return Err(CertificateError::OutputTooSmall);
        }
        output[..self.len].copy_from_slice(self.data());
        Ok(self.len)
    }
}

fn date(value: &[u8; 15]) -> Result<Der, CertificateError> {
    if value[14] != b'Z' || !value[..14].iter().all(u8::is_ascii_digit) {
        return Err(CertificateError::InvalidInput);
    }
    let number = |start, end| {
        value[start..end]
            .iter()
            .fold(0_u32, |n, c| n * 10 + u32::from(c - b'0'))
    };
    let year = number(0, 4);
    let month = number(4, 6);
    let day = number(6, 8);
    let leap = year % 4 == 0 && (year % 100 != 0 || year % 400 == 0);
    let days = match month {
        2 => {
            if leap {
                29
            } else {
                28
            }
        }
        4 | 6 | 9 | 11 => 30,
        1 | 3 | 5 | 7 | 8 | 10 | 12 => 31,
        _ => 0,
    };
    if year < 2000
        || day == 0
        || day > days
        || number(8, 10) > 23
        || number(10, 12) > 59
        || number(12, 14) > 59
    {
        return Err(CertificateError::InvalidInput);
    }
    if year < 2050 {
        Der::new(0x17, &[&value[2..]])
    } else {
        Der::new(0x18, &[value])
    }
}

/// Build an X.509 v1 TBSCertificate. The SDK must supply a canonical PKCS#1 DER
/// 2048/3072-bit RSA public key, a fresh nonzero 16-byte serial and UTC dates.
pub fn build_tbs(
    public_key_pkcs1: &[u8],
    serial: &[u8; 16],
    not_before: &[u8; 15],
    not_after: &[u8; 15],
    output: &mut [u8],
) -> Result<usize, CertificateError> {
    if !(256..=512).contains(&public_key_pkcs1.len())
        || public_key_pkcs1[0] != 0x30
        || not_before >= not_after
    {
        return Err(CertificateError::InvalidInput);
    }
    let start = serial
        .iter()
        .position(|n| *n != 0)
        .ok_or(CertificateError::InvalidInput)?;
    let serial_value = &serial[start..];
    let serial_der = if serial_value[0] & 0x80 != 0 {
        Der::new(2, &[&[0], serial_value])?
    } else {
        Der::new(2, &[serial_value])?
    };
    let common_name = Der::new(0x0c, &[b"MeshCentral iOS Agent"])?;
    let attribute = Der::new(0x30, &[&[0x06, 0x03, 0x55, 0x04, 0x03], common_name.data()])?;
    let rdn = Der::new(0x31, &[attribute.data()])?;
    let name = Der::new(0x30, &[rdn.data()])?;
    let before = date(not_before)?;
    let after = date(not_after)?;
    let validity = Der::new(0x30, &[before.data(), after.data()])?;
    let key_bits = Der::new(3, &[&[0], public_key_pkcs1])?;
    let spki = Der::new(0x30, &[RSA_ENCRYPTION, key_bits.data()])?;
    Der::new(
        0x30,
        &[
            serial_der.data(),
            SHA384_RSA,
            name.data(),
            validity.data(),
            name.data(),
            spki.data(),
        ],
    )?
    .copy_to(output)
}

/// Wrap the TBS and its native RSA PKCS#1 v1.5 SHA-384 signature in a certificate.
/// The caller must pass the exact TBS it signed, not arbitrary untrusted input.
pub fn finish(tbs: &[u8], signature: &[u8], output: &mut [u8]) -> Result<usize, CertificateError> {
    if tbs.first() != Some(&0x30) || !matches!(signature.len(), 256 | 384) {
        return Err(CertificateError::InvalidInput);
    }
    let bits = Der::new(3, &[&[0], signature])?;
    Der::new(0x30, &[tbs, SHA384_RSA, bits.data()])?.copy_to(output)
}
