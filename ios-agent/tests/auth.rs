// SPDX-License-Identifier: Apache-2.0
mod support;

use meshcentral_ios_core::auth::*;
use meshcentral_ios_core::wire::{self, MAX_FRAME_LEN, Message, WireError};
use support::*;

#[test]
fn ordered_handshake_binds_both_transcripts_and_waits_for_server_ack() {
    let mut provider = TestIdentity::default();
    let mut h = handshake();
    let mut hello = [0; 98];
    assert_eq!(h.hello(&mut hello), Ok(98));
    assert_eq!(&hello[50..], &[0x33; 48]);
    assert_eq!(
        h.receive(&challenge(), &mut provider),
        Ok(Progress::ChallengeAccepted)
    );
    assert!(!provider.verified);
    assert_eq!(
        h.receive(&proof(), &mut provider),
        Ok(Progress::ServerVerified)
    );
    assert!(provider.verified);
    assert!(!provider.signed);
    let mut identity_frame = [0; MAX_FRAME_LEN];
    let mut info_frame = [0; 327];
    let lengths = h
        .prepare_registration(&mut provider, info(), &mut identity_frame, &mut info_frame)
        .unwrap();
    assert!(provider.signed);
    assert_eq!(h.phase(), Phase::AwaitAcknowledgment);
    match wire::decode(&identity_frame[..lengths.identity]).unwrap() {
        Message::Certificate(value) => assert_eq!(value.signature, &[0x66; 256]),
        _ => panic!("wrong message"),
    }
    assert!(matches!(
        wire::decode(&info_frame[..lengths.info]),
        Ok(Message::AgentInfo(_))
    ));
    assert_eq!(
        h.receive(&[0, 4], &mut provider),
        Ok(Progress::Authenticated)
    );
    assert!(h.into_session().is_ok());
}

#[test]
fn failed_server_pin_certificate_or_signature_closes_without_signing() {
    for failure in [
        IdentityError::UntrustedServer,
        IdentityError::InvalidCertificate,
        IdentityError::InvalidSignature,
    ] {
        let mut provider = TestIdentity {
            failure: Some(failure),
            ..Default::default()
        };
        let mut h = handshake();
        h.receive(&challenge(), &mut provider).unwrap();
        assert_eq!(
            h.receive(&proof(), &mut provider),
            Err(AuthError::Identity(failure))
        );
        assert_eq!(h.phase(), Phase::Closed);
        assert!(!provider.signed);
        assert!(h.receive(&challenge(), &mut provider).is_err());
        assert!(h.into_session().is_err());
    }
}

#[test]
fn early_acknowledgment_and_out_of_order_proof_close_the_handshake() {
    for frame in [vec![0, 4], proof()] {
        let mut h = handshake();
        assert_eq!(
            h.receive(&frame, &mut TestIdentity::default()),
            Err(AuthError::UnexpectedMessage)
        );
        assert_eq!(h.phase(), Phase::Closed);
    }
    let mut provider = TestIdentity::default();
    let mut h = verified(&mut provider);
    assert_eq!(
        h.receive(&[0, 4], &mut provider),
        Err(AuthError::UnexpectedMessage)
    );
    assert!(!provider.signed);
}

#[test]
fn duplicate_challenges_and_proofs_are_rejected() {
    let mut provider = TestIdentity::default();
    let mut h = handshake();
    h.receive(&challenge(), &mut provider).unwrap();
    assert!(h.receive(&challenge(), &mut provider).is_err());
    assert_eq!(h.phase(), Phase::Closed);
    let mut h = verified(&mut provider);
    assert!(h.receive(&proof(), &mut provider).is_err());
    assert_eq!(h.phase(), Phase::Closed);
}

#[test]
fn tls_hash_mismatch_reflection_and_missing_nonce_are_rejected() {
    let mut frame = challenge();
    frame[2] ^= 1;
    let mut h = handshake();
    assert_eq!(
        h.receive(&frame, &mut TestIdentity::default()),
        Err(AuthError::TlsBindingMismatch)
    );
    for nonce in [0, 0x33] {
        let mut frame = challenge();
        frame[50..].fill(nonce);
        let mut h = handshake();
        assert_eq!(
            h.receive(&frame, &mut TestIdentity::default()),
            Err(AuthError::InvalidNonce)
        );
    }
    assert!(matches!(
        Handshake::new([1; 48], [2; 48], [0; 48]),
        Err(AuthError::InvalidNonce)
    ));
    assert!(matches!(
        Handshake::new([0; 48], [2; 48], [3; 48]),
        Err(AuthError::MissingServerIdentity)
    ));
    assert!(matches!(
        Handshake::new([1; 48], [0; 48], [3; 48]),
        Err(AuthError::MissingServerIdentity)
    ));
}

#[test]
fn malformed_frame_is_terminal() {
    let mut h = handshake();
    assert_eq!(
        h.receive(&[0], &mut TestIdentity::default()),
        Err(AuthError::Wire(WireError::InvalidLength))
    );
    assert_eq!(h.phase(), Phase::Closed);
    assert!(h.into_session().is_err());
}

#[test]
fn provider_signing_failures_and_invalid_lengths_fail_closed() {
    for length in [0, 255, 385, usize::MAX] {
        let mut provider = TestIdentity {
            signature_length: length,
            ..Default::default()
        };
        let mut h = verified(&mut provider);
        assert_eq!(
            h.prepare_registration(
                &mut provider,
                info(),
                &mut [0; MAX_FRAME_LEN],
                &mut [0; 327]
            ),
            Err(AuthError::Wire(WireError::UnsupportedSignatureLength))
        );
        assert_eq!(h.phase(), Phase::Closed);
    }
    let mut provider = TestIdentity {
        fail_signing: true,
        ..Default::default()
    };
    let mut h = verified(&mut provider);
    assert_eq!(
        h.prepare_registration(
            &mut provider,
            info(),
            &mut [0; MAX_FRAME_LEN],
            &mut [0; 327]
        ),
        Err(AuthError::Identity(IdentityError::SigningFailed))
    );
    assert_eq!(h.phase(), Phase::Closed);
}

#[test]
fn no_unimplemented_capabilities_can_be_registered() {
    let mut provider = TestIdentity::default();
    let mut h = verified(&mut provider);
    let mut data = info();
    data.capabilities = 1;
    assert_eq!(
        h.prepare_registration(&mut provider, data, &mut [0; MAX_FRAME_LEN], &mut [0; 327]),
        Err(AuthError::UnsupportedCapabilities)
    );
    assert!(!provider.signed);
    assert_eq!(h.phase(), Phase::Closed);
}

#[test]
fn local_output_failure_does_not_produce_a_sendable_registration() {
    let mut provider = TestIdentity::default();
    let mut h = verified(&mut provider);
    let mut output = [0x88; MAX_FRAME_LEN];
    assert_eq!(
        h.prepare_registration(&mut provider, info(), &mut output, &mut [0; 1]),
        Err(AuthError::Wire(WireError::OutputTooSmall))
    );
    assert_eq!(output, [0x88; MAX_FRAME_LEN]);
    assert!(!provider.signed);
    assert_eq!(h.phase(), Phase::Closed);
}

#[test]
fn session_requires_ack_and_closed_handshakes_cannot_reconnect() {
    assert!(handshake().into_session().is_err());
    assert!(
        verified(&mut TestIdentity::default())
            .into_session()
            .is_err()
    );
    let mut h = authenticated(0x33);
    h.close();
    assert!(h.hello(&mut [0; 98]).is_err());
    assert!(h.into_session().is_err());
    assert!(authenticated(0x34).into_session().is_ok());
}
