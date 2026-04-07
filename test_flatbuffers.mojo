from flatbuffers import (
    write_u8, write_u16_le, write_u32_le, write_i32_le,
    write_i64_le, write_u64_le, write_f32_le, write_f64_le,
    read_u8, read_u16_le, read_u32_le, read_i32_le,
    read_i64_le, read_u64_le, read_f32_le, read_f64_le,
    padding_to,
    FlatBufferBuilder,
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

    print("\n" + String(passed) + "/" + String(passed + failed) + " passed")
    if failed > 0:
        raise Error(String(failed) + " test(s) failed")
