// SPDX-License-Identifier: Apache-2.0
//! Bounded, read-only MeshCentral desktop frames. JPEG encoding belongs to the SDK.

pub const MAX_JPEG: usize = 512 * 1024;
pub const MAX_DIMENSION: u16 = 1920;
pub const MAX_PACKET: usize = MAX_JPEG + 16;

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum DesktopError {
    InvalidDimensions,
    InvalidImage,
    BufferTooSmall,
}

pub fn permits_view(rights: u32) -> bool {
    rights == u32::MAX || (rights & 0x108 != 0 && rights & 0x10000 == 0)
}

pub fn screen_size(width: u16, height: u16, out: &mut [u8]) -> Result<usize, DesktopError> {
    if width == 0 || height == 0 || width > MAX_DIMENSION || height > MAX_DIMENSION {
        return Err(DesktopError::InvalidDimensions);
    }
    if out.len() < 8 {
        return Err(DesktopError::BufferTooSmall);
    }
    out[..4].copy_from_slice(&[0, 7, 0, 8]);
    out[4..6].copy_from_slice(&width.to_be_bytes());
    out[6..8].copy_from_slice(&height.to_be_bytes());
    Ok(8)
}

/// A complete JPEG at origin (0,0), wrapped in command 27 when exceeding u16.
/// Signature checks are bounds/sanity checks, not a JPEG decoder or validator.
pub fn jpeg_tile(jpeg: &[u8], out: &mut [u8]) -> Result<usize, DesktopError> {
    if jpeg.len() < 4
        || jpeg.len() > MAX_JPEG
        || !jpeg.starts_with(&[0xff, 0xd8])
        || !jpeg.ends_with(&[0xff, 0xd9])
    {
        return Err(DesktopError::InvalidImage);
    }
    let inner = jpeg.len() + 8;
    let jumbo = inner > u16::MAX as usize;
    let total = inner + if jumbo { 8 } else { 0 };
    if out.len() < total {
        return Err(DesktopError::BufferTooSmall);
    }
    let offset = if jumbo {
        out[..4].copy_from_slice(&[0, 27, 0, 8]);
        out[4..8].copy_from_slice(&(inner as u32).to_be_bytes());
        8
    } else {
        0
    };
    out[offset..offset + 2].copy_from_slice(&[0, 3]);
    out[offset + 2..offset + 4]
        .copy_from_slice(&(if jumbo { 0 } else { inner as u16 }).to_be_bytes());
    out[offset + 4..offset + 8].fill(0);
    out[offset + 8..total].copy_from_slice(jpeg);
    Ok(total)
}
