// SPDX-License-Identifier: Apache-2.0
use meshcentral_ios_core::certificate::*;

fn public_key() -> [u8; 270] {
    let mut key = [1; 270];
    key[0] = 0x30;
    key
}

#[test]
fn dates_serial_and_key_bounds_are_validated() {
    let key = public_key();
    let mut output = [0; MAX_DER];
    for before in [
        b"20260230000000Z",
        b"20261301000000Z",
        b"20260101240000Z",
        b"20260101006000Z",
        b"20260101000060Z",
        b"20260101000000X",
    ] {
        assert_eq!(
            build_tbs(&key, &[1; 16], before, b"20310101000000Z", &mut output),
            Err(CertificateError::InvalidInput)
        );
    }
    assert!(
        build_tbs(
            &key,
            &[1; 16],
            b"20240229000000Z",
            b"20310101000000Z",
            &mut output
        )
        .is_ok()
    );
    assert!(
        build_tbs(
            &key,
            &[1; 16],
            b"20230229000000Z",
            b"20310101000000Z",
            &mut output
        )
        .is_err()
    );
    assert!(
        build_tbs(
            &key,
            &[0; 16],
            b"20260101000000Z",
            b"20310101000000Z",
            &mut output
        )
        .is_err()
    );
    assert!(
        build_tbs(
            &key[..255],
            &[1; 16],
            b"20260101000000Z",
            b"20310101000000Z",
            &mut output
        )
        .is_err()
    );
    assert!(
        build_tbs(
            &key,
            &[1; 16],
            b"20310101000000Z",
            b"20260101000000Z",
            &mut output
        )
        .is_err()
    );
}

#[test]
fn utc_time_switches_to_generalized_time_in_2050() {
    let key = public_key();
    let mut output = [0; MAX_DER];
    let count = build_tbs(
        &key,
        &[0xff; 16],
        b"20490101000000Z",
        b"20500101000000Z",
        &mut output,
    )
    .unwrap();
    assert!(
        output[..count]
            .windows(15)
            .any(|v| v == b"\x17\x0d490101000000Z")
    );
    assert!(
        output[..count]
            .windows(17)
            .any(|v| v == b"\x18\x0f20500101000000Z")
    );
    // Positive serials with the high bit set receive a leading zero octet.
    assert!(output[..count].windows(3).any(|v| v == [2, 17, 0]));
}

#[test]
fn tiny_output_and_oversized_signature_fail_without_writing() {
    let mut output = [0xaa; 1];
    assert_eq!(
        build_tbs(
            &public_key(),
            &[1; 16],
            b"20260101000000Z",
            b"20310101000000Z",
            &mut output
        ),
        Err(CertificateError::OutputTooSmall)
    );
    assert_eq!(output, [0xaa]);
    assert_eq!(
        finish(&[0x30, 0], &[0; 385], &mut [0; MAX_DER]),
        Err(CertificateError::InvalidInput)
    );
}
