// SPDX-License-Identifier: Apache-2.0
use meshcentral_ios_core::inventory::{Inventory, MAX_JSON};
fn main() {
    let mut item = Inventory {
        model: "iPad",
        machine: "iPad14,3",
        memory_bytes: 8 * 1024 * 1024 * 1024,
        processors: 8,
        architecture: 1,
        simulator: false,
        battery_percent: 0,
        battery_state: 1,
    };
    for name in ["device", "unknown", "charging", "full", "simulator"] {
        match name {
            "unknown" => {
                item.battery_percent = -1;
                item.battery_state = 0;
            }
            "charging" => {
                item.battery_percent = 71;
                item.battery_state = 2;
            }
            "full" => {
                item.battery_percent = 100;
                item.battery_state = 3;
            }
            "simulator" => {
                item.simulator = true;
                item.machine = "arm64";
            }
            _ => {}
        }
        let mut output = [0; MAX_JSON];
        let size = item.write(&mut output).unwrap();
        println!("{name}\t{}", std::str::from_utf8(&output[..size]).unwrap());
    }
}
