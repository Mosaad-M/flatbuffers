from flatbuffers import (
    write_u8, write_u16_le, write_u32_le, write_i32_le,
    write_i64_le, write_u64_le, write_f32_le, write_f64_le,
    read_u8, read_u16_le, read_u32_le, read_i32_le,
    read_i64_le, read_u64_le, read_f32_le, read_f64_le,
    padding_to,
    FieldLoc, FlatBufferBuilder, FlatBuffersReader,
)


# ============================================================================
# Test helpers
# ============================================================================


fn assert_eq_u8(actual: UInt8, expected: UInt8, msg: String = "") raises:
    if actual != expected:
        var m = "expected " + String(expected) + " got " + String(actual)
        if len(msg) > 0:
            m = msg + ": " + m
        raise Error(m)


fn assert_eq_u16(actual: UInt16, expected: UInt16, msg: String = "") raises:
    if actual != expected:
        var m = "expected " + String(expected) + " got " + String(actual)
        if len(msg) > 0:
            m = msg + ": " + m
        raise Error(m)


fn assert_eq_u32(actual: UInt32, expected: UInt32, msg: String = "") raises:
    if actual != expected:
        var m = "expected " + String(expected) + " got " + String(actual)
        if len(msg) > 0:
            m = msg + ": " + m
        raise Error(m)


fn assert_eq_i32(actual: Int32, expected: Int32, msg: String = "") raises:
    if actual != expected:
        var m = "expected " + String(expected) + " got " + String(actual)
        if len(msg) > 0:
            m = msg + ": " + m
        raise Error(m)


fn assert_eq_u64(actual: UInt64, expected: UInt64, msg: String = "") raises:
    if actual != expected:
        var m = "expected " + String(expected) + " got " + String(actual)
        if len(msg) > 0:
            m = msg + ": " + m
        raise Error(m)


fn assert_eq_int(actual: Int, expected: Int, msg: String = "") raises:
    if actual != expected:
        var m = "expected " + String(expected) + " got " + String(actual)
        if len(msg) > 0:
            m = msg + ": " + m
        raise Error(m)


fn assert_true(cond: Bool, msg: String = "") raises:
    if not cond:
        if len(msg) > 0:
            raise Error(msg)
        raise Error("expected True")


fn assert_raises(name: String) raises:
    raise Error("expected Error to be raised in: " + name)


fn assert_f32_near(a: Float32, b: Float32, eps: Float32) raises:
    var diff = a - b
    if diff < -eps or diff > eps:
        raise Error("f32 not near: " + String(a) + " vs " + String(b))


fn assert_f64_near(a: Float64, b: Float64, eps: Float64) raises:
    var diff = a - b
    if diff < -eps or diff > eps:
        raise Error("f64 not near: " + String(a) + " vs " + String(b))


fn _make_buf(size: Int) -> List[UInt8]:
    var b = List[UInt8](capacity=size)
    for _ in range(size):
        b.append(UInt8(0))
    return b^


# ============================================================================
# Phase 1 tests — LE read/write primitives
# ============================================================================


fn test_write_read_u8_roundtrip() raises:
    var buf = _make_buf(4)
    write_u8(buf, 0, UInt8(0x42))
    assert_eq_u8(read_u8(buf, 0), UInt8(0x42))
    write_u8(buf, 3, UInt8(0xFF))
    assert_eq_u8(read_u8(buf, 3), UInt8(0xFF))


fn test_write_read_u16_le_byte_order() raises:
    var buf = _make_buf(4)
    write_u16_le(buf, 0, UInt16(0xABCD))
    # little-endian: low byte first
    assert_eq_u8(buf[0], UInt8(0xCD), "low byte")
    assert_eq_u8(buf[1], UInt8(0xAB), "high byte")
    assert_eq_u16(read_u16_le(buf, 0), UInt16(0xABCD), "roundtrip")


fn test_write_read_u32_le_roundtrip() raises:
    var buf = _make_buf(8)
    write_u32_le(buf, 0, UInt32(0xDEADBEEF))
    assert_eq_u8(buf[0], UInt8(0xEF), "byte0")
    assert_eq_u8(buf[1], UInt8(0xBE), "byte1")
    assert_eq_u8(buf[2], UInt8(0xAD), "byte2")
    assert_eq_u8(buf[3], UInt8(0xDE), "byte3")
    assert_eq_u32(read_u32_le(buf, 0), UInt32(0xDEADBEEF), "roundtrip")
    # also test at non-zero offset
    write_u32_le(buf, 4, UInt32(0x12345678))
    assert_eq_u32(read_u32_le(buf, 4), UInt32(0x12345678), "offset 4")


fn test_write_read_i32_le_negative() raises:
    var buf = _make_buf(4)
    write_i32_le(buf, 0, Int32(-1))
    # -1 in two's complement = 0xFFFFFFFF
    assert_eq_u8(buf[0], UInt8(0xFF))
    assert_eq_u8(buf[1], UInt8(0xFF))
    assert_eq_u8(buf[2], UInt8(0xFF))
    assert_eq_u8(buf[3], UInt8(0xFF))
    assert_eq_i32(read_i32_le(buf, 0), Int32(-1), "roundtrip")
    write_i32_le(buf, 0, Int32(-2147483648))  # INT32_MIN
    assert_eq_i32(read_i32_le(buf, 0), Int32(-2147483648), "INT32_MIN")


fn test_write_read_u64_le_roundtrip() raises:
    var buf = _make_buf(8)
    var val = UInt64(0xCAFEBABEDEADBEEF)
    write_u64_le(buf, 0, val)
    assert_eq_u64(read_u64_le(buf, 0), val, "roundtrip")
    # verify first byte is the least significant
    assert_eq_u8(buf[0], UInt8(0xEF), "lowest byte")
    assert_eq_u8(buf[7], UInt8(0xCA), "highest byte")


fn test_write_read_f32_le_roundtrip() raises:
    var buf = _make_buf(4)
    var val = Float32(1.0)
    write_f32_le(buf, 0, val)
    var back = read_f32_le(buf, 0)
    # exact bit equality for 1.0 (IEEE 754 representable exactly)
    assert_true(back == val, "1.0 roundtrip")
    write_f32_le(buf, 0, Float32(-3.14))
    var back2 = read_f32_le(buf, 0)
    assert_true(back2 == Float32(-3.14), "-3.14 roundtrip")


fn test_write_read_f64_le_roundtrip() raises:
    var buf = _make_buf(8)
    var val = Float64(3.141592653589793)
    write_f64_le(buf, 0, val)
    var back = read_f64_le(buf, 0)
    assert_true(back == val, "pi roundtrip")
    write_f64_le(buf, 0, Float64(0.0))
    assert_true(read_f64_le(buf, 0) == Float64(0.0), "zero roundtrip")


fn test_padding_to_already_aligned() raises:
    assert_eq_int(padding_to(8, 4), 0, "8 mod 4")
    assert_eq_int(padding_to(0, 8), 0, "0 mod 8")
    assert_eq_int(padding_to(16, 8), 0, "16 mod 8")
    assert_eq_int(padding_to(4, 4), 0, "4 mod 4")


fn test_padding_to_needs_padding() raises:
    assert_eq_int(padding_to(5, 4), 3, "5→4")
    assert_eq_int(padding_to(1, 8), 7, "1→8")
    assert_eq_int(padding_to(3, 4), 1, "3→4")
    assert_eq_int(padding_to(7, 8), 1, "7→8")
    assert_eq_int(padding_to(1, 2), 1, "1→2")


fn test_read_out_of_bounds_raises() raises:
    var buf = _make_buf(3)
    # read_u32_le needs 4 bytes; pos=0 needs bytes 0..3 but buf only has 3
    var raised = False
    try:
        _ = read_u32_le(buf, 0)
    except:
        raised = True
    assert_true(raised, "read_u32_le on 3-byte buf should raise")

    var raised2 = False
    try:
        _ = read_u8(buf, 5)
    except:
        raised2 = True
    assert_true(raised2, "read_u8 past end should raise")

    var raised3 = False
    try:
        _ = read_u64_le(buf, 0)
    except:
        raised3 = True
    assert_true(raised3, "read_u64_le on 3-byte buf should raise")


# ============================================================================
# Phase 2 tests — FlatBufferBuilder scalars and strings
# ============================================================================


fn test_builder_initial_state() raises:
    var b = FlatBufferBuilder(256)
    assert_eq_int(len(b._buf), 256, "buf size")
    assert_eq_int(b._head, 256, "head at end")
    assert_eq_u32(b.offset(), UInt32(0), "offset is 0")


fn test_prepend_u8_single() raises:
    var b = FlatBufferBuilder(256)
    b.prepend_u8(UInt8(0x55))
    assert_eq_u32(b.offset(), UInt32(1), "offset after u8")
    assert_eq_u8(b._buf[b._head], UInt8(0x55), "value at head")


fn test_prepend_u32_alignment() raises:
    var b = FlatBufferBuilder(256)
    # Prepend a u8 first to misalign, then prepend u32 — should insert 3 padding bytes
    b.prepend_u8(UInt8(0x01))
    _ = b._head
    b.prepend_u32(UInt32(0xDEADBEEF))
    # u32 needs 4-byte alignment: from tail side, (written+needed) % 4 == 0
    # The u32 itself is 4 bytes; head should be 4-byte aligned in the buffer
    assert_eq_int(b._head % 4, 0, "head aligned to 4")
    # Value at head must be correct LE encoding
    assert_eq_u8(b._buf[b._head],     UInt8(0xEF), "byte0")
    assert_eq_u8(b._buf[b._head + 1], UInt8(0xBE), "byte1")
    assert_eq_u8(b._buf[b._head + 2], UInt8(0xAD), "byte2")
    assert_eq_u8(b._buf[b._head + 3], UInt8(0xDE), "byte3")


fn test_prepend_scalars_layout() raises:
    var b = FlatBufferBuilder(256)
    b.prepend_u8(UInt8(0xAA))
    b.prepend_u16(UInt16(0x1234))
    b.prepend_u32(UInt32(0x89ABCDEF))
    # Read back via read helpers using the finalized sub-buffer
    var head = b._head
    var buf = b._buf.copy()
    # u32 is lowest (prepended last so at head)
    assert_eq_u8(buf[head],     UInt8(0xEF), "u32 b0")
    assert_eq_u8(buf[head + 1], UInt8(0xCD), "u32 b1")
    assert_eq_u8(buf[head + 2], UInt8(0xAB), "u32 b2")
    assert_eq_u8(buf[head + 3], UInt8(0x89), "u32 b3")


fn test_builder_grow_on_overflow() raises:
    var b = FlatBufferBuilder(64)
    # Prepend 300 u8 bytes to force multiple grows
    for i in range(300):
        b.prepend_u8(UInt8(i % 256))
    assert_eq_u32(b.offset(), UInt32(300), "offset after 300 bytes")
    # Verify a few values: the last prepended (i=299) is at head
    assert_eq_u8(b._buf[b._head], UInt8(299 % 256), "last prepended at head")
    # First prepended (i=0) is at tail-1
    assert_eq_u8(b._buf[len(b._buf) - 1], UInt8(0), "first prepended at tail")


fn _buf_at_offset(b: FlatBufferBuilder, off: UInt32) -> Int:
    # Convert a UOffset (distance from tail) to absolute buf index
    return len(b._buf) - Int(off)


fn test_create_string_hello() raises:
    var b = FlatBufferBuilder(256)
    var off = b.create_string("hello")
    # UOffset points to start of string object = length field
    var abs_pos = _buf_at_offset(b, off)
    # length field = 5
    assert_eq_u32(
        UInt32(b._buf[abs_pos])
        | (UInt32(b._buf[abs_pos + 1]) << 8)
        | (UInt32(b._buf[abs_pos + 2]) << 16)
        | (UInt32(b._buf[abs_pos + 3]) << 24),
        UInt32(5), "length")
    # bytes h,e,l,l,o
    assert_eq_u8(b._buf[abs_pos + 4], UInt8(ord("h")), "h")
    assert_eq_u8(b._buf[abs_pos + 5], UInt8(ord("e")), "e")
    assert_eq_u8(b._buf[abs_pos + 6], UInt8(ord("l")), "l1")
    assert_eq_u8(b._buf[abs_pos + 7], UInt8(ord("l")), "l2")
    assert_eq_u8(b._buf[abs_pos + 8], UInt8(ord("o")), "o")
    # null terminator
    assert_eq_u8(b._buf[abs_pos + 9], UInt8(0), "null")


fn test_create_string_empty() raises:
    var b = FlatBufferBuilder(256)
    var off = b.create_string("")
    var abs_pos = _buf_at_offset(b, off)
    # length = 0
    assert_eq_u32(
        UInt32(b._buf[abs_pos])
        | (UInt32(b._buf[abs_pos + 1]) << 8)
        | (UInt32(b._buf[abs_pos + 2]) << 16)
        | (UInt32(b._buf[abs_pos + 3]) << 24),
        UInt32(0), "empty length")
    # null terminator immediately after length
    assert_eq_u8(b._buf[abs_pos + 4], UInt8(0), "null after empty")


fn test_create_string_unicode() raises:
    # "café" = 'c','a','f','é' where é = 0xC3 0xA9 (UTF-8, 2 bytes)
    var b = FlatBufferBuilder(256)
    var off = b.create_string("café")
    var abs_pos = _buf_at_offset(b, off)
    # UTF-8 byte count: c(1) + a(1) + f(1) + é(2) = 5
    var length = (UInt32(b._buf[abs_pos])
        | (UInt32(b._buf[abs_pos + 1]) << 8)
        | (UInt32(b._buf[abs_pos + 2]) << 16)
        | (UInt32(b._buf[abs_pos + 3]) << 24))
    assert_eq_u32(length, UInt32(5), "byte length of café")
    assert_eq_u8(b._buf[abs_pos + 4], UInt8(ord("c")), "c")
    assert_eq_u8(b._buf[abs_pos + 5], UInt8(ord("a")), "a")
    assert_eq_u8(b._buf[abs_pos + 6], UInt8(ord("f")), "f")
    assert_eq_u8(b._buf[abs_pos + 7], UInt8(0xC3), "é high byte")
    assert_eq_u8(b._buf[abs_pos + 8], UInt8(0xA9), "é low byte")
    assert_eq_u8(b._buf[abs_pos + 9], UInt8(0), "null")


# ============================================================================
# Phase 3 tests — vectors, tables, finish
# ============================================================================


fn test_create_vector_u8_empty() raises:
    var b = FlatBufferBuilder()
    var off = b.create_vector_u8(List[UInt8]())
    var abs_pos = _buf_at_offset(b, off)
    # count = 0
    assert_eq_u32(
        UInt32(b._buf[abs_pos])
        | (UInt32(b._buf[abs_pos + 1]) << 8)
        | (UInt32(b._buf[abs_pos + 2]) << 16)
        | (UInt32(b._buf[abs_pos + 3]) << 24),
        UInt32(0), "empty vector count")


fn test_create_vector_u8_values() raises:
    var b = FlatBufferBuilder()
    var data = List[UInt8]()
    data.append(UInt8(1))
    data.append(UInt8(2))
    data.append(UInt8(3))
    var off = b.create_vector_u8(data)
    var abs_pos = _buf_at_offset(b, off)
    # count = 3
    assert_eq_u32(
        UInt32(b._buf[abs_pos])
        | (UInt32(b._buf[abs_pos + 1]) << 8)
        | (UInt32(b._buf[abs_pos + 2]) << 16)
        | (UInt32(b._buf[abs_pos + 3]) << 24),
        UInt32(3), "count")
    assert_eq_u8(b._buf[abs_pos + 4], UInt8(1), "elem0")
    assert_eq_u8(b._buf[abs_pos + 5], UInt8(2), "elem1")
    assert_eq_u8(b._buf[abs_pos + 6], UInt8(3), "elem2")


fn test_create_vector_u32_alignment() raises:
    var b = FlatBufferBuilder()
    var data = List[UInt32]()
    data.append(UInt32(0xDEAD))
    data.append(UInt32(0xBEEF))
    var off = b.create_vector_u32(data)
    var abs_pos = _buf_at_offset(b, off)
    # count = 2
    assert_eq_u32(
        UInt32(b._buf[abs_pos])
        | (UInt32(b._buf[abs_pos + 1]) << 8)
        | (UInt32(b._buf[abs_pos + 2]) << 16)
        | (UInt32(b._buf[abs_pos + 3]) << 24),
        UInt32(2), "count")
    # elem0 at abs_pos+4
    assert_eq_u32(
        UInt32(b._buf[abs_pos + 4])
        | (UInt32(b._buf[abs_pos + 5]) << 8)
        | (UInt32(b._buf[abs_pos + 6]) << 16)
        | (UInt32(b._buf[abs_pos + 7]) << 24),
        UInt32(0xDEAD), "elem0")
    assert_eq_u32(
        UInt32(b._buf[abs_pos + 8])
        | (UInt32(b._buf[abs_pos + 9]) << 8)
        | (UInt32(b._buf[abs_pos + 10]) << 16)
        | (UInt32(b._buf[abs_pos + 11]) << 24),
        UInt32(0xBEEF), "elem1")


fn test_start_end_table_empty() raises:
    var b = FlatBufferBuilder()
    b.start_table()
    var toff = b.end_table()
    # Table was created — toff should be nonzero
    assert_true(Int(toff) > 0, "table offset > 0")
    # vtable should have been recorded
    assert_eq_int(len(b._vtables), 1, "one vtable recorded")


fn test_table_one_i32_field() raises:
    var b = FlatBufferBuilder()
    b.start_table()
    b.add_field_i32(0, Int32(42))
    var toff = b.end_table()
    # Follow soffset from table to vtable
    var table_abs = len(b._buf) - Int(toff)
    var soffset = (Int32(b._buf[table_abs])
        | (Int32(b._buf[table_abs + 1]) << 8)
        | (Int32(b._buf[table_abs + 2]) << 16)
        | (Int32(b._buf[table_abs + 3]) << 24))
    var vtable_abs = table_abs + Int(soffset)
    assert_true(vtable_abs >= 0, "vtable at valid position")
    # vtable slot 0 should be nonzero (field is present)
    var slot0 = UInt16(b._buf[vtable_abs + 4]) | (UInt16(b._buf[vtable_abs + 5]) << 8)
    assert_true(Int(slot0) > 0, "slot 0 nonzero")


fn test_table_field_absent() raises:
    var b = FlatBufferBuilder()
    b.start_table()
    b.add_field_i32(0, Int32(99))
    # slot 1 intentionally skipped
    var toff = b.end_table()
    var table_abs = len(b._buf) - Int(toff)
    var soffset = (Int32(b._buf[table_abs])
        | (Int32(b._buf[table_abs + 1]) << 8)
        | (Int32(b._buf[table_abs + 2]) << 16)
        | (Int32(b._buf[table_abs + 3]) << 24))
    var vtable_abs = table_abs + Int(soffset)
    var vtable_size = UInt16(b._buf[vtable_abs]) | (UInt16(b._buf[vtable_abs + 1]) << 8)
    # vtable has 1 slot (only slot 0 was added): 4 + 2*1 = 6 bytes
    assert_eq_u16(vtable_size, UInt16(6), "vtable size")
    var slot0 = UInt16(b._buf[vtable_abs + 4]) | (UInt16(b._buf[vtable_abs + 5]) << 8)
    assert_true(Int(slot0) > 0, "slot 0 present")
    # slot 1 is absent: slot_byte=6 >= vtable_size=6, reader returns 0 (default)
    # vtable correctly has no entry for slot 1 — this is standard FlatBuffers behavior


fn test_vtable_deduplication() raises:
    var b = FlatBufferBuilder()
    # Build first table
    b.start_table()
    b.add_field_i32(0, Int32(1))
    var t1 = b.end_table()
    var vtables_after_first = len(b._vtables)
    # Build second identical-schema table
    b.start_table()
    b.add_field_i32(0, Int32(2))
    var t2 = b.end_table()
    # vtable count must NOT have increased (dedup)
    assert_eq_int(len(b._vtables), vtables_after_first, "vtable dedup")
    # Both table offsets must be different
    assert_true(t1 != t2, "different table offsets")


fn test_finish_root_offset() raises:
    var b = FlatBufferBuilder()
    b.start_table()
    var toff = b.end_table()
    var buf = b.finish(toff)
    # bytes 0..3 = root UOffset (position of root table in result buffer)
    var root = Int(UInt32(buf[0])
        | (UInt32(buf[1]) << 8)
        | (UInt32(buf[2]) << 16)
        | (UInt32(buf[3]) << 24))
    # root must be a valid index into buf, past the 4-byte header
    assert_true(root > 0 and root < len(buf), "root within buffer")
    # soffset at root must point to a valid vtable position
    var soff = Int32(buf[root]) | (Int32(buf[root+1]) << 8) | (Int32(buf[root+2]) << 16) | (Int32(buf[root+3]) << 24)
    var vt_abs = root + Int(soff)
    assert_true(vt_abs >= 0 and vt_abs < len(buf), "vtable within buffer")
    # vtable_size at vtable must be >= 4 (minimum: just the 4-byte header)
    var vt_size = Int(UInt16(buf[vt_abs]) | (UInt16(buf[vt_abs + 1]) << 8))
    assert_true(vt_size >= 4, "vtable header present")


fn test_table_with_string_field() raises:
    var b = FlatBufferBuilder()
    var soff = b.create_string("mojo")
    b.start_table()
    b.add_field_offset(0, soff)
    var toff = b.end_table()
    var buf = b.finish(toff)
    # Verify: root → table → follow offset field → string length = 4
    var root = Int(UInt32(buf[0]) | (UInt32(buf[1]) << 8) | (UInt32(buf[2]) << 16) | (UInt32(buf[3]) << 24))
    # soffset at root
    var so = Int32(buf[root]) | (Int32(buf[root + 1]) << 8) | (Int32(buf[root + 2]) << 16) | (Int32(buf[root + 3]) << 24)
    var vt_abs = root + Int(so)
    # slot 0 voffset
    var slot0 = Int(UInt16(buf[vt_abs + 4]) | (UInt16(buf[vt_abs + 5]) << 8))
    assert_true(slot0 > 0, "slot0 present")
    # field ref position
    var ref_pos = root + slot0
    var str_rel = Int(UInt32(buf[ref_pos]) | (UInt32(buf[ref_pos + 1]) << 8) | (UInt32(buf[ref_pos + 2]) << 16) | (UInt32(buf[ref_pos + 3]) << 24))
    var str_pos = ref_pos + str_rel
    var str_len = Int(UInt32(buf[str_pos]) | (UInt32(buf[str_pos + 1]) << 8) | (UInt32(buf[str_pos + 2]) << 16) | (UInt32(buf[str_pos + 3]) << 24))
    assert_eq_int(str_len, 4, "string length")
    assert_eq_u8(buf[str_pos + 4], UInt8(ord("m")), "m")
    assert_eq_u8(buf[str_pos + 5], UInt8(ord("o")), "o")
    assert_eq_u8(buf[str_pos + 6], UInt8(ord("j")), "j")
    assert_eq_u8(buf[str_pos + 7], UInt8(ord("o")), "o2")


fn test_nested_table() raises:
    # Inner table: one i32 field (value=99)
    var b = FlatBufferBuilder()
    b.start_table()
    b.add_field_i32(0, Int32(99))
    var inner = b.end_table()
    # Outer table: one offset field pointing to inner
    b.start_table()
    b.add_field_offset(0, inner)
    var outer = b.end_table()
    var buf = b.finish(outer)
    # Navigate: root → outer table → inner table → field = 99
    var root = Int(UInt32(buf[0]) | (UInt32(buf[1]) << 8) | (UInt32(buf[2]) << 16) | (UInt32(buf[3]) << 24))
    var so = Int32(buf[root]) | (Int32(buf[root+1]) << 8) | (Int32(buf[root+2]) << 16) | (Int32(buf[root+3]) << 24)
    var vt = root + Int(so)
    var slot0 = Int(UInt16(buf[vt + 4]) | (UInt16(buf[vt + 5]) << 8))
    var ref_pos = root + slot0
    var inner_rel = Int(UInt32(buf[ref_pos]) | (UInt32(buf[ref_pos+1]) << 8) | (UInt32(buf[ref_pos+2]) << 16) | (UInt32(buf[ref_pos+3]) << 24))
    var inner_abs = ref_pos + inner_rel
    # Now read inner table field 0
    var iso = Int32(buf[inner_abs]) | (Int32(buf[inner_abs+1]) << 8) | (Int32(buf[inner_abs+2]) << 16) | (Int32(buf[inner_abs+3]) << 24)
    var ivt = inner_abs + Int(iso)
    var islot0 = Int(UInt16(buf[ivt + 4]) | (UInt16(buf[ivt + 5]) << 8))
    var ival_pos = inner_abs + islot0
    var ival = Int32(buf[ival_pos]) | (Int32(buf[ival_pos+1]) << 8) | (Int32(buf[ival_pos+2]) << 16) | (Int32(buf[ival_pos+3]) << 24)
    assert_eq_i32(ival, Int32(99), "inner field value")


# ============================================================================
# Phase 4 tests — FlatBuffersReader scalars and strings
# ============================================================================


fn test_reader_root_offset() raises:
    var b = FlatBufferBuilder()
    b.start_table()
    b.add_field_i32(0, Int32(7))
    var toff = b.end_table()
    var buf = b.finish(toff)
    var r = FlatBuffersReader(buf)
    var root = r.root()
    # root must be a valid position past the 4-byte header and within the buffer
    assert_true(Int(root) >= 4, "root >= 4")
    assert_true(Int(root) < len(r._buf), "root < len(buf)")


fn test_reader_vtable_resolution() raises:
    var b = FlatBufferBuilder()
    b.start_table()
    b.add_field_i32(0, Int32(5))
    var toff = b.end_table()
    var buf = b.finish(toff)
    var r = FlatBuffersReader(buf)
    var tp = r.root()
    var vt_pos = r._vtable_pos(tp)
    # vtable must be before the table in the buffer (lower index)
    assert_true(vt_pos >= 0, "vtable >= 0")
    assert_true(vt_pos < Int(tp), "vtable before table")
    # vtable_size at vt_pos must be at least 6 (header + 1 slot)
    var vt_size = Int(UInt16(r._buf[vt_pos]) | (UInt16(r._buf[vt_pos + 1]) << 8))
    assert_true(vt_size >= 6, "vtable_size >= 6")


fn test_reader_scalar_i32() raises:
    var b = FlatBufferBuilder()
    b.start_table()
    b.add_field_i32(0, Int32(1234))
    var toff = b.end_table()
    var buf = b.finish(toff)
    var r = FlatBuffersReader(buf)
    var tp = r.root()
    assert_eq_i32(r.read_i32(tp, 0), Int32(1234), "i32 roundtrip")


fn test_reader_scalar_f64() raises:
    var b = FlatBufferBuilder()
    b.start_table()
    b.add_field_f64(0, Float64(3.141592653589793))
    var toff = b.end_table()
    var buf = b.finish(toff)
    var r = FlatBuffersReader(buf)
    var tp = r.root()
    var val = r.read_f64(tp, 0)
    # exact IEEE 754 roundtrip for a stored-then-read value
    assert_true(val == Float64(3.141592653589793), "f64 roundtrip")


fn test_reader_scalar_bool_true() raises:
    var b = FlatBufferBuilder()
    b.start_table()
    b.add_field_bool(0, True)
    var toff = b.end_table()
    var buf = b.finish(toff)
    var r = FlatBuffersReader(buf)
    var tp = r.root()
    assert_true(r.read_bool(tp, 0), "bool True roundtrip")


fn test_reader_scalar_bool_false() raises:
    var b = FlatBufferBuilder()
    b.start_table()
    b.add_field_bool(0, False)
    var toff = b.end_table()
    var buf = b.finish(toff)
    var r = FlatBuffersReader(buf)
    var tp = r.root()
    assert_true(not r.read_bool(tp, 0), "bool False roundtrip")


fn test_reader_absent_field_returns_default() raises:
    # Build a table with only slot 0; slot 1 and 2 are absent
    var b = FlatBufferBuilder()
    b.start_table()
    b.add_field_i32(0, Int32(42))
    var toff = b.end_table()
    var buf = b.finish(toff)
    var r = FlatBuffersReader(buf)
    var tp = r.root()
    # slot 0 present
    assert_eq_i32(r.read_i32(tp, 0), Int32(42), "slot 0 present")
    # slot 1 absent — should return default
    assert_eq_i32(r.read_i32(tp, 1, Int32(-99)), Int32(-99), "slot 1 default")
    # slot 2 absent — default 0
    assert_eq_i32(r.read_i32(tp, 2), Int32(0), "slot 2 zero default")


fn test_reader_string_field() raises:
    var b = FlatBufferBuilder()
    var soff = b.create_string("flatbuffers")
    b.start_table()
    b.add_field_offset(0, soff)
    var toff = b.end_table()
    var buf = b.finish(toff)
    var r = FlatBuffersReader(buf)
    var tp = r.root()
    var s = r.read_string(tp, 0)
    assert_true(s == "flatbuffers", "string roundtrip: " + s)


fn test_reader_string_unicode() raises:
    # "日本語" = 3 CJK characters, 9 bytes in UTF-8
    var b = FlatBufferBuilder()
    var soff = b.create_string("日本語")
    b.start_table()
    b.add_field_offset(0, soff)
    var toff = b.end_table()
    var buf = b.finish(toff)
    var r = FlatBuffersReader(buf)
    var tp = r.root()
    var s = r.read_string(tp, 0)
    assert_true(s == "日本語", "unicode string roundtrip: " + s)


fn test_reader_multi_field_table() raises:
    # Table with slot 0=i32(42), slot 1=f32(1.5), slot 2=string("hello")
    var b = FlatBufferBuilder()
    var soff = b.create_string("hello")
    b.start_table()
    b.add_field_i32(0, Int32(42))
    b.add_field_f32(1, Float32(1.5))
    b.add_field_offset(2, soff)
    var toff = b.end_table()
    var buf = b.finish(toff)
    var r = FlatBuffersReader(buf)
    var tp = r.root()
    assert_eq_i32(r.read_i32(tp, 0), Int32(42), "i32 field")
    assert_true(r.read_f32(tp, 1) == Float32(1.5), "f32 field")
    var s = r.read_string(tp, 2)
    assert_true(s == "hello", "string field: " + s)


# ============================================================================
# Phase 5 tests — FlatBuffersReader vectors, nested tables, unions
# ============================================================================


fn test_reader_vector_u8() raises:
    var b = FlatBufferBuilder()
    var data = List[UInt8]()
    data.append(UInt8(10))
    data.append(UInt8(20))
    data.append(UInt8(30))
    var voff = b.create_vector_u8(data)
    b.start_table()
    b.add_field_offset(0, voff)
    var toff = b.end_table()
    var buf = b.finish(toff)
    var r = FlatBuffersReader(buf)
    var tp = r.root()
    var vec_pos = r.read_vector(tp, 0)
    assert_eq_u32(r.vector_len(vec_pos), UInt32(3), "len")
    assert_eq_u8(r.vec_u8(vec_pos, UInt32(0)), UInt8(10), "elem0")
    assert_eq_u8(r.vec_u8(vec_pos, UInt32(1)), UInt8(20), "elem1")
    assert_eq_u8(r.vec_u8(vec_pos, UInt32(2)), UInt8(30), "elem2")


fn test_reader_vector_u32() raises:
    var b = FlatBufferBuilder()
    var data = List[UInt32]()
    data.append(UInt32(100))
    data.append(UInt32(200))
    data.append(UInt32(300))
    var voff = b.create_vector_u32(data)
    b.start_table()
    b.add_field_offset(0, voff)
    var toff = b.end_table()
    var buf = b.finish(toff)
    var r = FlatBuffersReader(buf)
    var tp = r.root()
    var vec_pos = r.read_vector(tp, 0)
    assert_eq_u32(r.vector_len(vec_pos), UInt32(3), "len")
    assert_eq_u32(r.vec_u32(vec_pos, UInt32(0)), UInt32(100), "elem0")
    assert_eq_u32(r.vec_u32(vec_pos, UInt32(1)), UInt32(200), "elem1")
    assert_eq_u32(r.vec_u32(vec_pos, UInt32(2)), UInt32(300), "elem2")


fn test_reader_vector_length_zero() raises:
    var b = FlatBufferBuilder()
    var voff = b.create_vector_u8(List[UInt8]())
    b.start_table()
    b.add_field_offset(0, voff)
    var toff = b.end_table()
    var buf = b.finish(toff)
    var r = FlatBuffersReader(buf)
    var tp = r.root()
    var vec_pos = r.read_vector(tp, 0)
    assert_eq_u32(r.vector_len(vec_pos), UInt32(0), "empty len")


fn test_reader_vector_of_strings() raises:
    var b = FlatBufferBuilder()
    var s1 = b.create_string("foo")
    var s2 = b.create_string("bar")
    var offsets = List[UInt32]()
    offsets.append(s1)
    offsets.append(s2)
    var voff = b.create_vector_offsets(offsets)
    b.start_table()
    b.add_field_offset(0, voff)
    var toff = b.end_table()
    var buf = b.finish(toff)
    var r = FlatBuffersReader(buf)
    var tp = r.root()
    var vec_pos = r.read_vector(tp, 0)
    assert_eq_u32(r.vector_len(vec_pos), UInt32(2), "len")
    var str0 = r.vec_string(vec_pos, UInt32(0))
    assert_true(str0 == "foo", "str0: " + str0)
    var str1 = r.vec_string(vec_pos, UInt32(1))
    assert_true(str1 == "bar", "str1: " + str1)


fn test_reader_nested_table() raises:
    var b = FlatBufferBuilder()
    b.start_table()
    b.add_field_i32(0, Int32(99))
    var inner = b.end_table()
    b.start_table()
    b.add_field_offset(0, inner)
    var outer = b.end_table()
    var buf = b.finish(outer)
    var r = FlatBuffersReader(buf)
    var outer_tp = r.root()
    var inner_tp = r.read_table(outer_tp, 0)
    assert_eq_i32(r.read_i32(inner_tp, 0), Int32(99), "nested i32")


fn test_reader_deeply_nested() raises:
    # A → B → C → i32=77
    var b = FlatBufferBuilder()
    b.start_table()
    b.add_field_i32(0, Int32(77))
    var c = b.end_table()
    b.start_table()
    b.add_field_offset(0, c)
    var bv = b.end_table()
    b.start_table()
    b.add_field_offset(0, bv)
    var a = b.end_table()
    var buf = b.finish(a)
    var r = FlatBuffersReader(buf)
    var a_tp = r.root()
    var b_tp = r.read_table(a_tp, 0)
    var c_tp = r.read_table(b_tp, 0)
    assert_eq_i32(r.read_i32(c_tp, 0), Int32(77), "deep nested i32")


fn test_reader_vector_of_tables() raises:
    var b = FlatBufferBuilder()
    b.start_table()
    b.add_field_i32(0, Int32(10))
    var t1 = b.end_table()
    b.start_table()
    b.add_field_i32(0, Int32(20))
    var t2 = b.end_table()
    var offsets = List[UInt32]()
    offsets.append(t1)
    offsets.append(t2)
    var voff = b.create_vector_offsets(offsets)
    b.start_table()
    b.add_field_offset(0, voff)
    var root_toff = b.end_table()
    var buf = b.finish(root_toff)
    var r = FlatBuffersReader(buf)
    var tp = r.root()
    var vec_pos = r.read_vector(tp, 0)
    assert_eq_u32(r.vector_len(vec_pos), UInt32(2), "len")
    var inner1 = r.vec_offset(vec_pos, UInt32(0))
    assert_eq_i32(r.read_i32(inner1, 0), Int32(10), "table0 i32")
    var inner2 = r.vec_offset(vec_pos, UInt32(1))
    assert_eq_i32(r.read_i32(inner2, 0), Int32(20), "table1 i32")


fn test_reader_union_present() raises:
    # Union: type slot=2 (u8), value slot=3 (UOffset to inner table)
    # Inner table has i32=55 at slot 0
    var b = FlatBufferBuilder()
    b.start_table()
    b.add_field_i32(0, Int32(55))
    var inner = b.end_table()
    b.start_table()
    b.add_field_u8(2, UInt8(2))
    b.add_field_offset(3, inner)
    var outer = b.end_table()
    var buf = b.finish(outer)
    var r = FlatBuffersReader(buf)
    var tp = r.root()
    assert_eq_u8(r.union_type(tp, 2), UInt8(2), "union type=2")
    var union_tp = r.union_table(tp, 3)
    assert_eq_i32(r.read_i32(union_tp, 0), Int32(55), "union table value")


fn test_reader_union_type_zero() raises:
    # No union set: type slot absent → type=0, value slot absent → union_table raises
    var b = FlatBufferBuilder()
    b.start_table()
    var toff = b.end_table()
    var buf = b.finish(toff)
    var r = FlatBuffersReader(buf)
    var tp = r.root()
    # absent u8 field returns default 0
    assert_eq_u8(r.union_type(tp, 2), UInt8(0), "absent type = 0")
    var raised = False
    try:
        _ = r.union_table(tp, 3)
    except:
        raised = True
    assert_true(raised, "union_table raises when absent")


fn test_reader_vector_bounds_check() raises:
    var b = FlatBufferBuilder()
    var data = List[UInt8]()
    data.append(UInt8(1))
    data.append(UInt8(2))
    data.append(UInt8(3))
    var voff = b.create_vector_u8(data)
    b.start_table()
    b.add_field_offset(0, voff)
    var toff = b.end_table()
    var buf = b.finish(toff)
    var r = FlatBuffersReader(buf)
    var tp = r.root()
    var vec_pos = r.read_vector(tp, 0)
    # Index 5 in a len-3 vector must raise
    var raised = False
    try:
        _ = r.vec_u8(vec_pos, UInt32(5))
    except:
        raised = True
    assert_true(raised, "index 5 in len-3 vector should raise")


# ============================================================================
# Phase 6 tests — edge cases, growth stress, v1.0.0
# ============================================================================


fn test_missing_field_default_i32() raises:
    var b = FlatBufferBuilder()
    b.start_table()
    b.add_field_i32(0, Int32(1))
    # slot 1 absent
    var toff = b.end_table()
    var buf = b.finish(toff)
    var r = FlatBuffersReader(buf)
    var tp = r.root()
    assert_eq_i32(r.read_i32(tp, 1, Int32(-42)), Int32(-42), "default -42")
    assert_eq_i32(r.read_i32(tp, 1), Int32(0), "default 0")


fn test_missing_field_default_f64() raises:
    var b = FlatBufferBuilder()
    b.start_table()
    b.add_field_i32(0, Int32(1))
    # slot 1 absent
    var toff = b.end_table()
    var buf = b.finish(toff)
    var r = FlatBuffersReader(buf)
    var tp = r.root()
    assert_f64_near(r.read_f64(tp, 1, Float64(3.14)), Float64(3.14), Float64(1e-15))
    assert_f64_near(r.read_f64(tp, 1), Float64(0.0), Float64(1e-15))


fn test_missing_string_raises() raises:
    var b = FlatBufferBuilder()
    b.start_table()
    var toff = b.end_table()
    var buf = b.finish(toff)
    var r = FlatBuffersReader(buf)
    var tp = r.root()
    var raised = False
    try:
        _ = r.read_string(tp, 0)
    except:
        raised = True
    assert_true(raised, "absent string slot must raise")


fn test_missing_offset_raises() raises:
    var b = FlatBufferBuilder()
    b.start_table()
    var toff = b.end_table()
    var buf = b.finish(toff)
    var r = FlatBuffersReader(buf)
    var tp = r.root()
    var raised = False
    try:
        _ = r.read_offset(tp, 0)
    except:
        raised = True
    assert_true(raised, "absent offset slot must raise")


fn test_buffer_growth_boundary() raises:
    # Builder with capacity 16; write exactly 16 bytes, then 1 more → growth
    var b = FlatBufferBuilder(16)
    for i in range(16):
        b.prepend_u8(UInt8(i + 1))
    # At this point _head == 0; one more byte forces growth
    b.prepend_u8(UInt8(0xFF))
    # Verify all 17 bytes are intact
    assert_eq_u32(b.offset(), UInt32(17), "offset after 17 bytes")
    assert_eq_u8(b._buf[b._head], UInt8(0xFF), "last byte correct")
    assert_eq_u8(b._buf[len(b._buf) - 1], UInt8(1), "first byte correct")


fn test_buffer_growth_50_strings() raises:
    var b = FlatBufferBuilder()
    var str_offs = List[UInt32]()
    for i in range(50):
        var off = b.create_string("s" + String(i))
        str_offs.append(off)
    var voff = b.create_vector_offsets(str_offs)
    b.start_table()
    b.add_field_offset(0, voff)
    var toff = b.end_table()
    var buf = b.finish(toff)
    var r = FlatBuffersReader(buf)
    var tp = r.root()
    var vec_pos = r.read_vector(tp, 0)
    assert_eq_u32(r.vector_len(vec_pos), UInt32(50), "50 strings")
    for i in range(50):
        var s = r.vec_string(vec_pos, UInt32(i))
        var expected = "s" + String(i)
        assert_true(s == expected, "str" + String(i) + ": " + s)


fn test_empty_string_roundtrip() raises:
    var b = FlatBufferBuilder()
    var soff = b.create_string("")
    b.start_table()
    b.add_field_offset(0, soff)
    var toff = b.end_table()
    var buf = b.finish(toff)
    var r = FlatBuffersReader(buf)
    var tp = r.root()
    var s = r.read_string(tp, 0)
    assert_true(s == "", "empty string: '" + s + "'")


fn test_empty_vector_u32() raises:
    var b = FlatBufferBuilder()
    var voff = b.create_vector_u32(List[UInt32]())
    b.start_table()
    b.add_field_offset(0, voff)
    var toff = b.end_table()
    var buf = b.finish(toff)
    var r = FlatBuffersReader(buf)
    var tp = r.root()
    var vec_pos = r.read_vector(tp, 0)
    assert_eq_u32(r.vector_len(vec_pos), UInt32(0), "empty vec len=0")


fn test_vtable_dedup_10_identical() raises:
    var b = FlatBufferBuilder()
    for i in range(10):
        b.start_table()
        b.add_field_i32(0, Int32(i))
        _ = b.end_table()
    # All 10 tables share one vtable schema → _vtables.size == 1
    assert_eq_int(len(b._vtables), 1, "10 identical tables → 1 vtable")


fn test_full_composite_roundtrip() raises:
    var b = FlatBufferBuilder()
    # Inner nested table
    b.start_table()
    b.add_field_i32(0, Int32(42))
    var inner = b.end_table()
    # String
    var soff = b.create_string("composite")
    # u32 vector [1, 2, 3]
    var data = List[UInt32]()
    data.append(UInt32(1))
    data.append(UInt32(2))
    data.append(UInt32(3))
    var voff = b.create_vector_u32(data)
    # Outer table: slot 0=i32, slot 1=string, slot 2=vec, slot 3=nested
    b.start_table()
    b.add_field_i32(0, Int32(99))
    b.add_field_offset(1, soff)
    b.add_field_offset(2, voff)
    b.add_field_offset(3, inner)
    var outer = b.end_table()
    var buf = b.finish(outer)
    var r = FlatBuffersReader(buf)
    var tp = r.root()
    assert_eq_i32(r.read_i32(tp, 0), Int32(99), "i32")
    var s = r.read_string(tp, 1)
    assert_true(s == "composite", "string: " + s)
    var vec_pos = r.read_vector(tp, 2)
    assert_eq_u32(r.vector_len(vec_pos), UInt32(3), "vec len")
    assert_eq_u32(r.vec_u32(vec_pos, UInt32(0)), UInt32(1), "vec[0]")
    assert_eq_u32(r.vec_u32(vec_pos, UInt32(1)), UInt32(2), "vec[1]")
    assert_eq_u32(r.vec_u32(vec_pos, UInt32(2)), UInt32(3), "vec[2]")
    var inner_tp = r.read_table(tp, 3)
    assert_eq_i32(r.read_i32(inner_tp, 0), Int32(42), "nested i32")


# ============================================================================
# Test runner
# ============================================================================


fn run_test(
    name: String,
    mut passed: Int,
    mut failed: Int,
    test_fn: fn () raises -> None,
):
    try:
        test_fn()
        passed += 1
        print("  PASS:", name)
    except e:
        failed += 1
        print("  FAIL:", name, "--", String(e))


fn main() raises:
    print("=== flatbuffers tests ===")
    var passed = 0
    var failed = 0

    run_test("test_write_read_u8_roundtrip", passed, failed, test_write_read_u8_roundtrip)
    run_test("test_write_read_u16_le_byte_order", passed, failed, test_write_read_u16_le_byte_order)
    run_test("test_write_read_u32_le_roundtrip", passed, failed, test_write_read_u32_le_roundtrip)
    run_test("test_write_read_i32_le_negative", passed, failed, test_write_read_i32_le_negative)
    run_test("test_write_read_u64_le_roundtrip", passed, failed, test_write_read_u64_le_roundtrip)
    run_test("test_write_read_f32_le_roundtrip", passed, failed, test_write_read_f32_le_roundtrip)
    run_test("test_write_read_f64_le_roundtrip", passed, failed, test_write_read_f64_le_roundtrip)
    run_test("test_padding_to_already_aligned", passed, failed, test_padding_to_already_aligned)
    run_test("test_padding_to_needs_padding", passed, failed, test_padding_to_needs_padding)
    run_test("test_read_out_of_bounds_raises", passed, failed, test_read_out_of_bounds_raises)

    # Phase 2
    run_test("test_builder_initial_state", passed, failed, test_builder_initial_state)
    run_test("test_prepend_u8_single", passed, failed, test_prepend_u8_single)
    run_test("test_prepend_u32_alignment", passed, failed, test_prepend_u32_alignment)
    run_test("test_prepend_scalars_layout", passed, failed, test_prepend_scalars_layout)
    run_test("test_builder_grow_on_overflow", passed, failed, test_builder_grow_on_overflow)
    run_test("test_create_string_hello", passed, failed, test_create_string_hello)
    run_test("test_create_string_empty", passed, failed, test_create_string_empty)
    run_test("test_create_string_unicode", passed, failed, test_create_string_unicode)

    # Phase 3
    run_test("test_create_vector_u8_empty", passed, failed, test_create_vector_u8_empty)
    run_test("test_create_vector_u8_values", passed, failed, test_create_vector_u8_values)
    run_test("test_create_vector_u32_alignment", passed, failed, test_create_vector_u32_alignment)
    run_test("test_start_end_table_empty", passed, failed, test_start_end_table_empty)
    run_test("test_table_one_i32_field", passed, failed, test_table_one_i32_field)
    run_test("test_table_field_absent", passed, failed, test_table_field_absent)
    run_test("test_vtable_deduplication", passed, failed, test_vtable_deduplication)
    run_test("test_finish_root_offset", passed, failed, test_finish_root_offset)
    run_test("test_table_with_string_field", passed, failed, test_table_with_string_field)
    run_test("test_nested_table", passed, failed, test_nested_table)

    # Phase 4
    run_test("test_reader_root_offset", passed, failed, test_reader_root_offset)
    run_test("test_reader_vtable_resolution", passed, failed, test_reader_vtable_resolution)
    run_test("test_reader_scalar_i32", passed, failed, test_reader_scalar_i32)
    run_test("test_reader_scalar_f64", passed, failed, test_reader_scalar_f64)
    run_test("test_reader_scalar_bool_true", passed, failed, test_reader_scalar_bool_true)
    run_test("test_reader_scalar_bool_false", passed, failed, test_reader_scalar_bool_false)
    run_test("test_reader_absent_field_returns_default", passed, failed, test_reader_absent_field_returns_default)
    run_test("test_reader_string_field", passed, failed, test_reader_string_field)
    run_test("test_reader_string_unicode", passed, failed, test_reader_string_unicode)
    run_test("test_reader_multi_field_table", passed, failed, test_reader_multi_field_table)

    # Phase 5
    run_test("test_reader_vector_u8", passed, failed, test_reader_vector_u8)
    run_test("test_reader_vector_u32", passed, failed, test_reader_vector_u32)
    run_test("test_reader_vector_length_zero", passed, failed, test_reader_vector_length_zero)
    run_test("test_reader_vector_of_strings", passed, failed, test_reader_vector_of_strings)
    run_test("test_reader_nested_table", passed, failed, test_reader_nested_table)
    run_test("test_reader_deeply_nested", passed, failed, test_reader_deeply_nested)
    run_test("test_reader_vector_of_tables", passed, failed, test_reader_vector_of_tables)
    run_test("test_reader_union_present", passed, failed, test_reader_union_present)
    run_test("test_reader_union_type_zero", passed, failed, test_reader_union_type_zero)
    run_test("test_reader_vector_bounds_check", passed, failed, test_reader_vector_bounds_check)

    # Phase 6
    run_test("test_missing_field_default_i32", passed, failed, test_missing_field_default_i32)
    run_test("test_missing_field_default_f64", passed, failed, test_missing_field_default_f64)
    run_test("test_missing_string_raises", passed, failed, test_missing_string_raises)
    run_test("test_missing_offset_raises", passed, failed, test_missing_offset_raises)
    run_test("test_buffer_growth_boundary", passed, failed, test_buffer_growth_boundary)
    run_test("test_buffer_growth_50_strings", passed, failed, test_buffer_growth_50_strings)
    run_test("test_empty_string_roundtrip", passed, failed, test_empty_string_roundtrip)
    run_test("test_empty_vector_u32", passed, failed, test_empty_vector_u32)
    run_test("test_vtable_dedup_10_identical", passed, failed, test_vtable_dedup_10_identical)
    run_test("test_full_composite_roundtrip", passed, failed, test_full_composite_roundtrip)

    print("\n" + String(passed) + "/" + String(passed + failed) + " passed")
    if failed > 0:
        raise Error(String(failed) + " test(s) failed")
