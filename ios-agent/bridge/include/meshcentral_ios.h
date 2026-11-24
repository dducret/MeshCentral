// SPDX-License-Identifier: Apache-2.0
#ifndef MESHCENTRAL_IOS_H
#define MESHCENTRAL_IOS_H
#include <stddef.h>
#include <stdint.h>
/* Inventory: one serialized gate per authenticated control connection; free once
 * on disconnect. begin returns 1 at most once per 5000 monotonic milliseconds,
 * with one pending operation. from_operator=1 requires Device Details rights.
 * Complete after send/skip; callbacks after disconnect must not use the gate.
 * write: distinct borrowed buffers, ASCII model/machine <=64 bytes, output <=2048.
 * Returns bytes written, or 0 (discard partial output). See inventory.rs for
 * enum values. No NUL terminator. No device identifiers, storage or uptime. */
void *mc_inventory_new(void);
int32_t mc_inventory_begin(void *handle, uint64_t now_ms, uint32_t rights, uint32_t from_operator);
void mc_inventory_complete(void *handle);
void mc_inventory_free(void *handle);
size_t mc_inventory_write(const uint8_t *model, size_t model_len, const uint8_t *machine, size_t machine_len,
    uint64_t memory_bytes, uint32_t processors, uint32_t architecture, uint32_t simulator,
    int32_t battery_percent, uint32_t battery_state, uint8_t *output, size_t capacity);
/* Messenger: buffers borrowed for call, <=1024/256/512 bytes. Exact node/user binding.
 * One serialized handle per invitation; free once. Event 0=foreground poll,
 * 1=LOCAL accept, 2=stop, 3=LOCAL accept with background audio, 4=background
 * poll while the platform observes live two-way audio, 5=background poll while
 * the platform holds an interrupted call with media paused. Events 4 and 5
 * require event 3 and the original relay and control connection verified by
 * the platform. Milliseconds since receipt.
 * Result 0=offer, 1=active, 2=closed, -1=null. Closed cannot reopen. */
int32_t mc_messenger_validate(const uint8_t *id, size_t id_len, const uint8_t *node,
    size_t node_len, const uint8_t *user, size_t user_len, uint32_t rights);
void *mc_messenger_new(void);
int32_t mc_messenger_event(void *handle, uint32_t event, uint64_t elapsed_ms,
    uint32_t connected, uint32_t foreground);
void mc_messenger_free(void *handle);

// ABI v1. All buffers must be valid for the specified lengths. Calls on a handle
// must be serialized. Callbacks are synchronous, must not throw or reenter Rust,
// and their context must outlive the handle. Never use a handle after mc_free.
// Native APIs own the private key; Rust only receives the public certificate.
typedef int32_t (*MCVerify)(void *, const uint8_t *pin48, const uint8_t *cert,
    size_t cert_len, const uint8_t *signature, size_t signature_len, const uint8_t *transcript144);
typedef int32_t (*MCSign)(void *, const uint8_t *transcript144, uint8_t *signature384);
typedef struct { void *context; MCVerify verify; MCSign sign; } MCCallbacks;
typedef struct {
    uint32_t architecture_id;
    uint32_t agent_version;
    uint32_t platform_type;
    uint8_t mesh_id[48];
    const uint8_t *name;
    size_t name_len;
} MCRegistration;
typedef struct { size_t identity; size_t info; } MCLengths;

// Returns NULL on invalid input. Certificate <=8192 bytes. Pin/nonces are 48 bytes.
void *mc_new(const uint8_t *tls_hash48, const uint8_t *pin48, const uint8_t *nonce48,
    const uint8_t *certificate, size_t certificate_len, MCCallbacks callbacks);
// Positive byte count, or negative error. Caller sends this once after TLS trust.
intptr_t mc_hello(void *handle, uint8_t *output, size_t capacity);
// 1=challenge accepted, 2=server verified, 3=registered; negative=fatal, close socket.
int32_t mc_receive(void *handle, const uint8_t *frame, size_t length);
// Called after result 2. Zero=success; send identity then info as separate messages.
int32_t mc_register(void *handle, const MCRegistration *registration,
    uint8_t *identity, size_t identity_capacity, uint8_t *info, size_t info_capacity, MCLengths *lengths);
void mc_free(void *handle);
/* One live share per authenticated client. No media until local event 1 and
 * capture-confirmed event 2. Event 3 returns 1 only for authorized visible video.
 * Events 4/5 locally hide/show video (0=success); event 6 checks live consent
 * for non-video assistance and the synthetic privacy frame (1=active).
 * Freeing the client revokes all shares. Serialize access/free for each handle.
 * Only local UI/platform callbacks may send events 1/2/4/5. */
void *mc_share_new(void *client, uint32_t rights);
int32_t mc_share_event(void *share, uint32_t event);
void mc_share_free(void *share);
/* Distinct bounded buffers, no input/output aliasing. Max JPEG 524288 bytes,
 * maximum output 524304 bytes; dimensions 1..1920. Negative result is failure. */
intptr_t mc_screen_size(uint16_t width, uint16_t height, uint8_t *out, size_t capacity);
intptr_t mc_screen_jpeg(const uint8_t *jpeg, size_t length, uint8_t *out, size_t capacity);

// Device certificate construction. Native SDK signs TBS using RSA/SHA-384, then
// calls mc_finish_certificate. No private keys or randomness are generated here.
intptr_t mc_build_tbs(const uint8_t *pkcs1, size_t pkcs1_len, const uint8_t *serial16,
    const uint8_t *not_before15, const uint8_t *not_after15, uint8_t *output, size_t capacity);
intptr_t mc_finish_certificate(const uint8_t *tbs, size_t tbs_len,
    const uint8_t *signature, size_t signature_len, uint8_t *output, size_t capacity);
/* Quality handles must be serialized with observe/free. */
void *mc_quality_new(void);
uint32_t mc_quality_observe(void *handle, uint32_t elapsed_ms, uint32_t bytes);
void mc_quality_free(void *handle);
int32_t mc_transfer_next(uint32_t total, uint32_t offset, uint32_t chunk);
/* One document per handle; local UI alone may approve. Serialize with free. */
void *mc_transfer_new(uint32_t total);
int32_t mc_transfer_approve(void *handle);
int32_t mc_transfer_chunk(void *handle, uint32_t offset, uint32_t chunk);
void mc_transfer_free(void *handle);
/* Guided instructions: total 1..20, steps start at 1. Serialized unique handle.
 * present returns 0 only for the next step after local completion (or step 1).
 * respond: 1=done, 2=help, 3=stop, local UI only; 0=accepted, -1=stale/invalid.
 * The host must enforce authorized sharing, chat rights and guide UUID binding.
 * No event on this handle permits touch/keyboard injection. */
void *mc_guide_new(uint32_t total);
int32_t mc_guide_present(void *handle, uint32_t step);
int32_t mc_guide_respond(void *handle, uint32_t step, uint32_t response);
void mc_guide_free(void *handle);
/* Local diagnostic classification only; returns 0..5 (see assistance.rs). */
uint32_t mc_connection_health(uint32_t network, uint32_t frame_age_ms,
    uint32_t rtt_ms, uint32_t send_ms, uint32_t constrained, uint32_t thermal);
/* Broadcast watchdog: phase 0=preparation, 1=active, 2=stopping.
 * Milliseconds from a local monotonic clock. remaining never grants consent.
 * policy: 0=wait, 1=expired/revoke, 2=stale/revoke, 3=stop unconfirmed,
 * 4=invalid. In particular 3 must NOT enable automatic restart. */
uint32_t mc_broadcast_remaining_ms(uint32_t phase, uint64_t elapsed_ms);
uint32_t mc_broadcast_policy(uint32_t phase, uint64_t elapsed_ms, uint64_t silence_ms);
#endif
