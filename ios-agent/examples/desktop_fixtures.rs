// SPDX-License-Identifier: Apache-2.0
//! Original non-image fixtures: validate framing through the real browser parser.
use meshcentral_ios_core::desktop::{jpeg_tile, screen_size};
fn print(name: &str, bytes: &[u8]) {
    print!("{name} ");
    for byte in bytes {
        print!("{byte:02x}");
    }
    println!();
}
fn main() {
    let mut size = [0; 8];
    screen_size(720, 1280, &mut size).unwrap();
    print("size", &size);
    for n in [32, 65527, 65528, 90000] {
        let mut jpeg = vec![0x42; n];
        jpeg[..2].copy_from_slice(&[255, 216]);
        jpeg[n - 2..].copy_from_slice(&[255, 217]);
        let mut packet = vec![0; n + 16];
        let len = jpeg_tile(&jpeg, &mut packet).unwrap();
        print(&format!("jpeg{n}"), &packet[..len]);
    }
}
