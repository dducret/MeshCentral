// SPDX-License-Identifier: Apache-2.0
use meshcentral_ios_core::assistance::{Guide, Transfer};

#[test]
fn health_classifies_local_measurements_without_granting_consent() {
    use meshcentral_ios_core::assistance::connection_health as health;
    assert_eq!(health(0, 0, 0, 0, false, 0), 0);
    assert_eq!(health(2, 99000, 2000, 1000, true, 3), 1);
    assert_eq!(health(3, 0, 0, 0, false, 0), 1);
    assert_eq!(health(1, 8000, 10, 10, false, 0), 2);
    assert_eq!(health(1, 7999, 10, 10, false, 0), 0);
    assert_eq!(health(1, 0, 900, 10, false, 0), 3);
    assert_eq!(health(1, 0, 10, 900, false, 0), 3);
    assert_eq!(health(1, 0, 10, 10, true, 0), 4);
    assert_eq!(health(1, 0, 10, 10, true, 2), 5);
    assert_eq!(health(1, u32::MAX, u32::MAX, u32::MAX, true, 3), 2);
}

#[test]
fn guide_cannot_advance_without_local_completion() {
    let mut guide = Guide::new(3).unwrap();
    assert!(!guide.respond_locally(1, 1));
    assert!(!guide.present(2));
    assert!(guide.present(1));
    assert!(!guide.present(1));
    assert!(!guide.present(2));
    assert!(guide.respond_locally(1, 2));
    assert!(!guide.respond_locally(1, 2));
    assert!(!guide.present(2));
    assert!(!guide.respond_locally(2, 1));
    assert!(!guide.respond_locally(1, 99));
    assert!(guide.respond_locally(1, 1));
    assert!(!guide.respond_locally(1, 1));
    assert!(!guide.present(3));
    assert!(guide.present(2));
    assert!(!guide.respond_locally(1, 1));
    assert!(guide.respond_locally(2, 1));
    assert!(guide.present(3));
    assert!(guide.respond_locally(3, 1));
    assert!(!guide.present(4));
}

#[test]
fn guide_bounds_stop_and_new_session_are_independent() {
    for count in [0, 21, u32::MAX] {
        assert!(Guide::new(count).is_none());
    }
    let mut guide = Guide::new(20).unwrap();
    assert!(!guide.present(0));
    assert!(!guide.present(u32::MAX));
    assert!(guide.present(1));
    assert!(guide.respond_locally(1, 3));
    assert!(!guide.respond_locally(1, 1));
    assert!(!guide.respond_locally(1, 3));
    assert!(!guide.present(2));
    let mut fresh = Guide::new(1).unwrap();
    assert!(!fresh.respond_locally(1, 1));
    assert!(fresh.present(1));
}
use meshcentral_ios_core::assistance::{MAX_DOCUMENT, Quality, next_offset};

#[test]
fn documents_require_their_own_consent() {
    let mut transfer = Transfer::new(12).unwrap();
    assert_eq!(transfer.accept_chunk(0, 4), None);
    assert!(transfer.approve_locally());
    assert!(!transfer.approve_locally());
    assert_eq!(transfer.accept_chunk(0, 4), Some(4));
    let mut next_document = Transfer::new(12).unwrap();
    assert_eq!(next_document.accept_chunk(0, 4), None);
}
#[test]
fn gaps_duplicates_and_completion_do_not_advance_transfer() {
    let mut transfer = Transfer::new(12).unwrap();
    transfer.approve_locally();
    assert_eq!(transfer.accept_chunk(1, 4), None);
    assert_eq!(transfer.accept_chunk(0, 4), Some(4));
    assert_eq!(transfer.accept_chunk(0, 4), None);
    assert_eq!(transfer.accept_chunk(4, 9), None);
    assert_eq!(transfer.accept_chunk(4, 8), Some(12));
    assert_eq!(transfer.accept_chunk(12, 1), None);
    assert_eq!(transfer.accept_chunk(12, 0), None);
}
#[test]
fn transfer_allocation_is_bounded() {
    assert!(Transfer::new(0).is_none());
    assert!(Transfer::new(MAX_DOCUMENT + 1).is_none());
    assert!(Transfer::new(MAX_DOCUMENT).is_some());
}

#[test]
fn transfer_bounds_and_overflow() {
    assert_eq!(next_offset(10, 0, 8), Some(8));
    assert_eq!(next_offset(10, 8, 2), Some(10));
    for (total, offset, chunk) in [
        (0, 0, 1),
        (MAX_DOCUMENT + 1, 0, 1),
        (10, 8, 3),
        (10, 0, 0),
        (10, u32::MAX, 2),
        (10000, 0, 8193),
    ] {
        assert_eq!(next_offset(total, offset, chunk), None);
    }
}
#[test]
fn quality_degrades_immediately_recovers_with_hysteresis() {
    let mut q = Quality::new();
    assert_eq!(q.observe(1000, 1000), 0);
    for _ in 0..11 {
        assert_eq!(q.observe(50, 10000), 0);
    }
    assert_eq!(q.observe(50, 10000), 1);
    for _ in 0..100 {
        q.observe(50, 10000);
    }
    assert_eq!(q.observe(50, 10000), 2);
    assert_eq!(q.observe(50, 400000), 1);
    assert_eq!(q.observe(2000, 1000), 0);
    assert_eq!(q.observe(2000, 1000), 0);
}
