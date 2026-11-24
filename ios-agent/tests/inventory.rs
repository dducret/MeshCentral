// SPDX-License-Identifier: Apache-2.0
use meshcentral_ios_core::inventory::{DEVICE_DETAILS, Inventory, InventoryGate, MAX_JSON};

fn facts() -> Inventory<'static> {
    Inventory {
        model: "iPad",
        machine: "iPad14,3",
        memory_bytes: 8 * 1024 * 1024 * 1024,
        processors: 8,
        architecture: 1,
        simulator: false,
        battery_percent: 0,
        battery_state: 1,
    }
}
#[test]
fn limits_permissions_and_pending_send() {
    let mut gate = InventoryGate::default();
    assert!(!gate.begin(0, Some(8)));
    assert!(gate.begin(0, Some(DEVICE_DETAILS | 8)));
    assert!(!gate.begin(5000, None));
    gate.complete();
    assert!(!gate.begin(4999, None));
    assert!(gate.begin(5000, None));
    gate.complete();
    assert!(!gate.begin(0, None)); // Clock rollback cannot bypass throttling.
    assert!(gate.begin(10000, Some(u32::MAX)));
}
#[test]
fn serializer_bounds_and_empty_battery() {
    let mut buffer = [0; MAX_JSON];
    let count = facts().write(&mut buffer).unwrap();
    let text = core::str::from_utf8(&buffer[..count]).unwrap();
    assert!(text.contains("\"BatteryCharge\":\"0\""));
    assert!(text.contains("8192 MiB"));
    assert!(text.contains("8 processing cores"));
    assert!(facts().write(&mut buffer[..count]).is_some());
    assert!(facts().write(&mut buffer[..count - 1]).is_none());
    assert!(facts().write(&mut []).is_none());
}
#[test]
fn unknown_values_and_simulator_do_not_invent_hardware() {
    let mut item = facts();
    let mut buffer = [0; MAX_JSON];
    item.battery_percent = -1;
    item.battery_state = 0;
    item.memory_bytes = 0;
    item.processors = 0;
    let count = item.write(&mut buffer).unwrap();
    let text = core::str::from_utf8(&buffer[..count]).unwrap();
    assert!(!text.contains("battery"));
    assert!(!text.contains("darwin"));
    item = facts();
    item.simulator = true;
    let count = item.write(&mut buffer).unwrap();
    let text = core::str::from_utf8(&buffer[..count]).unwrap();
    assert!(text.contains("iPad Simulator"));
    assert!(text.contains("simulator host"));
    assert!(!text.contains("battery"));
    assert!(!text.contains("darwin"));
    assert!(!text.contains("processing cores"));
}
#[test]
fn invalid_native_facts_cannot_inject_json_or_html() {
    let mut buffer = [0; MAX_JSON];
    for label in ["", "<img>", "\"", "line\n", "é", &"a".repeat(65)] {
        let mut item = facts();
        item.model = label;
        assert!(item.write(&mut buffer).is_none());
        item = facts();
        item.machine = label;
        assert!(item.write(&mut buffer).is_none());
    }
    for percent in [-2, 101, i32::MAX] {
        let mut item = facts();
        item.battery_percent = percent;
        assert!(item.write(&mut buffer).is_none());
    }
    let mut item = facts();
    item.battery_state = 4;
    assert!(item.write(&mut buffer).is_none());
    item = facts();
    item.architecture = 3;
    assert!(item.write(&mut buffer).is_none());
    item = facts();
    item.processors = 1025;
    assert!(item.write(&mut buffer).is_none());
    item = facts();
    item.memory_bytes = u64::MAX;
    assert!(item.write(&mut buffer).is_none());
}
