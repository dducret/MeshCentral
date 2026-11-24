// SPDX-License-Identifier: Apache-2.0
//! Deterministic, non-secret codec fixtures for the local Node interoperability check.
use meshcentral_ios_core::wire::{AgentInfo, Challenge, MAX_FRAME_LEN, Message};

fn print_frame(name: &str, message: Message<'_>) {
    let mut buffer = [0; MAX_FRAME_LEN];
    let length = message.encode(&mut buffer).expect("valid test fixture");
    print!("{name} ");
    for byte in &buffer[..length] {
        print!("{byte:02x}");
    }
    println!();
}

fn main() {
    print_frame(
        "challenge",
        Message::Challenge(Challenge {
            tls_hash: [0x11; 48],
            nonce: [0x33; 48],
        }),
    );
    print_frame(
        "info",
        Message::AgentInfo(AgentInfo {
            info_version: 1,
            architecture_id: 0xffff_fff0,
            agent_version: 1,
            platform_type: 1,
            mesh_id: [0x77; 48],
            capabilities: 0,
            name: "iPhone de Chloé",
        }),
    );
}
