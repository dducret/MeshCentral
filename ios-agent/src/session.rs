// SPDX-License-Identifier: Apache-2.0
//! Local consent only. This does not implement relay authorization or screen capture.

use crate::wire::HASH_LEN;

/// Portable broadcast deadlines. These observations can only revoke or wait;
/// they never authorize media or permit reuse of a previous consent ticket.
pub const PREPARATION_MS: u64 = 120_000;
pub const BROADCAST_MS: u64 = 600_000;
pub const MAILBOX_SILENCE_MS: u64 = 10_000;

/// Phase 0=preparation, 1=broadcast, 2=waiting for stop acknowledgement.
/// Unknown phases have no remaining budget. Saturation avoids clock overflow.
pub fn broadcast_remaining_ms(phase: u32, elapsed_ms: u64) -> u32 {
    let limit = match phase {
        0 => PREPARATION_MS,
        1 => BROADCAST_MS,
        _ => 0,
    };
    limit.saturating_sub(elapsed_ms) as u32
}

/// 0=wait, 1=deadline/revoke, 2=missing heartbeat/revoke,
/// 3=stop unconfirmed (keep stop controls, do NOT grant a new session), 4=invalid.
pub fn broadcast_policy(phase: u32, elapsed_ms: u64, silence_ms: u64) -> u32 {
    match phase {
        0 if elapsed_ms >= PREPARATION_MS => 1,
        0 => 0,
        1 if elapsed_ms >= BROADCAST_MS => 1,
        1 if silence_ms >= MAILBOX_SILENCE_MS => 2,
        1 => 0,
        2 if elapsed_ms >= MAILBOX_SILENCE_MS => 3,
        2 => 0,
        _ => 4,
    }
}

/// Opaque ticket bound to this connection's fresh nonce and one local request.
/// The host must associate it with exactly one authenticated relay/operator.
#[derive(Clone, Copy, Eq, PartialEq)]
pub struct ConsentTicket {
    connection_nonce: [u8; HASH_LEN],
    sequence: u64,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum SessionState {
    Idle,
    AwaitConsent,
    AwaitCapture,
    Sharing,
    Closed,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum SessionError {
    Closed,
    Busy,
    StaleTicket,
    InvalidTransition,
    RequestLimitReached,
}

/// One control connection, at most one local screen-sharing session at a time.
/// Created only by consuming a successfully acknowledged handshake.
pub struct AssistanceSession {
    connection_nonce: [u8; HASH_LEN],
    sequence: u64,
    state: SessionState,
    ticket: Option<ConsentTicket>,
    screen_hidden: bool,
}

impl AssistanceSession {
    pub(crate) fn authenticated(connection_nonce: [u8; HASH_LEN]) -> Self {
        Self {
            connection_nonce,
            sequence: 0,
            state: SessionState::Idle,
            ticket: None,
            screen_hidden: false,
        }
    }

    pub fn state(&self) -> SessionState {
        self.state
    }

    /// Call only after validating relay origin, protocol, operator and rights.
    /// A network request cannot authorize capture; local approval is mandatory.
    pub fn request_screen_share(&mut self) -> Result<ConsentTicket, SessionError> {
        if self.state == SessionState::Closed {
            return Err(SessionError::Closed);
        }
        if self.state != SessionState::Idle {
            return Err(SessionError::Busy);
        }
        self.sequence = self
            .sequence
            .checked_add(1)
            .ok_or(SessionError::RequestLimitReached)?;
        let ticket = ConsentTicket {
            connection_nonce: self.connection_nonce,
            sequence: self.sequence,
        };
        self.ticket = Some(ticket);
        self.state = SessionState::AwaitConsent;
        Ok(ticket)
    }

    /// Trusted local UI event, never a remotely supplied permission flag.
    pub fn approve_locally(&mut self, ticket: ConsentTicket) -> Result<(), SessionError> {
        self.transition(
            ticket,
            SessionState::AwaitConsent,
            SessionState::AwaitCapture,
        )
    }

    /// Native adapter event after the person accepts the system capture UI.
    pub fn capture_started(&mut self, ticket: ConsentTicket) -> Result<(), SessionError> {
        self.transition(ticket, SessionState::AwaitCapture, SessionState::Sharing)
    }

    fn transition(
        &mut self,
        ticket: ConsentTicket,
        from: SessionState,
        to: SessionState,
    ) -> Result<(), SessionError> {
        if self.state == SessionState::Closed {
            return Err(SessionError::Closed);
        }
        if self.ticket != Some(ticket) {
            return Err(SessionError::StaleTicket);
        }
        if self.state != from {
            return Err(SessionError::InvalidTransition);
        }
        self.state = to;
        Ok(())
    }

    /// Check immediately before enqueuing/sending media, not just at capture start.
    pub fn may_send_screen(&self, ticket: ConsentTicket) -> bool {
        self.assistance_active(ticket) && !self.screen_hidden
    }

    pub fn assistance_active(&self, ticket: ConsentTicket) -> bool {
        self.state == SessionState::Sharing && self.ticket == Some(ticket)
    }

    /// Only the trusted local UI may change video visibility for this ticket.
    pub fn set_screen_hidden(
        &mut self,
        ticket: ConsentTicket,
        hidden: bool,
    ) -> Result<(), SessionError> {
        self.transition(ticket, SessionState::Sharing, SessionState::Sharing)?;
        self.screen_hidden = hidden;
        Ok(())
    }

    pub fn permits_remote_input(&self) -> bool {
        false
    }

    /// Local stop, rejection, timeout, capture pause/error or relay disconnect.
    /// The adapter must also stop capture, discard queued media and close the relay.
    pub fn stop(&mut self) {
        self.ticket = None;
        self.screen_hidden = false;
        if self.state != SessionState::Closed {
            self.state = SessionState::Idle;
        }
    }

    /// Control transport loss permanently closes this object. Reconnect requires
    /// a fresh handshake and new consent, never a transition back to connected.
    pub fn disconnect(&mut self) {
        self.stop();
        self.state = SessionState::Closed;
    }
}
