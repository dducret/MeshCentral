// SPDX-License-Identifier: Apache-2.0
//! MeshMessenger invitation binding and explicit local consent for a single call.

pub fn valid_invitation(id: &[u8], node: &[u8], user: &[u8], rights: u32) -> bool {
    if rights & 0x4000 == 0 || rights & 0x108 == 0 || id.len() > 1024 {
        return false;
    }
    let (Ok(node), Ok(user)) = (core::str::from_utf8(node), core::str::from_utf8(user)) else {
        return false;
    };
    let mut n = node.split('/');
    let mut u = user.split('/');
    if n.next() != Some("node") || u.next() != Some("user") || n.next() != u.next() {
        return false;
    }
    let (Some(key), Some(name)) = (n.next(), u.next()) else {
        return false;
    };
    if n.next().is_some()
        || u.next().is_some()
        || key.len() != 64
        || !key
            .bytes()
            .all(|b| b.is_ascii_alphanumeric() || b == b'@' || b == b'$')
        || name.is_empty()
        || user.len() > 512
        || user.chars().any(char::is_control)
    {
        return false;
    }
    id.iter().copied().eq(b"meshmessenger/"
        .iter()
        .copied()
        .chain(node.bytes())
        .chain(core::iter::once(b'/'))
        .chain(user.bytes()))
}

/// Unique invitation owner. Time is monotonic elapsed since receipt, not reset on acceptance.
#[derive(Default)]
pub struct Messenger {
    state: u32,
    background_audio: bool,
}
impl Messenger {
    /// 0=foreground poll, 1=local accept, 2=stop, 3=local accept with background audio,
    /// 4=background poll with live two-way audio, 5=background poll with media
    /// paused after an established call. For both, the platform verifies the
    /// existing relay and authenticated control connection.
    /// Result: 0=offer, 1=active, 2=closed.
    /// Closed is terminal, including invalid events, disconnection and clock failure.
    pub fn event(&mut self, event: u32, elapsed: u64, connected: bool, foreground: bool) -> u32 {
        if self.state == 2 {
            return 2;
        }
        let limit = if self.state == 0 { 120_000 } else { 600_000 };
        let allowed = match event {
            0 | 1 => foreground,
            3 => foreground && self.state == 0,
            4 | 5 => !foreground && self.state == 1 && self.background_audio,
            _ => false,
        };
        if !allowed || elapsed >= limit || !connected {
            self.state = 2;
        } else if matches!(event, 1 | 3) && self.state == 0 {
            self.state = 1;
            self.background_audio = event == 3;
        }
        self.state
    }
}
