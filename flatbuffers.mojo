# ============================================================================
# flatbuffers.mojo — Pure-Mojo FlatBuffers Binary Format Encoder/Decoder
# ============================================================================
#
# Implements the FlatBuffers binary wire format (https://flatbuffers.dev).
# Schema-agnostic: callers address fields by slot index, not field name.
#
# Usage (write):
#   var b = FlatBufferBuilder()
#   var s = b.create_string("hello")
#   b.start_table(1)
#   b.add_field_offset(0, s)
#   var root = b.end_table()
#   var buf = b.finish(root)
#
# Usage (read):
#   var r = FlatBuffersReader(buf^)
#   var tp = r.root()
#   var msg = r.read_string(tp, 0)
#
# ============================================================================

from std.memory.unsafe_pointer import alloc

# ============================================================================
# Offset type constants (FlatBuffers spec §2)
# ============================================================================

# UOffset = UInt32  — forward offset relative to its own storage position
# SOffset = Int32   — signed offset used for table → vtable pointer
# VOffset = UInt16  — offset within a vtable

# ============================================================================
# Little-endian write helpers
#
# All write_* functions overwrite bytes at `pos` inside a pre-sized List[UInt8].
# They do NOT append — the caller must ensure buf is large enough.
# Integer write_i* uses signed arithmetic via Int64 to safely extract bytes
# from negative values without relying on bitcast.
# Float write_f* uses UnsafePointer.bitcast to reinterpret IEEE 754 bits.
# ============================================================================


fn write_u8(mut buf: List[UInt8], pos: Int, val: UInt8):
    buf[pos] = val


fn write_u16_le(mut buf: List[UInt8], pos: Int, val: UInt16):
    buf[pos]     = UInt8(val & UInt16(0xFF))
    buf[pos + 1] = UInt8((val >> 8) & UInt16(0xFF))


fn write_u32_le(mut buf: List[UInt8], pos: Int, val: UInt32):
    buf[pos]     = UInt8(val & UInt32(0xFF))
    buf[pos + 1] = UInt8((val >> 8) & UInt32(0xFF))
    buf[pos + 2] = UInt8((val >> 16) & UInt32(0xFF))
    buf[pos + 3] = UInt8((val >> 24) & UInt32(0xFF))


fn write_i32_le(mut buf: List[UInt8], pos: Int, val: Int32):
    # Use Int64 arithmetic so negative values shift/mask correctly.
    var v = Int64(val)
    buf[pos]     = UInt8(Int32(v & Int64(0xFF)))
    buf[pos + 1] = UInt8(Int32((v >> 8) & Int64(0xFF)))
    buf[pos + 2] = UInt8(Int32((v >> 16) & Int64(0xFF)))
    buf[pos + 3] = UInt8(Int32((v >> 24) & Int64(0xFF)))


fn write_i64_le(mut buf: List[UInt8], pos: Int, val: Int64):
    buf[pos]     = UInt8(Int32(val & Int64(0xFF)))
    buf[pos + 1] = UInt8(Int32((val >> 8) & Int64(0xFF)))
    buf[pos + 2] = UInt8(Int32((val >> 16) & Int64(0xFF)))
    buf[pos + 3] = UInt8(Int32((val >> 24) & Int64(0xFF)))
    buf[pos + 4] = UInt8(Int32((val >> 32) & Int64(0xFF)))
    buf[pos + 5] = UInt8(Int32((val >> 40) & Int64(0xFF)))
    buf[pos + 6] = UInt8(Int32((val >> 48) & Int64(0xFF)))
    buf[pos + 7] = UInt8(Int32((val >> 56) & Int64(0xFF)))


fn write_u64_le(mut buf: List[UInt8], pos: Int, val: UInt64):
    buf[pos]     = UInt8(UInt32(val & UInt64(0xFF)))
    buf[pos + 1] = UInt8(UInt32((val >> 8) & UInt64(0xFF)))
    buf[pos + 2] = UInt8(UInt32((val >> 16) & UInt64(0xFF)))
    buf[pos + 3] = UInt8(UInt32((val >> 24) & UInt64(0xFF)))
    buf[pos + 4] = UInt8(UInt32((val >> 32) & UInt64(0xFF)))
    buf[pos + 5] = UInt8(UInt32((val >> 40) & UInt64(0xFF)))
    buf[pos + 6] = UInt8(UInt32((val >> 48) & UInt64(0xFF)))
    buf[pos + 7] = UInt8(UInt32((val >> 56) & UInt64(0xFF)))


fn write_f32_le(mut buf: List[UInt8], pos: Int, val: Float32):
    # Reinterpret float bits as UInt32 via heap alloc + bitcast, then write LE.
    var tmp = alloc[Float32](1)
    tmp[] = val
    var u = tmp.bitcast[UInt32]()[]
    tmp.free()
    write_u32_le(buf, pos, u)


fn write_f64_le(mut buf: List[UInt8], pos: Int, val: Float64):
    var tmp = alloc[Float64](1)
    tmp[] = val
    var u = tmp.bitcast[UInt64]()[]
    tmp.free()
    write_u64_le(buf, pos, u)


# ============================================================================
# Little-endian read helpers
#
# All read_* functions raise Error on out-of-bounds access.
# Bounds check: pos + sizeof(T) - 1 must be < len(buf).
# All intermediate arithmetic uses Int (platform word) to avoid unsigned wrap.
# ============================================================================


fn read_u8(buf: List[UInt8], pos: Int) raises -> UInt8:
    if pos < 0 or pos >= len(buf):
        raise Error("flatbuffers: read_u8 out of bounds at " + String(pos))
    return buf[pos]


fn read_u16_le(buf: List[UInt8], pos: Int) raises -> UInt16:
    if pos < 0 or pos + 1 >= len(buf):
        raise Error("flatbuffers: read_u16_le out of bounds at " + String(pos))
    return UInt16(buf[pos]) | (UInt16(buf[pos + 1]) << 8)


fn read_u32_le(buf: List[UInt8], pos: Int) raises -> UInt32:
    if pos < 0 or pos + 3 >= len(buf):
        raise Error("flatbuffers: read_u32_le out of bounds at " + String(pos))
    return (UInt32(buf[pos])
        | (UInt32(buf[pos + 1]) << 8)
        | (UInt32(buf[pos + 2]) << 16)
        | (UInt32(buf[pos + 3]) << 24))


fn read_i32_le(buf: List[UInt8], pos: Int) raises -> Int32:
    var u = read_u32_le(buf, pos)
    var tmp = alloc[UInt32](1)
    tmp[] = u
    var result = tmp.bitcast[Int32]()[]
    tmp.free()
    return result


fn read_i64_le(buf: List[UInt8], pos: Int) raises -> Int64:
    var u = read_u64_le(buf, pos)
    var tmp = alloc[UInt64](1)
    tmp[] = u
    var result = tmp.bitcast[Int64]()[]
    tmp.free()
    return result


fn read_u64_le(buf: List[UInt8], pos: Int) raises -> UInt64:
    if pos < 0 or pos + 7 >= len(buf):
        raise Error("flatbuffers: read_u64_le out of bounds at " + String(pos))
    return (UInt64(buf[pos])
        | (UInt64(buf[pos + 1]) << 8)
        | (UInt64(buf[pos + 2]) << 16)
        | (UInt64(buf[pos + 3]) << 24)
        | (UInt64(buf[pos + 4]) << 32)
        | (UInt64(buf[pos + 5]) << 40)
        | (UInt64(buf[pos + 6]) << 48)
        | (UInt64(buf[pos + 7]) << 56))


fn read_f32_le(buf: List[UInt8], pos: Int) raises -> Float32:
    var u = read_u32_le(buf, pos)
    var tmp = alloc[UInt32](1)
    tmp[] = u
    var result = tmp.bitcast[Float32]()[]
    tmp.free()
    return result


fn read_f64_le(buf: List[UInt8], pos: Int) raises -> Float64:
    var u = read_u64_le(buf, pos)
    var tmp = alloc[UInt64](1)
    tmp[] = u
    var result = tmp.bitcast[Float64]()[]
    tmp.free()
    return result


# ============================================================================
# Alignment helper
# ============================================================================


fn padding_to(pos: Int, alignment: Int) -> Int:
    """Return bytes needed to align `pos` up to the next `alignment` boundary."""
    return (alignment - (pos % alignment)) % alignment
