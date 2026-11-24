// SPDX-License-Identifier: Apache-2.0
mod support;

use meshcentral_ios_core::session::*;

#[test]
fn local_consent_and_system_capture_are_both_required() {
    let mut s = support::authenticated(0x33).into_session().unwrap();
    let ticket = s.request_screen_share().unwrap();
    assert!(!s.may_send_screen(ticket));
    assert_eq!(
        s.capture_started(ticket),
        Err(SessionError::InvalidTransition)
    );
    s.approve_locally(ticket).unwrap();
    assert!(!s.may_send_screen(ticket));
    s.capture_started(ticket).unwrap();
    assert!(s.may_send_screen(ticket));
    assert!(!s.permits_remote_input());
    s.stop();
    assert!(!s.may_send_screen(ticket));
}

#[test]
fn stale_ui_or_capture_callbacks_cannot_restart_a_stopped_session() {
    let mut s = support::authenticated(0x33).into_session().unwrap();
    let first = s.request_screen_share().unwrap();
    s.approve_locally(first).unwrap();
    s.stop();
    assert_eq!(s.capture_started(first), Err(SessionError::StaleTicket));
    let second = s.request_screen_share().unwrap();
    assert_eq!(s.approve_locally(first), Err(SessionError::StaleTicket));
    s.approve_locally(second).unwrap();
    s.capture_started(second).unwrap();
    assert!(!s.may_send_screen(first));
    assert!(s.may_send_screen(second));
}

#[test]
fn disconnect_revokes_every_state_and_is_irreversible() {
    for stage in 0..3 {
        let mut s = support::authenticated(0x33).into_session().unwrap();
        let ticket = s.request_screen_share().unwrap();
        if stage > 0 {
            s.approve_locally(ticket).unwrap();
        }
        if stage > 1 {
            s.capture_started(ticket).unwrap();
        }
        s.disconnect();
        assert!(!s.may_send_screen(ticket));
        assert_eq!(s.approve_locally(ticket), Err(SessionError::Closed));
        assert_eq!(s.request_screen_share().err(), Some(SessionError::Closed));
        s.stop();
        assert_eq!(s.state(), SessionState::Closed);
        assert!(!s.permits_remote_input());
    }
}

#[test]
fn reconnect_cannot_reuse_previous_consent_ticket() {
    let mut old = support::authenticated(0x33).into_session().unwrap();
    let old_ticket = old.request_screen_share().unwrap();
    old.approve_locally(old_ticket).unwrap();
    old.disconnect();
    let mut new = support::authenticated(0x34).into_session().unwrap();
    let new_ticket = new.request_screen_share().unwrap();
    assert_eq!(
        new.approve_locally(old_ticket),
        Err(SessionError::StaleTicket)
    );
    assert!(!new.may_send_screen(old_ticket));
    new.approve_locally(new_ticket).unwrap();
    new.capture_started(new_ticket).unwrap();
    assert!(new.may_send_screen(new_ticket));
}

#[test]
fn a_second_request_cannot_replace_the_operator_being_approved() {
    let mut s = support::authenticated(0x33).into_session().unwrap();
    let ticket = s.request_screen_share().unwrap();
    assert_eq!(s.request_screen_share().err(), Some(SessionError::Busy));
    s.approve_locally(ticket).unwrap();
    assert_eq!(s.request_screen_share().err(), Some(SessionError::Busy));
    s.capture_started(ticket).unwrap();
    assert_eq!(s.request_screen_share().err(), Some(SessionError::Busy));
}

#[test]
fn local_privacy_only_changes_video_for_the_live_ticket() {
    let mut s = support::authenticated(0x33).into_session().unwrap();
    let first = s.request_screen_share().unwrap();
    assert_eq!(
        s.set_screen_hidden(first, false),
        Err(SessionError::InvalidTransition)
    );
    s.approve_locally(first).unwrap();
    s.capture_started(first).unwrap();
    s.set_screen_hidden(first, true).unwrap();
    assert!(s.assistance_active(first));
    assert!(!s.may_send_screen(first));
    s.set_screen_hidden(first, false).unwrap();
    assert!(s.may_send_screen(first));
    s.set_screen_hidden(first, true).unwrap();
    s.stop();

    let second = s.request_screen_share().unwrap();
    s.approve_locally(second).unwrap();
    s.capture_started(second).unwrap();
    assert!(s.may_send_screen(second));
    s.set_screen_hidden(second, true).unwrap();
    assert_eq!(
        s.set_screen_hidden(first, false),
        Err(SessionError::StaleTicket)
    );
    assert!(!s.may_send_screen(second));
    s.disconnect();
    assert!(!s.assistance_active(second));
    assert_eq!(
        s.set_screen_hidden(second, false),
        Err(SessionError::Closed)
    );
}
