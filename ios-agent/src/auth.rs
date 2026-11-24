// SPDX-License-Identifier: Apache-2.0
//! Authentication sequencing, not a cryptographic implementation.

use crate::session::AssistanceSession;
use crate::wire::{self, AgentInfo, CertificateProof, Challenge, HASH_LEN, Message, WireError};

pub const TRANSCRIPT_LEN: usize = HASH_LEN * 3;

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum IdentityError {
    InvalidCertificate,
    UntrustedServer,
    InvalidSignature,
    SigningFailed,
}

/// Trusted adapter implemented by an audited crypto/platform layer.
///
/// `verify_server` MUST validate the X.509 RSA key, SHA-384 of its PKCS#1 DER
/// against `expected_server_id`, AND the RSA PKCS#1 v1.5 / SHA-384 signature of
/// `transcript`. Trusting any presented key or returning success unconditionally
/// breaks authentication. The Apple implementation lives in `apple/`, connected
/// through the separate C ABI crate; this portable crate has no crypto backend.
pub trait IdentityProvider {
    fn verify_server(
        &mut self,
        expected_server_id: &[u8; HASH_LEN],
        proof: CertificateProof<'_>,
        transcript: &[u8; TRANSCRIPT_LEN],
    ) -> Result<(), IdentityError>;

    /// Stable device X.509 certificate; never expose its private key to the core.
    fn agent_certificate_der(&self) -> &[u8];

    /// Sign the message (not an already hashed digest) using RSA PKCS#1 v1.5
    /// with SHA-384. Return 256 or 384 bytes matching the certificate's key.
    fn sign_agent(
        &mut self,
        transcript: &[u8; TRANSCRIPT_LEN],
        output: &mut [u8; wire::MAX_SIGNATURE_LEN],
    ) -> Result<usize, IdentityError>;
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum Phase {
    AwaitChallenge,
    AwaitServerProof,
    ServerVerified,
    AwaitAcknowledgment,
    Authenticated,
    Closed,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum AuthError {
    Wire(WireError),
    Identity(IdentityError),
    UnexpectedMessage,
    TlsBindingMismatch,
    InvalidNonce,
    MissingServerIdentity,
    UnsupportedCapabilities,
    NotAuthenticated,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum Progress {
    ChallengeAccepted,
    ServerVerified,
    Authenticated,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct RegistrationLengths {
    pub identity: usize,
    pub info: usize,
}

/// One authenticated TLS/WebSocket connection, never reusable after closure.
///
/// Before constructing, the host MUST validate TLS/hostname, obtain the actual
/// peer-certificate SHA-384, load a trusted enrollment pin, and generate a fresh
/// 48-byte cryptographically random nonce. Nonzero checks cannot prove entropy.
/// The transport must close this object on timeout, I/O failure or disconnect.
pub struct Handshake {
    phase: Phase,
    tls_hash: [u8; HASH_LEN],
    server_id: [u8; HASH_LEN],
    agent_nonce: [u8; HASH_LEN],
    server_nonce: [u8; HASH_LEN],
}

impl Handshake {
    pub fn new(
        tls_hash: [u8; HASH_LEN],
        server_id: [u8; HASH_LEN],
        agent_nonce: [u8; HASH_LEN],
    ) -> Result<Self, AuthError> {
        if tls_hash == [0; HASH_LEN] || server_id == [0; HASH_LEN] {
            return Err(AuthError::MissingServerIdentity);
        }
        if agent_nonce == [0; HASH_LEN] {
            return Err(AuthError::InvalidNonce);
        }
        Ok(Self {
            phase: Phase::AwaitChallenge,
            tls_hash,
            server_id,
            agent_nonce,
            server_nonce: [0; HASH_LEN],
        })
    }

    pub fn phase(&self) -> Phase {
        self.phase
    }

    /// Encode once and send as a binary WebSocket message at connection start.
    pub fn hello(&self, output: &mut [u8]) -> Result<usize, AuthError> {
        if self.phase != Phase::AwaitChallenge {
            return Err(AuthError::UnexpectedMessage);
        }
        Message::Challenge(Challenge {
            tls_hash: self.tls_hash,
            nonce: self.agent_nonce,
        })
        .encode(output)
        .map_err(AuthError::Wire)
    }

    /// Consume a server handshake frame. Any error permanently closes the state.
    pub fn receive(
        &mut self,
        frame: &[u8],
        identity: &mut impl IdentityProvider,
    ) -> Result<Progress, AuthError> {
        let result = self.receive_inner(frame, identity);
        if result.is_err() {
            self.close();
        }
        result
    }

    fn receive_inner(
        &mut self,
        frame: &[u8],
        identity: &mut impl IdentityProvider,
    ) -> Result<Progress, AuthError> {
        match (self.phase, wire::decode(frame).map_err(AuthError::Wire)?) {
            (Phase::AwaitChallenge, Message::Challenge(challenge)) => {
                if challenge.tls_hash != self.tls_hash {
                    return Err(AuthError::TlsBindingMismatch);
                }
                if challenge.nonce == [0; HASH_LEN] || challenge.nonce == self.agent_nonce {
                    return Err(AuthError::InvalidNonce);
                }
                self.server_nonce = challenge.nonce;
                self.phase = Phase::AwaitServerProof;
                Ok(Progress::ChallengeAccepted)
            }
            (Phase::AwaitServerProof, Message::Certificate(proof)) => {
                identity
                    .verify_server(&self.server_id, proof, &self.transcript(true))
                    .map_err(AuthError::Identity)?;
                self.phase = Phase::ServerVerified;
                Ok(Progress::ServerVerified)
            }
            (Phase::AwaitAcknowledgment, Message::Authenticated) => {
                self.phase = Phase::Authenticated;
                Ok(Progress::Authenticated)
            }
            _ => Err(AuthError::UnexpectedMessage),
        }
    }

    fn transcript(&self, server: bool) -> [u8; TRANSCRIPT_LEN] {
        let mut result = [0; TRANSCRIPT_LEN];
        result[..48].copy_from_slice(&self.tls_hash);
        let (first, second) = if server {
            (&self.agent_nonce, &self.server_nonce)
        } else {
            (&self.server_nonce, &self.agent_nonce)
        };
        result[48..96].copy_from_slice(first);
        result[96..144].copy_from_slice(second);
        result
    }

    /// Prepare command 2 then command 3, as SEPARATE binary WebSocket messages.
    /// Send neither output unless this returns Ok. Close on either send failure.
    /// This milestone only permits capabilities zero (no implemented services).
    pub fn prepare_registration(
        &mut self,
        identity: &mut impl IdentityProvider,
        info: AgentInfo<'_>,
        proof_output: &mut [u8],
        info_output: &mut [u8],
    ) -> Result<RegistrationLengths, AuthError> {
        let result = self.registration_inner(identity, info, proof_output, info_output);
        if result.is_err() {
            self.close();
        }
        result
    }

    fn registration_inner(
        &mut self,
        identity: &mut impl IdentityProvider,
        info: AgentInfo<'_>,
        proof_output: &mut [u8],
        info_output: &mut [u8],
    ) -> Result<RegistrationLengths, AuthError> {
        if self.phase != Phase::ServerVerified {
            return Err(AuthError::UnexpectedMessage);
        }
        if info.capabilities != 0 {
            return Err(AuthError::UnsupportedCapabilities);
        }
        let info_message = Message::AgentInfo(info);
        let info_len = info_message.encoded_len().map_err(AuthError::Wire)?;
        if info_output.len() < info_len {
            return Err(AuthError::Wire(WireError::OutputTooSmall));
        }
        let mut signature = [0; wire::MAX_SIGNATURE_LEN];
        let signature_len = identity
            .sign_agent(&self.transcript(false), &mut signature)
            .map_err(AuthError::Identity)?;
        // Validate before slicing: even a broken adapter cannot cause a panic.
        if !matches!(signature_len, 256 | 384) {
            return Err(AuthError::Wire(WireError::UnsupportedSignatureLength));
        }
        let proof = Message::Certificate(CertificateProof {
            certificate_der: identity.agent_certificate_der(),
            signature: &signature[..signature_len],
        });
        let identity_len = proof.encode(proof_output).map_err(AuthError::Wire)?;
        info_message.encode(info_output).map_err(AuthError::Wire)?;
        self.phase = Phase::AwaitAcknowledgment;
        Ok(RegistrationLengths {
            identity: identity_len,
            info: info_len,
        })
    }

    /// Consume the handshake; a consent gate cannot exist before server acceptance.
    pub fn into_session(self) -> Result<AssistanceSession, AuthError> {
        if self.phase != Phase::Authenticated {
            return Err(AuthError::NotAuthenticated);
        }
        Ok(AssistanceSession::authenticated(self.agent_nonce))
    }

    pub fn close(&mut self) {
        self.phase = Phase::Closed;
    }
}
