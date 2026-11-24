// SPDX-License-Identifier: Apache-2.0
mod support;

use meshcentral_ios_core::wire::*;
use support::{encode, info};

#[test]
fn challenge_matches_the_fixed_wire_layout() {
    let bytes = encode(Message::Challenge(Challenge {
        tls_hash: [0x11; 48],
        nonce: [0x33; 48],
    }));
    assert_eq!(bytes.len(), 98);
    assert_eq!(&bytes[..2], &[0, 1]);
    assert_eq!(&bytes[2..50], &[0x11; 48]);
    assert_eq!(&bytes[50..], &[0x33; 48]);
    assert!(matches!(decode(&bytes), Ok(Message::Challenge(_))));
    for length in 0..bytes.len() {
        assert!(decode(&bytes[..length]).is_err());
    }
    let mut extended = bytes;
    extended.push(0);
    assert_eq!(decode(&extended).err(), Some(WireError::InvalidLength));
}

#[test]
fn registration_is_big_endian_and_counts_utf8_bytes() {
    let bytes = encode(Message::AgentInfo(info()));
    assert_eq!(&bytes[..10], &[0, 3, 0, 0, 0, 1, 255, 255, 255, 240]);
    assert_eq!(&bytes[18..66], &[0x77; 48]);
    assert_eq!(&bytes[66..70], &[0; 4]);
    assert_eq!(&bytes[70..72], &[0, 16]);
    assert_eq!(&bytes[72..], "iPhone de Chloé".as_bytes());
    match decode(&bytes).unwrap() {
        Message::AgentInfo(parsed) => {
            assert_eq!(parsed.architecture_id, 0xffff_fff0);
            assert_eq!(parsed.name, "iPhone de Chloé");
        }
        _ => panic!("wrong message"),
    }
    for length in 0..bytes.len() {
        if length != 70 {
            assert!(decode(&bytes[..length]).is_err());
        }
    }
    assert!(matches!(
        decode(&bytes[..70]),
        Ok(Message::AgentInfo(AgentInfo { name: "", .. }))
    ));
}

#[test]
fn registration_rejects_ambiguous_mesh_ids_and_bad_metadata() {
    let mut value = info();
    value.mesh_id[32..].fill(0);
    assert_eq!(value.validate(), Err(WireError::LegacyMeshId));
    value = info();
    value.platform_type = 9;
    assert_eq!(value.validate(), Err(WireError::InvalidPlatform));
    value = info();
    value.name = "name\noperator";
    assert_eq!(value.validate(), Err(WireError::InvalidName));
    let long = "é".repeat(128);
    value.name = &long;
    assert_eq!(value.validate(), Err(WireError::InvalidName));
    let mut bytes = encode(Message::AgentInfo(info()));
    bytes[72] = 0xff;
    assert_eq!(decode(&bytes).err(), Some(WireError::InvalidName));
    let mut bytes = encode(Message::AgentInfo(info()));
    bytes.push(0);
    assert_eq!(decode(&bytes).err(), Some(WireError::InvalidLength));
}

#[test]
fn certificate_lengths_are_checked_before_slicing() {
    let bytes = support::proof();
    assert_eq!(&bytes[..4], &[0, 2, 0, 3]);
    assert_eq!(bytes.len(), 263);
    for length in 0..bytes.len() {
        assert!(decode(&bytes[..length]).is_err());
    }
    assert!(matches!(decode(&bytes), Ok(Message::Certificate(_))));
    assert_eq!(
        decode(&[0, 2, 255, 255]).err(),
        Some(WireError::InvalidCertificateLength)
    );
    assert_eq!(
        decode(&[0, 2, 0, 5, 1]).err(),
        Some(WireError::InvalidLength)
    );
    assert_eq!(
        decode(&[0, 2, 0, 0]).err(),
        Some(WireError::InvalidCertificateLength)
    );
    let bytes = encode(Message::Certificate(CertificateProof {
        certificate_der: &[1],
        signature: &[2; 384],
    }));
    assert!(decode(&bytes).is_ok());
    let mut invalid = bytes;
    invalid.push(0);
    assert_eq!(
        decode(&invalid).err(),
        Some(WireError::UnsupportedSignatureLength)
    );
}

#[test]
fn invalid_outputs_and_short_buffers_do_not_modify_the_buffer() {
    let mut output = [0x88; 97];
    let message = Message::Challenge(Challenge {
        tls_hash: [1; 48],
        nonce: [2; 48],
    });
    assert_eq!(message.encode(&mut output), Err(WireError::OutputTooSmall));
    assert_eq!(output, [0x88; 97]);
    let invalid = Message::Certificate(CertificateProof {
        certificate_der: &[],
        signature: &[1; 256],
    });
    assert_eq!(
        invalid.encode(&mut output),
        Err(WireError::InvalidCertificateLength)
    );
    assert_eq!(output, [0x88; 97]);
}

#[test]
fn reject_oversized_unknown_and_padded_acknowledgments() {
    assert_eq!(
        decode(&vec![0; MAX_FRAME_LEN + 1]).err(),
        Some(WireError::FrameTooLarge)
    );
    assert_eq!(
        decode(&[0, 10]).err(),
        Some(WireError::UnsupportedCommand(10))
    );
    assert_eq!(decode(&[0, 4, 0]).err(), Some(WireError::InvalidLength));
    assert!(matches!(decode(&[0, 4]), Ok(Message::Authenticated)));
    let id = encode(Message::ServerId([0x42; 48]));
    assert_eq!(&id[..2], &[0, 5]);
    assert!(matches!(decode(&id), Ok(Message::ServerId(_))));
    assert!(decode(&id[..34]).is_err()); // Legacy SHA-256 not supported.
}

#[test]
fn arbitrary_short_frames_do_not_panic() {
    let mut seed = 0x1274_8169_u32;
    let mut frame = [0; 512];
    for length in 0..=frame.len() {
        for byte in &mut frame[..length] {
            seed = seed.wrapping_mul(1664525).wrapping_add(1013904223);
            *byte = (seed >> 24) as u8;
        }
        if length >= 2 {
            for command in 1_u16..=5 {
                frame[..2].copy_from_slice(&command.to_be_bytes());
                let _ = decode(&frame[..length]);
            }
        } else {
            let _ = decode(&frame[..length]);
        }
    }
}
