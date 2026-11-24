// SPDX-License-Identifier: Apache-2.0
use meshcentral_ios_core::session::{broadcast_policy, broadcast_remaining_ms};

#[test]
fn preparation_is_bounded_and_never_extends_an_active_broadcast() {
    assert_eq!(broadcast_remaining_ms(0, 0), 120_000);
    assert_eq!(broadcast_policy(0, 119_999, 0), 0);
    assert_eq!(broadcast_policy(0, 120_000, 0), 1);
    assert_eq!(broadcast_remaining_ms(1, 120_000), 480_000);
    assert_eq!(broadcast_policy(1, 600_000, 0), 1);
}

#[test]
fn silence_is_revocation_not_restart() {
    assert_eq!(broadcast_policy(1, 20_000, 9_999), 0);
    assert_eq!(broadcast_policy(1, 20_000, 10_000), 2);
    assert_eq!(broadcast_policy(2, 9_999, 0), 0);
    assert_eq!(broadcast_policy(2, 10_000, 0), 3);
    assert_eq!(broadcast_policy(2, u64::MAX, 0), 3);
    assert_eq!(broadcast_remaining_ms(2, 0), 0);
}

#[test]
fn invalid_phases_and_extreme_clocks_fail_closed() {
    for phase in [0, 1, 2, 3, u32::MAX] {
        assert_eq!(broadcast_remaining_ms(phase, u64::MAX), 0);
    }
    assert_eq!(broadcast_policy(u32::MAX, 0, 0), 4);
    assert_eq!(broadcast_policy(1, u64::MAX, 0), 1);
    assert_eq!(broadcast_policy(1, 1, u64::MAX), 2);
}
