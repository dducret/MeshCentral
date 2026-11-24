// SPDX-License-Identifier: Apache-2.0
//! Bounded assistance policies shared by the Apple adapter and portable tests.
pub const MAX_DOCUMENT: u32 = 2 * 1024 * 1024;
pub const MAX_CHUNK: u32 = 8192;

/// Numeric, privacy-preserving health assessment; inputs are local measurements.
/// network: 0=unknown, 1=available, 2=unavailable, 3=requires connection.
/// result: 0=healthy/unknown, 1=network, 2=no recent image, 3=slow,
/// 4=constrained data, 5=thermal pressure. Never grants or resumes a session.
pub fn connection_health(
    network: u32,
    frame_age_ms: u32,
    rtt_ms: u32,
    send_ms: u32,
    constrained: bool,
    thermal: u32,
) -> u32 {
    if matches!(network, 2 | 3) {
        1
    } else if frame_age_ms >= 8000 {
        2
    } else if thermal >= 2 {
        5
    } else if rtt_ms >= 900 || send_ms >= 900 {
        3
    } else if constrained {
        4
    } else {
        0
    }
}

/// One guide per authorized relay. Content/UUID parsing belongs to the adapter;
/// ordering and local-only completion are enforced here. No remote input occurs.
pub struct Guide {
    total: u32,
    step: u32,
    state: u32, // 0=not started, 1=waiting, 2=help, 3=done, 4=stopped
}
impl Guide {
    pub fn new(total: u32) -> Option<Self> {
        (1..=20).contains(&total).then_some(Self {
            total,
            step: 0,
            state: 0,
        })
    }
    pub fn present(&mut self, step: u32) -> bool {
        if step != self.step + 1 || step > self.total || !matches!(self.state, 0 | 3) {
            return false;
        }
        self.step = step;
        self.state = 1;
        true
    }
    /// Local UI only: 1=done, 2=help, 3=stop. Stale/duplicate replies are rejected.
    pub fn respond_locally(&mut self, step: u32, response: u32) -> bool {
        if step != self.step || self.step == 0 || self.state == 4 {
            return false;
        }
        let next = match response {
            1 if matches!(self.state, 1 | 2) => 3,
            2 if self.state == 1 => 2,
            3 => 4,
            _ => return false,
        };
        self.state = next;
        true
    }
}

/// Per-document consent and sequence state. Only the native local UI may approve.
pub struct Transfer {
    total: u32,
    offset: u32,
    approved: bool,
}
impl Transfer {
    pub fn new(total: u32) -> Option<Self> {
        (1..=MAX_DOCUMENT).contains(&total).then_some(Self {
            total,
            offset: 0,
            approved: false,
        })
    }
    pub fn approve_locally(&mut self) -> bool {
        if self.approved {
            return false;
        }
        self.approved = true;
        true
    }
    pub fn accept_chunk(&mut self, offset: u32, chunk: u32) -> Option<u32> {
        if !self.approved || offset != self.offset {
            return None;
        }
        let next = next_offset(self.total, offset, chunk)?;
        self.offset = next;
        Some(next)
    }
}

/// Reject gaps, overlaps, overflow, empty chunks and oversized resources.
pub fn next_offset(total: u32, offset: u32, chunk: u32) -> Option<u32> {
    if total == 0 || total > MAX_DOCUMENT || chunk == 0 || chunk > MAX_CHUNK {
        return None;
    }
    offset.checked_add(chunk).filter(|end| *end <= total)
}

/// Fast degradation and slow recovery. The caller supplies measured elapsed
/// send/round-trip time, never a remote-requested quality level.
pub struct Quality {
    level: u32,
    good: u32,
}
impl Default for Quality {
    fn default() -> Self {
        Self::new()
    }
}
impl Quality {
    pub fn new() -> Self {
        Self { level: 1, good: 0 }
    }
    pub fn observe(&mut self, milliseconds: u32, bytes: u32) -> u32 {
        if milliseconds > 900 || bytes > 300_000 {
            self.level = self.level.saturating_sub(1);
            self.good = 0;
        } else if milliseconds < 250 && bytes < 180_000 {
            self.good += 1;
            if self.good >= 12 {
                self.level = (self.level + 1).min(2);
                self.good = 0;
            }
        } else {
            self.good = 0;
        }
        self.level
    }
}
