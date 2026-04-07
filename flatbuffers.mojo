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


# ============================================================================
# FlatBufferBuilder
#
# Writes data back-to-front (prepend model): _head decrements on each write.
# The valid buffer content lives at _buf[_head:].
# finish(root) prepends the 4-byte root UOffset and returns a copy of _buf[_head:].
#
# Usage:
#   var b = FlatBufferBuilder()
#   var s = b.create_string("hello")
#   b.start_table(1)
#   b.add_field_offset(0, s)
#   var root = b.end_table()
#   var out = b.finish(root)
# ============================================================================


struct FlatBufferBuilder(Movable):
    var _buf: List[UInt8]    # backing store; valid data at _buf[_head:]
    var _head: Int           # write cursor; decrements on each prepend
    var _min_align: Int      # max alignment seen — used to pad finish()

    fn __init__(out self, initial_capacity: Int = 256):
        self._buf = List[UInt8](capacity=initial_capacity)
        for _ in range(initial_capacity):
            self._buf.append(UInt8(0))
        self._head = initial_capacity
        self._min_align = 1

    fn __moveinit__(out self, deinit take: Self):
        self._buf = take._buf^
        self._head = take._head
        self._min_align = take._min_align

    # ------------------------------------------------------------------
    # Internal: grow the buffer by doubling, shifting written bytes to end
    # ------------------------------------------------------------------

    fn _grow(mut self):
        var old_size = len(self._buf)
        var new_size = old_size * 2
        var written = old_size - self._head
        # Build new buffer filled with zeros
        var new_buf = List[UInt8](capacity=new_size)
        for _ in range(new_size):
            new_buf.append(UInt8(0))
        # Copy existing written bytes to the end of new buffer
        var new_head = new_size - written
        for i in range(written):
            new_buf[new_head + i] = self._buf[self._head + i]
        self._buf = new_buf^
        self._head = new_head

    # ------------------------------------------------------------------
    # Internal: ensure at least `needed` bytes of headroom, then align
    # _head down to `align` boundary.
    # ------------------------------------------------------------------

    fn _prep(mut self, align: Int, needed: Int = 0):
        if align > self._min_align:
            self._min_align = align
        # Grow until there is room for `needed` bytes plus alignment padding
        while self._head < needed + align:
            self._grow()
        # Pad with zeros up to the alignment boundary
        var pad = padding_to(len(self._buf) - self._head + needed, align)
        for _ in range(pad):
            self._head -= 1
            self._buf[self._head] = UInt8(0)

    # ------------------------------------------------------------------
    # Current offset (distance from tail): the UOffset of the last prepended
    # object. Stable even after _grow since both len and _head move together.
    # ------------------------------------------------------------------

    fn offset(self) -> UInt32:
        return UInt32(len(self._buf) - self._head)

    # ------------------------------------------------------------------
    # Low-level prepend — each method calls _prep for alignment then writes
    # ------------------------------------------------------------------

    fn prepend_u8(mut self, val: UInt8):
        self._prep(1, 1)
        self._head -= 1
        self._buf[self._head] = val

    fn prepend_bool(mut self, val: Bool):
        self.prepend_u8(UInt8(1) if val else UInt8(0))

    fn prepend_u16(mut self, val: UInt16):
        self._prep(2, 2)
        self._head -= 2
        write_u16_le(self._buf, self._head, val)

    fn prepend_i16(mut self, val: Int16):
        self._prep(2, 2)
        self._head -= 2
        # Extract bytes via Int32 arithmetic
        var v = Int32(val)
        self._buf[self._head]     = UInt8(Int32(v & Int32(0xFF)))
        self._buf[self._head + 1] = UInt8(Int32((v >> 8) & Int32(0xFF)))

    fn prepend_u32(mut self, val: UInt32):
        self._prep(4, 4)
        self._head -= 4
        write_u32_le(self._buf, self._head, val)

    fn prepend_i32(mut self, val: Int32):
        self._prep(4, 4)
        self._head -= 4
        write_i32_le(self._buf, self._head, val)

    fn prepend_u64(mut self, val: UInt64):
        self._prep(8, 8)
        self._head -= 8
        write_u64_le(self._buf, self._head, val)

    fn prepend_i64(mut self, val: Int64):
        self._prep(8, 8)
        self._head -= 8
        write_i64_le(self._buf, self._head, val)

    fn prepend_f32(mut self, val: Float32):
        self._prep(4, 4)
        self._head -= 4
        write_f32_le(self._buf, self._head, val)

    fn prepend_f64(mut self, val: Float64):
        self._prep(8, 8)
        self._head -= 8
        write_f64_le(self._buf, self._head, val)

    # ------------------------------------------------------------------
    # String creation
    # FlatBuffers string layout (written right-to-left via prepend):
    #   [null byte][utf8 bytes in reverse][u32 length]
    # When read forward in the final buffer:
    #   [u32 length][utf8 bytes][null byte]
    # ------------------------------------------------------------------

    fn create_string(mut self, s: String) raises -> UInt32:
        var bytes = s.as_bytes()
        var n = len(bytes)
        # _prep(4, n+1): add alignment padding so that after writing n+1 bytes
        # (content + null), the next write (4-byte length) will be 4-byte aligned.
        # The padding goes at the lowest address — before the length in forward view.
        # We do NOT call _prep inside the individual byte writes that follow.
        self._prep(4, n + 1)
        # Prepend null terminator (ends up at highest address = after string bytes)
        self._head -= 1
        self._buf[self._head] = UInt8(0)
        # Prepend UTF-8 bytes in reverse order (no per-byte _prep — space is reserved)
        for i in range(n - 1, -1, -1):
            self._head -= 1
            self._buf[self._head] = bytes[i]
        # Prepend 4-byte length (4-byte aligned due to _prep above)
        self._head -= 4
        write_u32_le(self._buf, self._head, UInt32(n))
        return self.offset()
