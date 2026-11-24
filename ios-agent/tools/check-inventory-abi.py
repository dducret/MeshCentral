# SPDX-License-Identifier: Apache-2.0
"""Exercise the built Rust C ABI with bounds, lifecycle and real JSON output."""
import ctypes as c
import json
import sys

lib = c.CDLL(sys.argv[1])
lib.mc_inventory_new.restype = c.c_void_p
lib.mc_inventory_begin.argtypes = [c.c_void_p, c.c_uint64, c.c_uint32, c.c_uint32]
lib.mc_inventory_begin.restype = c.c_int32
for name in ['mc_inventory_complete', 'mc_inventory_free']:
    getattr(lib, name).argtypes = [c.c_void_p]
    getattr(lib, name).restype = None
lib.mc_inventory_write.argtypes = [c.c_void_p,c.c_size_t,c.c_void_p,c.c_size_t,c.c_uint64,c.c_uint32,c.c_uint32,c.c_uint32,c.c_int32,c.c_uint32,c.c_void_p,c.c_size_t]
lib.mc_inventory_write.restype = c.c_size_t
handle = lib.mc_inventory_new()
assert handle
try:
    assert lib.mc_inventory_begin(None,0,0,0)==0
    assert lib.mc_inventory_begin(handle,0,8,1)==0
    assert lib.mc_inventory_begin(handle,0,0,2)==0
    assert lib.mc_inventory_begin(handle,0,0x100008,1)==1
    assert lib.mc_inventory_begin(handle,5000,0,0)==0
    lib.mc_inventory_complete(handle)
    assert lib.mc_inventory_begin(handle,4999,0,0)==0
    assert lib.mc_inventory_begin(handle,5000,0,0)==1
finally:
    lib.mc_inventory_free(handle)
lib.mc_inventory_free(None); lib.mc_inventory_complete(None)
buffer = c.create_string_buffer(2048)
args = [b'iPad',4,b'iPad14,3',8,8589934592,8,1,0,0,1,buffer,2048]
length = lib.mc_inventory_write(*args)
assert 0 < length < 2048
data = json.loads(buffer.raw[:length])
assert data['hardware']['battery'][0]['BatteryCharge']=='0'
assert data['hardware']['darwin']['memory'][0]['Size']=='8192 MiB'
for index, value in [(0,None),(1,65),(2,None),(3,65),(6,3),(7,2),(8,101),(9,4),(10,None),(11,2049),(11,length-1),(11,0)]:
    invalid=args.copy();invalid[index]=value
    assert lib.mc_inventory_write(*invalid)==0,(index,value)
assert lib.mc_inventory_write(*args)==length
print('PASS: inventory C ABI JSON, nulls, input/output bounds, permissions, one pending operation, and rate limit.')
