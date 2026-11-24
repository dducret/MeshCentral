// SPDX-License-Identifier: Apache-2.0
//! Portable foundation; no transport or production cryptography is included.
//!
//! The host must enforce TLS trust, message limits before buffering, deadlines,
//! and authenticated relay ownership. See `docs/protocol.md` for adapter contracts.
#![no_std]
#![forbid(unsafe_code)]

pub mod assistance;
pub mod auth;
pub mod certificate;
pub mod desktop;
pub mod inventory;
pub mod messenger;
pub mod session;
pub mod wire;
