// SPDX-License-Identifier: Apache-2.0
// Test-only protocol adapter. It does NOT verify certificates or signatures.
#![allow(dead_code)]

use meshcentral_ios_core::auth::{Handshake, IdentityError, IdentityProvider, TRANSCRIPT_LEN};
use meshcentral_ios_core::wire::{AgentInfo, CertificateProof, Challenge, MAX_FRAME_LEN, Message};

pub struct TestIdentity {
    pub failure: Option<IdentityError>,
    pub signature_length: usize,
    pub fail_signing: bool,
    pub verified: bool,
    pub signed: bool,
    pub agent_nonce: u8,
}

impl Default for TestIdentity {
    fn default() -> Self {
        Self {
            failure: None,
            signature_length: 256,
            fail_signing: false,
            verified: false,
            signed: false,
            agent_nonce: 0x33,
        }
    }
}

impl IdentityProvider for TestIdentity {
    fn verify_server(
        &mut self,
        expected_server_id: &[u8; 48],
        proof: CertificateProof<'_>,
        transcript: &[u8; TRANSCRIPT_LEN],
    ) -> Result<(), IdentityError> {
        assert_eq!(expected_server_id, &[0x22; 48]);
        assert_eq!(&transcript[..48], &[0x11; 48]);
        assert_eq!(&transcript[48..96], &[self.agent_nonce; 48]);
        assert_eq!(&transcript[96..], &[0x44; 48]);
        assert_eq!(proof.certificate_der, &[0x30, 0x01, 0x00]);
        assert_eq!(proof.signature, &[0x55; 256]);
        self.verified = true;
        self.failure.map_or(Ok(()), Err)
    }

    fn agent_certificate_der(&self) -> &[u8] {
        &[0x30, 0x01, 0x00]
    }

    fn sign_agent(
        &mut self,
        transcript: &[u8; TRANSCRIPT_LEN],
        output: &mut [u8; 384],
    ) -> Result<usize, IdentityError> {
        assert!(self.verified, "Must not sign before verifying the server");
        assert_eq!(&transcript[..48], &[0x11; 48]);
        assert_eq!(&transcript[48..96], &[0x44; 48]);
        assert_eq!(&transcript[96..], &[self.agent_nonce; 48]);
        self.signed = true;
        output.fill(0x66);
        if self.fail_signing {
            Err(IdentityError::SigningFailed)
        } else {
            Ok(self.signature_length)
        }
    }
}

pub fn info() -> AgentInfo<'static> {
    AgentInfo {
        info_version: 1,
        architecture_id: 0xffff_fff0, // Synthetic fixture ID, never an assigned iOS ID.
        agent_version: 1,
        platform_type: 1,
        mesh_id: [0x77; 48],
        capabilities: 0,
        name: "iPhone de Chloé",
    }
}

pub fn encode(message: Message<'_>) -> Vec<u8> {
    let mut result = vec![0; MAX_FRAME_LEN];
    let length = message.encode(&mut result).unwrap();
    result.truncate(length);
    result
}

pub fn challenge() -> Vec<u8> {
    encode(Message::Challenge(Challenge {
        tls_hash: [0x11; 48],
        nonce: [0x44; 48],
    }))
}

pub fn proof() -> Vec<u8> {
    encode(Message::Certificate(CertificateProof {
        certificate_der: &[0x30, 0x01, 0],
        signature: &[0x55; 256],
    }))
}

pub fn handshake() -> Handshake {
    Handshake::new([0x11; 48], [0x22; 48], [0x33; 48]).unwrap()
}

pub fn verified(identity: &mut TestIdentity) -> Handshake {
    let mut h = Handshake::new([0x11; 48], [0x22; 48], [identity.agent_nonce; 48]).unwrap();
    h.receive(&challenge(), identity).unwrap();
    h.receive(&proof(), identity).unwrap();
    h
}

pub fn authenticated(nonce: u8) -> Handshake {
    let mut identity = TestIdentity {
        agent_nonce: nonce,
        ..Default::default()
    };
    let mut h = verified(&mut identity);
    h.prepare_registration(
        &mut identity,
        info(),
        &mut [0; MAX_FRAME_LEN],
        &mut [0; 327],
    )
    .unwrap();
    h.receive(&[0, 4], &mut identity).unwrap();
    h
}
