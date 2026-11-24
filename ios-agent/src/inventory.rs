// SPDX-License-Identifier: Apache-2.0
//! Bounded, identifier-free inventory in MeshCentral's existing sysinfo schema.
use core::fmt::{self, Write};

pub const MAX_JSON: usize = 2048;
pub const DEVICE_DETAILS: u32 = 0x0010_0000;

#[derive(Default)]
pub struct InventoryGate {
    last: Option<u64>,
    pending: bool,
}
impl InventoryGate {
    /// Native owner calls only after authentication, on one serial queue.
    pub fn begin(&mut self, now_ms: u64, operator_rights: Option<u32>) -> bool {
        if operator_rights.is_some_and(|r| r & DEVICE_DETAILS == 0)
            || self.pending
            || self
                .last
                .is_some_and(|last| now_ms.saturating_sub(last) < 5000)
        {
            return false;
        }
        self.last = Some(now_ms);
        self.pending = true;
        true
    }
    pub fn complete(&mut self) {
        self.pending = false;
    }
}

pub struct Inventory<'a> {
    pub model: &'a str,
    pub machine: &'a str,
    pub memory_bytes: u64,
    pub processors: u32,
    /// 0 unknown, 1 arm64, 2 x86_64. This is not a SoC marketing name.
    pub architecture: u32,
    pub simulator: bool,
    /// -1 unavailable, otherwise 0..=100.
    pub battery_percent: i32,
    /// UIDevice: 0 unknown, 1 unplugged, 2 charging, 3 full.
    pub battery_state: u32,
}

struct Buffer<'a> {
    bytes: &'a mut [u8],
    length: usize,
}
impl Write for Buffer<'_> {
    fn write_str(&mut self, text: &str) -> fmt::Result {
        let end = self.length.checked_add(text.len()).ok_or(fmt::Error)?;
        let target = self.bytes.get_mut(self.length..end).ok_or(fmt::Error)?;
        target.copy_from_slice(text.as_bytes());
        self.length = end;
        Ok(())
    }
}
fn safe_label(value: &str) -> bool {
    !value.is_empty()
        && value.len() <= 64
        && value
            .bytes()
            .all(|b| b.is_ascii_alphanumeric() || b" .,_-".contains(&b))
}

impl Inventory<'_> {
    /// Writes only the hash input {hardware:...}. Caller hashes these exact bytes
    /// with SHA-384 and adds hash before sending {action:sysinfo,data:...}.
    /// None means invalid facts or insufficient output; discard partial bytes.
    pub fn write(&self, output: &mut [u8]) -> Option<usize> {
        if !safe_label(self.model)
            || !safe_label(self.machine)
            || self.memory_bytes > (1 << 50)
            || self.processors > 1024
            || self.architecture > 2
            || !(-1..=100).contains(&self.battery_percent)
            || self.battery_state > 3
        {
            return None;
        }
        let size = output.len().min(MAX_JSON);
        let mut out = Buffer {
            bytes: &mut output[..size],
            length: 0,
        };
        let suffix = if self.simulator { " Simulator" } else { "" };
        let architecture = match self.architecture {
            1 => "arm64",
            2 => "x86_64",
            _ => "unknown architecture",
        };
        write!(out, "{{\"hardware\":{{\"mobile\":{{\"brand\":\"Apple\",\"model\":\"{}{suffix}\",\"device\":\"{}\"}},\"identifiers\":{{\"chassis_manufacturer\":\"Apple\",\"product_name\":\"{}{suffix} ({})\",\"cpu_name\":\"{architecture}", self.model, self.machine, self.model, self.machine).ok()?;
        if self.simulator {
            write!(out, " (simulator host)\"").ok()?;
        } else {
            if self.processors > 0 {
                write!(out, "; {} processing cores", self.processors).ok()?;
            }
            write!(out, "\"").ok()?;
        }
        write!(out, "}}").ok()?;
        if !self.simulator && self.memory_bytes > 0 {
            write!(out, ",\"darwin\":{{\"memory\":[{{\"DeviceLocator\":\"Physical memory\",\"Size\":\"{} MiB\"}}]}}", self.memory_bytes / (1024 * 1024)).ok()?;
        }
        if !self.simulator && (self.battery_percent >= 0 || self.battery_state != 0) {
            write!(out, ",\"battery\":[{{\"DeviceName\":\"Battery\"").ok()?;
            if self.battery_percent >= 0 {
                // Upstream tests truthiness: the string "0" displays an empty battery.
                write!(out, ",\"BatteryCharge\":\"{}\"", self.battery_percent).ok()?;
            }
            if self.battery_state != 0 {
                write!(
                    out,
                    ",\"Charging\":{},\"Discharging\":{}",
                    self.battery_state == 2,
                    self.battery_state == 1
                )
                .ok()?;
            }
            write!(out, "}}]").ok()?;
        }
        write!(out, "}}}}").ok()?;
        Some(out.length)
    }
}
