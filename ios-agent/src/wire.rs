// SPDX-License-Identifier: Apache-2.0
//! Bounded codecs for complete MeshCentral control-channel handshake messages.

pub const HASH_LEN: usize = 48;
pub const CHALLENGE_LEN: usize = 98;
pub const MAX_CERTIFICATE_LEN: usize = 8192;
pub const MAX_SIGNATURE_LEN: usize = 384;
pub const MAX_NAME_LEN: usize = 255;
pub const MAX_FRAME_LEN: usize = 4 + MAX_CERTIFICATE_LEN + MAX_SIGNATURE_LEN;

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum WireError {
    InvalidLength,
    FrameTooLarge,
    OutputTooSmall,
    UnsupportedCommand(u16),
    InvalidCertificateLength,
    UnsupportedSignatureLength,
    InvalidName,
    InvalidPlatform,
    LegacyMeshId,
}

#[derive(Clone, Copy, Eq, PartialEq)]
pub struct Challenge {
    pub tls_hash: [u8; HASH_LEN],
    pub nonce: [u8; HASH_LEN],
}

#[derive(Clone, Copy)]
pub struct CertificateProof<'a> {
    pub certificate_der: &'a [u8],
    pub signature: &'a [u8],
}

impl CertificateProof<'_> {
    pub fn validate(&self) -> Result<(), WireError> {
        if self.certificate_der.is_empty() || self.certificate_der.len() > MAX_CERTIFICATE_LEN {
            return Err(WireError::InvalidCertificateLength);
        }
        if !matches!(self.signature.len(), 256 | 384) {
            return Err(WireError::UnsupportedSignatureLength);
        }
        Ok(())
    }
}

#[derive(Clone, Copy)]
pub struct AgentInfo<'a> {
    pub info_version: u32,
    /// Must be agreed with the server registry; no iOS ID is assigned here.
    pub architecture_id: u32,
    pub agent_version: u32,
    /// MeshCentral's icon/platform field, not a Rust target or architecture ID.
    pub platform_type: u32,
    pub mesh_id: [u8; HASH_LEN],
    pub capabilities: u32,
    pub name: &'a str,
}

impl AgentInfo<'_> {
    pub fn validate(&self) -> Result<(), WireError> {
        if !(1..=8).contains(&self.platform_type) {
            return Err(WireError::InvalidPlatform);
        }
        if self.mesh_id[32..].iter().all(|byte| *byte == 0) {
            return Err(WireError::LegacyMeshId);
        }
        if self.name.len() > MAX_NAME_LEN || self.name.chars().any(char::is_control) {
            return Err(WireError::InvalidName);
        }
        Ok(())
    }
}

pub enum Message<'a> {
    Challenge(Challenge),
    Certificate(CertificateProof<'a>),
    AgentInfo(AgentInfo<'a>),
    Authenticated,
    ServerId([u8; HASH_LEN]),
}

fn read_u16(bytes: &[u8], offset: usize) -> u16 {
    u16::from_be_bytes([bytes[offset], bytes[offset + 1]])
}

fn read_u32(bytes: &[u8], offset: usize) -> u32 {
    u32::from_be_bytes([
        bytes[offset],
        bytes[offset + 1],
        bytes[offset + 2],
        bytes[offset + 3],
    ])
}

/// Decode one complete message. Certificate DER is bounded but not cryptographically
/// validated here; that is the identity provider's responsibility.
pub fn decode(bytes: &[u8]) -> Result<Message<'_>, WireError> {
    if bytes.len() > MAX_FRAME_LEN {
        return Err(WireError::FrameTooLarge);
    }
    if bytes.len() < 2 {
        return Err(WireError::InvalidLength);
    }
    match read_u16(bytes, 0) {
        1 => {
            if bytes.len() != CHALLENGE_LEN {
                return Err(WireError::InvalidLength);
            }
            let mut tls_hash = [0; HASH_LEN];
            let mut nonce = [0; HASH_LEN];
            tls_hash.copy_from_slice(&bytes[2..50]);
            nonce.copy_from_slice(&bytes[50..98]);
            Ok(Message::Challenge(Challenge { tls_hash, nonce }))
        }
        2 => {
            if bytes.len() < 4 {
                return Err(WireError::InvalidLength);
            }
            let length = usize::from(read_u16(bytes, 2));
            if length == 0 || length > MAX_CERTIFICATE_LEN {
                return Err(WireError::InvalidCertificateLength);
            }
            if bytes.len() < 4 + length {
                return Err(WireError::InvalidLength);
            }
            let proof = CertificateProof {
                certificate_der: &bytes[4..4 + length],
                signature: &bytes[4 + length..],
            };
            proof.validate()?;
            Ok(Message::Certificate(proof))
        }
        3 => {
            if bytes.len() < 70 || bytes.len() == 71 {
                return Err(WireError::InvalidLength);
            }
            let name = if bytes.len() == 70 {
                ""
            } else {
                let length = usize::from(read_u16(bytes, 70));
                if bytes.len() != 72 + length {
                    return Err(WireError::InvalidLength);
                }
                core::str::from_utf8(&bytes[72..]).map_err(|_| WireError::InvalidName)?
            };
            let mut mesh_id = [0; HASH_LEN];
            mesh_id.copy_from_slice(&bytes[18..66]);
            let info = AgentInfo {
                info_version: read_u32(bytes, 2),
                architecture_id: read_u32(bytes, 6),
                agent_version: read_u32(bytes, 10),
                platform_type: read_u32(bytes, 14),
                mesh_id,
                capabilities: read_u32(bytes, 66),
                name,
            };
            info.validate()?;
            Ok(Message::AgentInfo(info))
        }
        4 => {
            if bytes.len() != 2 {
                return Err(WireError::InvalidLength);
            }
            Ok(Message::Authenticated)
        }
        5 => {
            if bytes.len() != 2 + HASH_LEN {
                return Err(WireError::InvalidLength);
            }
            let mut hash = [0; HASH_LEN];
            hash.copy_from_slice(&bytes[2..]);
            Ok(Message::ServerId(hash))
        }
        other => Err(WireError::UnsupportedCommand(other)),
    }
}

impl Message<'_> {
    pub fn encoded_len(&self) -> Result<usize, WireError> {
        Ok(match self {
            Self::Challenge(_) => CHALLENGE_LEN,
            Self::Certificate(proof) => {
                proof.validate()?;
                4 + proof.certificate_der.len() + proof.signature.len()
            }
            Self::AgentInfo(info) => {
                info.validate()?;
                72 + info.name.len()
            }
            Self::Authenticated => 2,
            Self::ServerId(_) => 2 + HASH_LEN,
        })
    }

    /// The output is unchanged on validation or buffer-size errors.
    pub fn encode(&self, output: &mut [u8]) -> Result<usize, WireError> {
        let length = self.encoded_len()?;
        if output.len() < length {
            return Err(WireError::OutputTooSmall);
        }
        let out = &mut output[..length];
        match self {
            Self::Challenge(challenge) => {
                out[..2].copy_from_slice(&1_u16.to_be_bytes());
                out[2..50].copy_from_slice(&challenge.tls_hash);
                out[50..98].copy_from_slice(&challenge.nonce);
            }
            Self::Certificate(proof) => {
                let certificate_len = proof.certificate_der.len();
                out[..2].copy_from_slice(&2_u16.to_be_bytes());
                out[2..4].copy_from_slice(&(certificate_len as u16).to_be_bytes());
                out[4..4 + certificate_len].copy_from_slice(proof.certificate_der);
                out[4 + certificate_len..].copy_from_slice(proof.signature);
            }
            Self::AgentInfo(info) => {
                out[..2].copy_from_slice(&3_u16.to_be_bytes());
                out[2..6].copy_from_slice(&info.info_version.to_be_bytes());
                out[6..10].copy_from_slice(&info.architecture_id.to_be_bytes());
                out[10..14].copy_from_slice(&info.agent_version.to_be_bytes());
                out[14..18].copy_from_slice(&info.platform_type.to_be_bytes());
                out[18..66].copy_from_slice(&info.mesh_id);
                out[66..70].copy_from_slice(&info.capabilities.to_be_bytes());
                out[70..72].copy_from_slice(&(info.name.len() as u16).to_be_bytes());
                out[72..].copy_from_slice(info.name.as_bytes());
            }
            Self::Authenticated => out.copy_from_slice(&4_u16.to_be_bytes()),
            Self::ServerId(hash) => {
                out[..2].copy_from_slice(&5_u16.to_be_bytes());
                out[2..].copy_from_slice(hash);
            }
        }
        Ok(length)
    }
}
