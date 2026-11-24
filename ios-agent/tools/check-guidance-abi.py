# SPDX-License-Identifier: Apache-2.0
"""Exercise the compiled Rust C ABI, without Apple SDKs or third-party packages."""
import ctypes
import pathlib
import sys


def main():
    path = pathlib.Path(sys.argv[1]).resolve(strict=True)
    library = ctypes.CDLL(str(path))
    library.mc_broadcast_remaining_ms.argtypes = [ctypes.c_uint32, ctypes.c_uint64]
    library.mc_broadcast_remaining_ms.restype = ctypes.c_uint32
    library.mc_broadcast_policy.argtypes = [ctypes.c_uint32, ctypes.c_uint64, ctypes.c_uint64]
    library.mc_broadcast_policy.restype = ctypes.c_uint32
    assert library.mc_broadcast_remaining_ms(0, 0) == 120000
    assert library.mc_broadcast_remaining_ms(1, 599999) == 1
    assert library.mc_broadcast_remaining_ms(1, 2**64 - 1) == 0
    assert library.mc_broadcast_policy(0, 120000, 0) == 1
    assert library.mc_broadcast_policy(1, 1, 10000) == 2
    assert library.mc_broadcast_policy(2, 10000, 0) == 3
    assert library.mc_broadcast_policy(99, 0, 0) == 4
    library.mc_guide_new.argtypes = [ctypes.c_uint32]
    library.mc_guide_new.restype = ctypes.c_void_p
    library.mc_guide_present.argtypes = [ctypes.c_void_p, ctypes.c_uint32]
    library.mc_guide_present.restype = ctypes.c_int32
    library.mc_guide_respond.argtypes = [ctypes.c_void_p, ctypes.c_uint32, ctypes.c_uint32]
    library.mc_guide_respond.restype = ctypes.c_int32
    library.mc_guide_free.argtypes = [ctypes.c_void_p]
    library.mc_guide_free.restype = None
    library.mc_connection_health.argtypes = [ctypes.c_uint32] * 6
    library.mc_connection_health.restype = ctypes.c_uint32
    assert library.mc_connection_health(1, 0, 20, 50, 0, 0) == 0
    assert library.mc_connection_health(2, 0, 20, 50, 0, 0) == 1
    assert library.mc_connection_health(1, 8000, 20, 50, 0, 0) == 2
    assert library.mc_connection_health(1, 0, 20, 50, 0, 2) == 5
    for total in (0, 21, 0xFFFFFFFF):
        assert not library.mc_guide_new(total)
    assert library.mc_guide_present(None, 1) == -1
    assert library.mc_guide_respond(None, 1, 1) == -1
    library.mc_guide_free(None)
    handle = library.mc_guide_new(2)
    assert handle
    try:
        assert library.mc_guide_respond(handle, 1, 1) == -1
        assert library.mc_guide_present(handle, 1) == 0
        assert library.mc_guide_present(handle, 2) == -1
        assert library.mc_guide_respond(handle, 1, 2) == 0
        assert library.mc_guide_present(handle, 2) == -1
        assert library.mc_guide_respond(handle, 1, 1) == 0
        assert library.mc_guide_present(handle, 2) == 0
        assert library.mc_guide_respond(handle, 1, 1) == -1
        assert library.mc_guide_respond(handle, 2, 3) == 0
        assert library.mc_guide_respond(handle, 2, 1) == -1
    finally:
        library.mc_guide_free(handle)
    print("PASS: actual Rust C ABI: broadcast expiry/stale/stop watchdog, guidance bounds/consent and connection health.")


if __name__ == "__main__":
    main()
