# SPDX-License-Identifier: Apache-2.0
"""Exercise real Rust Messenger ABI with bound invitations and terminal consent states."""
import ctypes as c
from pathlib import Path
import sys

lib = c.CDLL(str(Path(sys.argv[1]).resolve(strict=True)))
lib.mc_messenger_validate.argtypes = [c.c_char_p, c.c_size_t, c.c_char_p, c.c_size_t, c.c_char_p, c.c_size_t, c.c_uint32]
lib.mc_messenger_validate.restype = c.c_int32
lib.mc_messenger_new.restype = c.c_void_p
lib.mc_messenger_event.argtypes = [c.c_void_p, c.c_uint32, c.c_uint64, c.c_uint32, c.c_uint32]
lib.mc_messenger_event.restype = c.c_int32
lib.mc_messenger_free.argtypes = [c.c_void_p]
node = b'node/team/' + b'A' * 64
user = b'user/team/tech'
identifier = b'meshmessenger/' + node + b'/' + user
def valid(value, rights=0x4008, expected_user=user):
    return lib.mc_messenger_validate(value, len(value), node, len(node), expected_user, len(expected_user), rights)
assert valid(identifier) == 1
assert valid(identifier, 8) == 0
assert valid(identifier, expected_user=b'user/team/other') == 0
assert valid(identifier + b'/other') == 0
assert valid(b'x' * 1025) == 0
assert lib.mc_messenger_validate(None, 1, node, len(node), user, len(user), 0x4008) == 0
assert lib.mc_messenger_event(None, 0, 0, 1, 1) == -1
for terminal in [(0, 120000, 1, 1), (0, 0, 0, 1), (0, 0, 1, 0), (0, 2**64-1, 1, 1), (99, 0, 1, 1)]:
    gate=lib.mc_messenger_new()
    try:
        assert lib.mc_messenger_event(gate, 0, 0, 1, 1) == 0
        assert lib.mc_messenger_event(gate, *terminal) == 2
        assert lib.mc_messenger_event(gate, 1, 0, 1, 1) == 2
    finally: lib.mc_messenger_free(gate)
gate=lib.mc_messenger_new()
try:
    assert lib.mc_messenger_event(gate, 1, 119999, 1, 1) == 1
    assert lib.mc_messenger_event(gate, 0, 599999, 1, 1) == 1
    assert lib.mc_messenger_event(gate, 0, 600000, 1, 1) == 2
finally: lib.mc_messenger_free(gate)
for answer, background_result in [(1, 2), (3, 1)]:
    gate = lib.mc_messenger_new()
    try:
        assert lib.mc_messenger_event(gate, answer, 1, 1, 1) == 1
        assert lib.mc_messenger_event(gate, 4, 2, 1, 0) == background_result
        assert lib.mc_messenger_event(gate, 4, 3, 1, 2) == 2
        assert lib.mc_messenger_event(gate, 4, 4, 1, 0) == 2
    finally: lib.mc_messenger_free(gate)
for connected, foreground in [(1, 0), (0, 0), (1, 1), (1, 2)]:
    gate = lib.mc_messenger_new()
    try:
        assert lib.mc_messenger_event(gate, 3, 1, 1, 1) == 1
        assert lib.mc_messenger_event(gate, 4, 2000, 1, 0) == 1
        held = connected == 1 and foreground == 0
        assert lib.mc_messenger_event(gate, 5, 3000, connected, foreground) == (1 if held else 2)
        assert lib.mc_messenger_event(gate, 0, 599999, 1, 1) == (1 if held else 2)
        assert lib.mc_messenger_event(gate, 0, 600000, 1, 1) == 2
    finally:
        lib.mc_messenger_free(gate)
print('PASS: compiled Messenger ABI consent, live and interrupted background audio, invalid phase, expiry and terminal stop.')
