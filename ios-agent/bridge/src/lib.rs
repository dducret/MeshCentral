// SPDX-License-Identifier: Apache-2.0
//! Checked C ABI over the safe Rust core; pointer safety is confined to this crate.
//! All exported functions require the pointer/lifetime contract in the C header.
#![deny(unsafe_op_in_unsafe_fn)]
// One shared safety contract is published in the header instead of repeating it.
#![allow(clippy::missing_safety_doc)]

use meshcentral_ios_core::assistance::{Guide, Quality, Transfer, next_offset};
#[unsafe(no_mangle)]
pub extern "C" fn mc_inventory_new() -> *mut c_void {
    Box::into_raw(Box::new(
        meshcentral_ios_core::inventory::InventoryGate::default(),
    ))
    .cast()
}
#[unsafe(no_mangle)]
pub unsafe extern "C" fn mc_inventory_begin(
    handle: *mut c_void,
    now_ms: u64,
    rights: u32,
    from_operator: u32,
) -> i32 {
    if from_operator > 1 {
        return 0;
    }
    // SAFETY: one serialized owner, as documented in the C header.
    unsafe { (handle as *mut meshcentral_ios_core::inventory::InventoryGate).as_mut() }
        .map_or(0, |gate| {
            i32::from(gate.begin(now_ms, (from_operator == 1).then_some(rights)))
        })
}
#[unsafe(no_mangle)]
pub unsafe extern "C" fn mc_inventory_complete(handle: *mut c_void) {
    // SAFETY: same owner; null is a no-op.
    if let Some(gate) =
        unsafe { (handle as *mut meshcentral_ios_core::inventory::InventoryGate).as_mut() }
    {
        gate.complete();
    }
}
#[unsafe(no_mangle)]
pub unsafe extern "C" fn mc_inventory_free(handle: *mut c_void) {
    if !handle.is_null() {
        // SAFETY: freed exactly once by the native owner.
        drop(unsafe {
            Box::from_raw(handle as *mut meshcentral_ios_core::inventory::InventoryGate)
        });
    }
}
#[unsafe(no_mangle)]
pub unsafe extern "C" fn mc_inventory_write(
    model: *const u8,
    model_len: usize,
    machine: *const u8,
    machine_len: usize,
    memory_bytes: u64,
    processors: u32,
    architecture: u32,
    simulator: u32,
    battery_percent: i32,
    battery_state: u32,
    out: *mut u8,
    capacity: usize,
) -> usize {
    if simulator > 1 {
        return 0;
    }
    // SAFETY: distinct borrowed buffers, bounded before slice construction.
    let values = unsafe {
        (
            input(model, model_len, 64),
            input(machine, machine_len, 64),
            output(out, capacity, 2048),
        )
    };
    let (Some(model), Some(machine), Some(out)) = values else {
        return 0;
    };
    let (Ok(model), Ok(machine)) = (std::str::from_utf8(model), std::str::from_utf8(machine))
    else {
        return 0;
    };
    meshcentral_ios_core::inventory::Inventory {
        model,
        machine,
        memory_bytes,
        processors,
        architecture,
        simulator: simulator == 1,
        battery_percent,
        battery_state,
    }
    .write(out)
    .unwrap_or(0)
}
#[unsafe(no_mangle)]
pub unsafe extern "C" fn mc_messenger_validate(
    id: *const u8,
    id_len: usize,
    node: *const u8,
    node_len: usize,
    user: *const u8,
    user_len: usize,
    rights: u32,
) -> i32 {
    // SAFETY: borrowed caller-owned buffers, bounded before constructing slices.
    let values = unsafe {
        (
            input(id, id_len, 1024),
            input(node, node_len, 256),
            input(user, user_len, 512),
        )
    };
    match values {
        (Some(id), Some(node), Some(user)) => i32::from(
            meshcentral_ios_core::messenger::valid_invitation(id, node, user, rights),
        ),
        _ => 0,
    }
}
#[unsafe(no_mangle)]
pub extern "C" fn mc_messenger_new() -> *mut c_void {
    Box::into_raw(Box::new(
        meshcentral_ios_core::messenger::Messenger::default(),
    ))
    .cast()
}
#[unsafe(no_mangle)]
pub unsafe extern "C" fn mc_messenger_event(
    handle: *mut c_void,
    event: u32,
    elapsed: u64,
    connected: u32,
    foreground: u32,
) -> i32 {
    // SAFETY: one serialized native owner; never use after free.
    unsafe { (handle as *mut meshcentral_ios_core::messenger::Messenger).as_mut() }.map_or(
        -1,
        |gate| {
            gate.event(
                event,
                elapsed,
                connected == 1 && foreground <= 1,
                foreground == 1,
            ) as i32
        },
    )
}
#[unsafe(no_mangle)]
pub unsafe extern "C" fn mc_messenger_free(handle: *mut c_void) {
    if !handle.is_null() {
        // SAFETY: released exactly once by its owner.
        drop(unsafe { Box::from_raw(handle as *mut meshcentral_ios_core::messenger::Messenger) });
    }
}
#[unsafe(no_mangle)]
pub extern "C" fn mc_broadcast_remaining_ms(phase: u32, elapsed_ms: u64) -> u32 {
    meshcentral_ios_core::session::broadcast_remaining_ms(phase, elapsed_ms)
}

#[unsafe(no_mangle)]
pub extern "C" fn mc_broadcast_policy(phase: u32, elapsed_ms: u64, silence_ms: u64) -> u32 {
    meshcentral_ios_core::session::broadcast_policy(phase, elapsed_ms, silence_ms)
}
#[unsafe(no_mangle)]
pub extern "C" fn mc_connection_health(
    network: u32,
    frame_age_ms: u32,
    rtt_ms: u32,
    send_ms: u32,
    constrained: u32,
    thermal: u32,
) -> u32 {
    meshcentral_ios_core::assistance::connection_health(
        network,
        frame_age_ms,
        rtt_ms,
        send_ms,
        constrained != 0,
        thermal,
    )
}
use meshcentral_ios_core::{
    auth::*,
    certificate, desktop,
    session::{AssistanceSession, ConsentTicket},
    wire::*,
};
#[unsafe(no_mangle)]
pub extern "C" fn mc_guide_new(total: u32) -> *mut c_void {
    Guide::new(total).map_or(std::ptr::null_mut(), |g| Box::into_raw(Box::new(g)).cast())
}
#[unsafe(no_mangle)]
pub unsafe extern "C" fn mc_guide_present(handle: *mut c_void, step: u32) -> i32 {
    // SAFETY: caller serializes access to one live guide handle.
    unsafe { (handle as *mut Guide).as_mut() }.map_or(-1, |g| if g.present(step) { 0 } else { -1 })
}
#[unsafe(no_mangle)]
pub unsafe extern "C" fn mc_guide_respond(handle: *mut c_void, step: u32, response: u32) -> i32 {
    // SAFETY: caller serializes access; response originates only from local UI.
    unsafe { (handle as *mut Guide).as_mut() }.map_or(-1, |g| {
        if g.respond_locally(step, response) {
            0
        } else {
            -1
        }
    })
}
#[unsafe(no_mangle)]
pub unsafe extern "C" fn mc_guide_free(handle: *mut c_void) {
    if !handle.is_null() {
        // SAFETY: native owner releases this allocation exactly once.
        drop(unsafe { Box::from_raw(handle as *mut Guide) });
    }
}
#[unsafe(no_mangle)]
pub extern "C" fn mc_transfer_new(total: u32) -> *mut c_void {
    Transfer::new(total).map_or(std::ptr::null_mut(), |t| Box::into_raw(Box::new(t)).cast())
}
#[unsafe(no_mangle)]
pub unsafe extern "C" fn mc_transfer_approve(handle: *mut c_void) -> i32 {
    // SAFETY: caller serializes access to one live transfer handle.
    unsafe { (handle as *mut Transfer).as_mut() }
        .map_or(-1, |t| if t.approve_locally() { 0 } else { -1 })
}
#[unsafe(no_mangle)]
pub unsafe extern "C" fn mc_transfer_chunk(handle: *mut c_void, offset: u32, chunk: u32) -> i32 {
    // SAFETY: caller serializes access to one live transfer handle.
    unsafe { (handle as *mut Transfer).as_mut() }
        .and_then(|t| t.accept_chunk(offset, chunk))
        .map_or(-1, |n| n as i32)
}
#[unsafe(no_mangle)]
pub unsafe extern "C" fn mc_transfer_free(handle: *mut c_void) {
    if !handle.is_null() {
        // SAFETY: native owner releases this allocation exactly once.
        drop(unsafe { Box::from_raw(handle as *mut Transfer) });
    }
}
#[unsafe(no_mangle)]
pub extern "C" fn mc_transfer_next(total: u32, offset: u32, chunk: u32) -> i32 {
    next_offset(total, offset, chunk).map_or(-1, |n| n as i32)
}
#[unsafe(no_mangle)]
pub extern "C" fn mc_quality_new() -> *mut c_void {
    Box::into_raw(Box::new(Quality::new())).cast()
}
#[unsafe(no_mangle)]
pub unsafe extern "C" fn mc_quality_observe(
    handle: *mut c_void,
    elapsed_ms: u32,
    bytes: u32,
) -> u32 {
    // SAFETY: caller serializes access to a live quality handle.
    unsafe { (handle as *mut Quality).as_mut() }.map_or(0, |q| q.observe(elapsed_ms, bytes))
}
#[unsafe(no_mangle)]
pub unsafe extern "C" fn mc_quality_free(handle: *mut c_void) {
    if !handle.is_null() {
        // SAFETY: caller uniquely owns this allocation and releases it once.
        drop(unsafe { Box::from_raw(handle as *mut Quality) });
    }
}
use std::{
    ffi::c_void,
    slice,
    sync::{Arc, Mutex},
};

type Verify = unsafe extern "C" fn(
    *mut c_void,
    *const u8,
    *const u8,
    usize,
    *const u8,
    usize,
    *const u8,
) -> i32;
type Sign = unsafe extern "C" fn(*mut c_void, *const u8, *mut u8) -> i32;

#[repr(C)]
#[derive(Clone, Copy)]
pub struct Callbacks {
    context: *mut c_void,
    verify: Option<Verify>,
    sign: Option<Sign>,
}
#[repr(C)]
pub struct Registration {
    architecture_id: u32,
    agent_version: u32,
    platform_type: u32,
    mesh_id: [u8; 48],
    name: *const u8,
    name_len: usize,
}
#[repr(C)]
pub struct Lengths {
    identity: usize,
    info: usize,
}

struct NativeIdentity {
    certificate: Vec<u8>,
    callbacks: Callbacks,
}
impl IdentityProvider for NativeIdentity {
    fn verify_server(
        &mut self,
        pin: &[u8; 48],
        proof: CertificateProof<'_>,
        transcript: &[u8; 144],
    ) -> Result<(), IdentityError> {
        let callback = self
            .callbacks
            .verify
            .ok_or(IdentityError::InvalidCertificate)?;
        // SAFETY: function/context lifetime is guaranteed by the native host; all
        // borrowed slices stay alive for this synchronous callback.
        match unsafe {
            callback(
                self.callbacks.context,
                pin.as_ptr(),
                proof.certificate_der.as_ptr(),
                proof.certificate_der.len(),
                proof.signature.as_ptr(),
                proof.signature.len(),
                transcript.as_ptr(),
            )
        } {
            0 => Ok(()),
            2 => Err(IdentityError::UntrustedServer),
            3 => Err(IdentityError::InvalidSignature),
            _ => Err(IdentityError::InvalidCertificate),
        }
    }
    fn agent_certificate_der(&self) -> &[u8] {
        &self.certificate
    }
    fn sign_agent(
        &mut self,
        transcript: &[u8; 144],
        output: &mut [u8; MAX_SIGNATURE_LEN],
    ) -> Result<usize, IdentityError> {
        let callback = self.callbacks.sign.ok_or(IdentityError::SigningFailed)?;
        // SAFETY: same host lifetime contract; output has exactly 384 writable bytes.
        match unsafe {
            callback(
                self.callbacks.context,
                transcript.as_ptr(),
                output.as_mut_ptr(),
            )
        } {
            length @ (256 | 384) => Ok(length as usize),
            _ => Err(IdentityError::SigningFailed),
        }
    }
}
struct Client {
    handshake: Option<Handshake>,
    identity: NativeIdentity,
    session: Option<Arc<Mutex<AssistanceSession>>>,
}
impl Drop for Client {
    fn drop(&mut self) {
        if let Some(session) = &self.session
            && let Ok(mut session) = session.lock()
        {
            session.disconnect();
        }
    }
}
struct Share {
    session: Arc<Mutex<AssistanceSession>>,
    ticket: ConsentTicket,
}
impl Drop for Share {
    fn drop(&mut self) {
        if let Ok(mut session) = self.session.lock() {
            session.stop();
        }
    }
}

unsafe fn input<'a>(ptr: *const u8, length: usize, limit: usize) -> Option<&'a [u8]> {
    if ptr.is_null() || length > limit {
        return None;
    }
    // SAFETY: caller promises a readable buffer; lengths are bounded before slicing.
    Some(unsafe { slice::from_raw_parts(ptr, length) })
}
unsafe fn output<'a>(ptr: *mut u8, length: usize, limit: usize) -> Option<&'a mut [u8]> {
    if ptr.is_null() || length > limit {
        return None;
    }
    // SAFETY: caller promises an exclusively writable buffer with no aliasing inputs.
    Some(unsafe { slice::from_raw_parts_mut(ptr, length) })
}
unsafe fn fixed<const N: usize>(ptr: *const u8) -> Option<[u8; N]> {
    // SAFETY: caller's fixed-size buffer contract is forwarded to the checked helper.
    unsafe { input(ptr, N, N) }?.try_into().ok()
}
unsafe fn client<'a>(handle: *mut c_void) -> Option<&'a mut Client> {
    // SAFETY: only live mc_new handles may be passed, with serialized access.
    unsafe { (handle as *mut Client).as_mut() }
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn mc_new(
    tls: *const u8,
    pin: *const u8,
    nonce: *const u8,
    cert: *const u8,
    cert_len: usize,
    callbacks: Callbacks,
) -> *mut c_void {
    let create = || -> Option<Client> {
        if callbacks.verify.is_none() || callbacks.sign.is_none() || cert_len == 0 {
            return None;
        }
        // SAFETY: fixed-size input pointers and cert span follow the C header contract.
        let (tls, pin, nonce, certificate) = unsafe {
            (
                fixed(tls)?,
                fixed(pin)?,
                fixed(nonce)?,
                input(cert, cert_len, MAX_CERTIFICATE_LEN)?.to_vec(),
            )
        };
        Some(Client {
            handshake: Some(Handshake::new(tls, pin, nonce).ok()?),
            identity: NativeIdentity {
                certificate,
                callbacks,
            },
            session: None,
        })
    };
    create().map_or(std::ptr::null_mut(), |value| {
        Box::into_raw(Box::new(value)).cast()
    })
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn mc_hello(handle: *mut c_void, out: *mut u8, capacity: usize) -> isize {
    // SAFETY: native host owns a live handle and exclusive bounded output buffer.
    let (Some(c), Some(out)) = (unsafe { client(handle) }, unsafe {
        output(out, capacity, MAX_FRAME_LEN)
    }) else {
        return -1;
    };
    c.handshake
        .as_ref()
        .and_then(|h| h.hello(out).ok())
        .map_or(-2, |n| n as isize)
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn mc_receive(handle: *mut c_void, frame: *const u8, length: usize) -> i32 {
    // SAFETY: live handle and readable frame are required by the native host contract.
    let Some(c) = (unsafe { client(handle) }) else {
        return -1;
    };
    let Some(frame) = (unsafe { input(frame, length, MAX_FRAME_LEN) }) else {
        if let Some(h) = &mut c.handshake {
            h.close();
        }
        return -1;
    };
    let Some(handshake) = &mut c.handshake else {
        return -2;
    };
    match handshake.receive(frame, &mut c.identity) {
        Ok(Progress::ChallengeAccepted) => 1,
        Ok(Progress::ServerVerified) => 2,
        Ok(Progress::Authenticated) => {
            let Some(handshake) = c.handshake.take() else {
                return -2;
            };
            let Ok(session) = handshake.into_session() else {
                return -2;
            };
            c.session = Some(Arc::new(Mutex::new(session)));
            3
        }
        Err(_) => -2,
    }
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn mc_register(
    handle: *mut c_void,
    registration: *const Registration,
    proof: *mut u8,
    proof_cap: usize,
    info: *mut u8,
    info_cap: usize,
    lengths: *mut Lengths,
) -> i32 {
    // SAFETY: live, aligned pointers and distinct output buffers are a C ABI precondition.
    let Some(c) = (unsafe { client(handle) }) else {
        return -1;
    };
    let prepare = || -> Option<RegistrationLengths> {
        // SAFETY: validity/alignment of the structures is guaranteed by the host.
        let registration = unsafe { registration.as_ref() }?;
        if lengths.is_null() {
            return None;
        }
        let (name, proof, info) = unsafe {
            (
                input(registration.name, registration.name_len, MAX_NAME_LEN)?,
                output(proof, proof_cap, MAX_FRAME_LEN)?,
                output(info, info_cap, MAX_FRAME_LEN)?,
            )
        };
        let data = AgentInfo {
            info_version: 1,
            architecture_id: registration.architecture_id,
            agent_version: registration.agent_version,
            platform_type: registration.platform_type,
            mesh_id: registration.mesh_id,
            capabilities: 0,
            name: std::str::from_utf8(name).ok()?,
        };
        c.handshake
            .as_mut()?
            .prepare_registration(&mut c.identity, data, proof, info)
            .ok()
    };
    let mut prepare = prepare;
    if let Some(result) = prepare() {
        // SAFETY: lengths was validated nonnull above; host supplies writable struct.
        unsafe {
            lengths.write(Lengths {
                identity: result.identity,
                info: result.info,
            });
        }
        0
    } else {
        if let Some(h) = &mut c.handshake {
            h.close();
        }
        -2
    }
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn mc_free(handle: *mut c_void) {
    if !handle.is_null() {
        // SAFETY: host releases the unique live allocation exactly once after callbacks end.
        drop(unsafe { Box::from_raw(handle as *mut Client) });
    }
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn mc_share_new(handle: *mut c_void, rights: u32) -> *mut c_void {
    let create = || -> Option<Share> {
        if !desktop::permits_view(rights) {
            return None;
        }
        // SAFETY: same serialized live-client contract as mc_receive.
        let c = unsafe { client(handle) }?;
        let session = c.session.as_ref()?.clone();
        let ticket = session.lock().ok()?.request_screen_share().ok()?;
        Some(Share { session, ticket })
    };
    create().map_or(std::ptr::null_mut(), |s| Box::into_raw(Box::new(s)).cast())
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn mc_share_event(handle: *mut c_void, event: u32) -> i32 {
    // SAFETY: caller provides one live mc_share_new handle, serialized with free.
    let Some(share) = (unsafe { (handle as *mut Share).as_ref() }) else {
        return -1;
    };
    let Ok(mut session) = share.session.lock() else {
        return -1;
    };
    match event {
        1 => session.approve_locally(share.ticket).map_or(-1, |()| 0),
        2 => session.capture_started(share.ticket).map_or(-1, |()| 0),
        3 => i32::from(session.may_send_screen(share.ticket)),
        4 | 5 => session
            .set_screen_hidden(share.ticket, event == 4)
            .map_or(-1, |()| 0),
        6 => i32::from(session.assistance_active(share.ticket)),
        _ => -1,
    }
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn mc_share_free(handle: *mut c_void) {
    if !handle.is_null() {
        // SAFETY: unique live allocation released exactly once by native owner.
        drop(unsafe { Box::from_raw(handle as *mut Share) });
    }
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn mc_screen_size(
    width: u16,
    height: u16,
    out: *mut u8,
    capacity: usize,
) -> isize {
    // SAFETY: caller owns the bounded writable output buffer.
    let Some(out) = (unsafe { output(out, capacity, 8) }) else {
        return -1;
    };
    desktop::screen_size(width, height, out).map_or(-1, |n| n as isize)
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn mc_screen_jpeg(
    jpeg: *const u8,
    length: usize,
    out: *mut u8,
    capacity: usize,
) -> isize {
    // SAFETY: native caller provides readable JPEG and distinct writable output.
    let (Some(jpeg), Some(out)) = (unsafe { input(jpeg, length, desktop::MAX_JPEG) }, unsafe {
        output(out, capacity, desktop::MAX_PACKET)
    }) else {
        return -1;
    };
    desktop::jpeg_tile(jpeg, out).map_or(-1, |n| n as isize)
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn mc_build_tbs(
    key: *const u8,
    key_len: usize,
    serial: *const u8,
    before: *const u8,
    after: *const u8,
    out: *mut u8,
    capacity: usize,
) -> isize {
    let build = || -> Option<usize> {
        // SAFETY: bounded input arrays and distinct writable output follow the C contract.
        let (key, serial, before, after, out) = unsafe {
            (
                input(key, key_len, 512)?,
                fixed(serial)?,
                fixed(before)?,
                fixed(after)?,
                output(out, capacity, certificate::MAX_DER)?,
            )
        };
        certificate::build_tbs(key, &serial, &before, &after, out).ok()
    };
    build().map_or(-1, |n| n as isize)
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn mc_finish_certificate(
    tbs: *const u8,
    tbs_len: usize,
    signature: *const u8,
    signature_len: usize,
    out: *mut u8,
    capacity: usize,
) -> isize {
    let finish = || -> Option<usize> {
        // SAFETY: bounded readable inputs and nonaliasing output supplied by the host.
        let (tbs, signature, out) = unsafe {
            (
                input(tbs, tbs_len, certificate::MAX_DER)?,
                input(signature, signature_len, MAX_SIGNATURE_LEN)?,
                output(out, capacity, certificate::MAX_DER)?,
            )
        };
        certificate::finish(tbs, signature, out).ok()
    };
    finish().map_or(-1, |n| n as isize)
}
