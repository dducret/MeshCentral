// SPDX-License-Identifier: Apache-2.0
use meshcentral_ios_core::messenger::{Messenger, valid_invitation};

fn node() -> String {
    format!("node//{}", "A".repeat(64))
}
#[test]
fn invitation_binds_device_operator_domain_and_rights() {
    let node = node();
    let user = "user//tech";
    let id = format!("meshmessenger/{node}/{user}");
    assert!(valid_invitation(
        id.as_bytes(),
        node.as_bytes(),
        user.as_bytes(),
        0x4008
    ));
    assert!(valid_invitation(
        id.as_bytes(),
        node.as_bytes(),
        user.as_bytes(),
        u32::MAX
    ));
    for rights in [0, 8, 0x4000] {
        assert!(!valid_invitation(
            id.as_bytes(),
            node.as_bytes(),
            user.as_bytes(),
            rights
        ));
    }
    assert!(!valid_invitation(
        id.as_bytes(),
        node.as_bytes(),
        b"user//other",
        0x4008
    ));
    assert!(!valid_invitation(
        id.as_bytes(),
        node.as_bytes(),
        b"user/domain/tech",
        0x4008
    ));
    let other = node.replace('A', "B");
    assert!(!valid_invitation(
        id.as_bytes(),
        other.as_bytes(),
        user.as_bytes(),
        0x4008
    ));
}
#[test]
fn invitation_rejects_suffixes_controls_and_unbounded_input() {
    let node = node();
    for user in ["user//", "user//tech/more", "user//tech\n", "user//tech\0"] {
        let id = format!("meshmessenger/{node}/{user}");
        assert!(!valid_invitation(
            id.as_bytes(),
            node.as_bytes(),
            user.as_bytes(),
            0x4008
        ));
    }
    let id = format!("meshmessenger/{node}/user//tech/extra");
    assert!(!valid_invitation(
        id.as_bytes(),
        node.as_bytes(),
        b"user//tech",
        0x4008
    ));
    assert!(!valid_invitation(
        &[0; 1025],
        node.as_bytes(),
        b"user//tech",
        0x4008
    ));
    let key = "node//short";
    assert!(!valid_invitation(
        format!("meshmessenger/{key}/user//tech").as_bytes(),
        key.as_bytes(),
        b"user//tech",
        0x4008
    ));
}
#[test]
fn local_accept_is_required_and_time_cannot_be_renewed() {
    let mut gate = Messenger::default();
    assert_eq!(gate.event(0, 0, true, true), 0);
    assert_eq!(gate.event(1, 119_999, true, true), 1);
    assert_eq!(gate.event(1, 599_999, true, true), 1);
    assert_eq!(gate.event(0, 600_000, true, true), 2);
    assert_eq!(gate.event(1, 0, true, true), 2);
}
#[test]
fn expiry_disconnect_background_and_unknown_events_close_permanently() {
    for (event, age, connected, foreground) in [
        (0, 120_000, true, true),
        (1, u64::MAX, true, true),
        (0, 0, false, true),
        (0, 0, true, false),
        (2, 0, true, true),
        (99, 0, true, true),
    ] {
        let mut gate = Messenger::default();
        assert_eq!(gate.event(event, age, connected, foreground), 2);
        assert_eq!(gate.event(1, 0, true, true), 2);
    }
    for (connected, foreground) in [(false, true), (true, false)] {
        let mut gate = Messenger::default();
        gate.event(1, 0, true, true);
        assert_eq!(gate.event(0, 1, connected, foreground), 2);
        assert_eq!(gate.event(1, 2, true, true), 2);
    }
}

#[test]
fn active_background_audio_needs_explicit_foreground_acceptance() {
    for (accept, accepted_in_foreground) in [(0, true), (1, true), (3, false)] {
        let mut gate = Messenger::default();
        gate.event(accept, 1, true, accepted_in_foreground);
        assert_eq!(gate.event(4, 2, true, false), 2);
        assert_eq!(gate.event(3, 3, true, true), 2);
    }
    let mut gate = Messenger::default();
    assert_eq!(gate.event(1, 1, true, true), 1);
    assert_eq!(
        gate.event(3, 2, true, true),
        2,
        "cannot upgrade old consent"
    );
}

#[test]
fn accepted_background_audio_can_continue_but_never_resume_after_stop() {
    for (event, age, connected, foreground) in [
        (4, 600_000, true, false),
        (4, 200, false, false),
        (0, 200, true, false),
        (2, 200, true, false),
    ] {
        let mut gate = Messenger::default();
        assert_eq!(gate.event(3, 1, true, true), 1);
        assert_eq!(gate.event(4, 50, true, false), 1);
        assert_eq!(gate.event(0, 100, true, true), 1);
        assert_eq!(gate.event(event, age, connected, foreground), 2);
        assert_eq!(gate.event(0, age, true, true), 2);
    }
}

#[test]
fn interrupted_audio_keeps_only_the_original_authorization() {
    let mut gate = Messenger::default();
    assert_eq!(gate.event(3, 1, true, true), 1);
    assert_eq!(gate.event(4, 20_000, true, false), 1);
    assert_eq!(gate.event(5, 21_000, true, false), 1);
    assert_eq!(gate.event(0, 30_000, true, true), 1);
    assert_eq!(gate.event(4, 31_000, true, false), 1);
    assert_eq!(gate.event(5, 599_999, true, false), 1);
    assert_eq!(gate.event(0, 600_000, true, true), 2);

    for (accept, connected, foreground) in [
        (0, true, false),
        (1, true, false),
        (3, false, false),
        (3, true, true),
    ] {
        let mut gate = Messenger::default();
        gate.event(accept, 1, true, true);
        assert_eq!(gate.event(5, 2, connected, foreground), 2);
        assert_eq!(gate.event(0, 3, true, true), 2);
    }
}
