// SPDX-License-Identifier: Apache-2.0
use meshcentral_ios_core::desktop::*;

#[test]
fn size_is_network_order_and_invalid_dimensions_do_not_write() {
    let mut out = [0xaa; 8];
    assert_eq!(screen_size(720, 1280, &mut out), Ok(8));
    assert_eq!(out, [0, 7, 0, 8, 2, 208, 5, 0]);
    for (w, h) in [(0, 1), (1, 0), (1921, 1), (1, 65535)] {
        out.fill(0xaa);
        assert!(screen_size(w, h, &mut out).is_err());
        assert_eq!(out, [0xaa; 8]);
    }
}

#[test]
fn jpeg_standard_and_jumbo_boundaries() {
    for n in [4, 65527, 65528, MAX_JPEG] {
        let mut jpeg = vec![0; n];
        jpeg[..2].copy_from_slice(&[255, 216]);
        jpeg[n - 2..].copy_from_slice(&[255, 217]);
        let mut out = vec![0xaa; n + 16];
        let count = jpeg_tile(&jpeg, &mut out).unwrap();
        let offset = if n + 8 > 65535 { 8 } else { 0 };
        assert_eq!(count, n + 8 + offset);
        if offset == 8 {
            assert_eq!(&out[..4], &[0, 27, 0, 8]);
            assert_eq!(
                u32::from_be_bytes(out[4..8].try_into().unwrap()),
                (n + 8) as u32
            );
            assert_eq!(&out[10..12], &[0, 0]);
        } else {
            assert_eq!(
                u16::from_be_bytes(out[2..4].try_into().unwrap()),
                (n + 8) as u16
            );
        }
        assert_eq!(&out[offset..offset + 2], &[0, 3]);
        assert_eq!(&out[offset + 4..offset + 8], &[0, 0, 0, 0]);
        assert_eq!(&out[offset + 8..count], jpeg);
    }
}

#[test]
fn invalid_jpeg_and_short_output_fail_without_partial_write() {
    let mut out = [0xaa; 16];
    for jpeg in [vec![], vec![255, 216, 0, 0], vec![0; MAX_JPEG + 1]] {
        assert!(jpeg_tile(&jpeg, &mut out).is_err());
        assert_eq!(out, [0xaa; 16]);
    }
    assert_eq!(
        jpeg_tile(&[255, 216, 255, 217], &mut out[..11]),
        Err(DesktopError::BufferTooSmall)
    );
    assert_eq!(out, [0xaa; 16]);
}

#[test]
fn rights_require_remote_control_and_respect_no_desktop_except_admin() {
    assert!(permits_view(8));
    assert!(permits_view(256));
    assert!(permits_view(u32::MAX));
    assert!(!permits_view(0));
    assert!(!permits_view(0x10008));
    assert!(!permits_view(0x200000));
}
