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
# All intermediate arithmetic uses Int to avoid unsigned wrap.
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
# FieldLoc — records where a table field was written during table building
# ============================================================================


struct FieldLoc(Copyable, Movable):
    var slot: Int       # field slot index (0-based)
    var offset: UInt32  # offset() value right after the field was prepended

    fn __init__(out self, slot: Int, offset: UInt32):
        self.slot = slot
        self.offset = offset

    fn __copyinit__(out self, copy: Self):
        self.slot = copy.slot
        self.offset = copy.offset

    fn __moveinit__(out self, deinit take: Self):
        self.slot = take.slot
        self.offset = take.offset


# ============================================================================
# FlatBufferBuilder
#
# Writes data back-to-front (prepend model): _buf[_head:] is the valid content.
# _head starts at len(_buf) and decrements on each write.
# finish(root) prepends the 4-byte root UOffset and returns a copy of _buf[_head:].
# ============================================================================


struct FlatBufferBuilder(Movable):
    var _buf:        List[UInt8]     # backing store; valid data at _buf[_head:]
    var _head:       Int             # write cursor; decrements on each prepend
    var _min_align:  Int             # max alignment seen — used to pad finish()
    # Table-building state
    var _vtables:    List[UInt32]    # UOffsets of previously written vtables (for dedup)
    var _table_start: Int            # _head value saved at start_table()
    var _in_table:   Bool            # True between start_table() / end_table()
    var _field_locs: List[FieldLoc]  # fields added in current table

    fn __init__(out self, initial_capacity: Int = 256):
        self._buf = List[UInt8](capacity=initial_capacity)
        for _ in range(initial_capacity):
            self._buf.append(UInt8(0))
        self._head       = initial_capacity
        self._min_align  = 1
        self._vtables    = List[UInt32]()
        self._table_start = initial_capacity
        self._in_table   = False
        self._field_locs = List[FieldLoc]()

    fn __moveinit__(out self, deinit take: Self):
        self._buf        = take._buf^
        self._head       = take._head
        self._min_align  = take._min_align
        self._vtables    = take._vtables^
        self._table_start = take._table_start
        self._in_table   = take._in_table
        self._field_locs = take._field_locs^

    # ------------------------------------------------------------------
    # Internal: grow buffer by doubling, shift written bytes to end
    # ------------------------------------------------------------------

    fn _grow(mut self):
        var old_size = len(self._buf)
        var new_size = old_size * 2
        var written  = old_size - self._head
        var new_buf  = List[UInt8](capacity=new_size)
        for _ in range(new_size):
            new_buf.append(UInt8(0))
        var new_head = new_size - written
        for i in range(written):
            new_buf[new_head + i] = self._buf[self._head + i]
        self._buf  = new_buf^
        self._head = new_head

    # ------------------------------------------------------------------
    # Internal: ensure headroom and add alignment padding
    # _prep(align, needed): add pad so (written+needed) % align == 0;
    # padding bytes go at lowest addresses (before the object in forward view).
    # ------------------------------------------------------------------

    fn _prep(mut self, align: Int, needed: Int = 0):
        if align > self._min_align:
            self._min_align = align
        while self._head < needed + align:
            self._grow()
        var written = len(self._buf) - self._head
        var pad = padding_to(written + needed, align)
        for _ in range(pad):
            self._head -= 1
            self._buf[self._head] = UInt8(0)

    # ------------------------------------------------------------------
    # Current UOffset: distance from tail (end of buffer)
    # ------------------------------------------------------------------

    fn offset(self) -> UInt32:
        return UInt32(len(self._buf) - self._head)

    # ------------------------------------------------------------------
    # Low-level prepend methods
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
    # Layout in final buffer: [padding][length:u32][bytes][null]
    # ------------------------------------------------------------------

    fn create_string(mut self, s: String) raises -> UInt32:
        var bytes = s.as_bytes()
        var n = len(bytes)
        self._prep(4, n + 1)
        self._head -= 1
        self._buf[self._head] = UInt8(0)
        for i in range(n - 1, -1, -1):
            self._head -= 1
            self._buf[self._head] = bytes[i]
        self._head -= 4
        write_u32_le(self._buf, self._head, UInt32(n))
        return self.offset()

    # ------------------------------------------------------------------
    # Vector creation
    # Layout: [padding][count:u32][elem0][elem1]...
    # Vectors of offsets must prepend in REVERSE order (last element first).
    # ------------------------------------------------------------------

    fn create_vector_u8(mut self, data: List[UInt8]) -> UInt32:
        var n = len(data)
        self._prep(4, n)
        for i in range(n - 1, -1, -1):
            self._head -= 1
            self._buf[self._head] = data[i]
        self._head -= 4
        write_u32_le(self._buf, self._head, UInt32(n))
        return self.offset()

    fn create_vector_u32(mut self, data: List[UInt32]) -> UInt32:
        var n = len(data)
        self._prep(4, n * 4)
        for i in range(n - 1, -1, -1):
            self._head -= 4
            write_u32_le(self._buf, self._head, data[i])
        self._head -= 4
        write_u32_le(self._buf, self._head, UInt32(n))
        return self.offset()

    fn create_vector_i32(mut self, data: List[Int32]) -> UInt32:
        var n = len(data)
        self._prep(4, n * 4)
        for i in range(n - 1, -1, -1):
            self._head -= 4
            write_i32_le(self._buf, self._head, data[i])
        self._head -= 4
        write_u32_le(self._buf, self._head, UInt32(n))
        return self.offset()

    fn create_vector_offsets(mut self, offsets: List[UInt32]) -> UInt32:
        # UOffset elements must be written in REVERSE order so that when read
        # forward the first element comes first.
        var n = len(offsets)
        self._prep(4, n * 4)
        for i in range(n - 1, -1, -1):
            # Each UOffset is relative to the position where it is stored.
            # At the time of writing, the element position = offset() + (n-1-i)*4
            # after the prepend. Since we haven't decremented yet, compute
            # the stored relative offset:
            # stored_pos_from_tail = offset() + 4  (after this write)
            # target = offsets[i] (absolute distance from tail)
            # relative = target - stored_pos_from_tail
            # But UOffsets are always positive (point forward). In the prepend
            # model the referenced object is at a HIGHER tail-distance (lower
            # absolute address). We store relative = target (absolute) because
            # position stored = len(buf) - (_head-4), target = len(buf) - T_head.
            # relative offset = T_head - (_head - 4) = target - (offset() + 4)
            # after decrement:
            #   stored_abs = len(buf) - (_head - 4) = offset() + 4
            #   relative = Int(offsets[i]) - Int(self.offset()) - 4
            self._head -= 4
            var stored_abs = len(self._buf) - self._head
            var rel = stored_abs - Int(offsets[i])
            write_u32_le(self._buf, self._head, UInt32(rel))
        self._head -= 4
        write_u32_le(self._buf, self._head, UInt32(n))
        return self.offset()

    # ------------------------------------------------------------------
    # Table building
    # ------------------------------------------------------------------

    fn start_table(mut self):
        # Pre-align to 4 bytes so that field writes inside the table have
        # consistent padding regardless of preceding buffer content.
        # This ensures same-schema tables produce identical vtable obj_size
        # values, making vtable deduplication reliable.
        var written = len(self._buf) - self._head
        var pad = padding_to(written, 4)
        for _ in range(pad):
            self._head -= 1
            self._buf[self._head] = UInt8(0)
        self._table_start = self._head
        self._in_table    = True
        self._field_locs  = List[FieldLoc]()

    fn _add_field(mut self, slot: Int):
        self._field_locs.append(FieldLoc(slot, self.offset()))

    fn add_field_offset(mut self, slot: Int, val: UInt32) raises:
        # UOffset relative encoding: stored_value = target_abs - field_abs
        # In tail-distance terms: stored_value = stored_abs - target_tail_dist
        # where stored_abs = tail-dist of this field, val = tail-dist of target.
        # target_abs = len(buf) - val;  field_abs = len(buf) - stored_abs
        # stored_value = (len-val) - (len-stored_abs) = stored_abs - val  (always >= 0)
        self._prep(4, 4)
        self._head -= 4
        var stored_abs = len(self._buf) - self._head
        var rel = stored_abs - Int(val)
        write_u32_le(self._buf, self._head, UInt32(rel))
        self._add_field(slot)

    fn add_field_i8(mut self, slot: Int, val: Int8) raises:
        self.prepend_u8(UInt8(val))  # bitwise safe for single byte
        self._add_field(slot)

    fn add_field_u8(mut self, slot: Int, val: UInt8) raises:
        self.prepend_u8(val)
        self._add_field(slot)

    fn add_field_i16(mut self, slot: Int, val: Int16) raises:
        self.prepend_i16(val)
        self._add_field(slot)

    fn add_field_u16(mut self, slot: Int, val: UInt16) raises:
        self.prepend_u16(val)
        self._add_field(slot)

    fn add_field_i32(mut self, slot: Int, val: Int32) raises:
        self.prepend_i32(val)
        self._add_field(slot)

    fn add_field_u32(mut self, slot: Int, val: UInt32) raises:
        self.prepend_u32(val)
        self._add_field(slot)

    fn add_field_i64(mut self, slot: Int, val: Int64) raises:
        self.prepend_i64(val)
        self._add_field(slot)

    fn add_field_f32(mut self, slot: Int, val: Float32) raises:
        self.prepend_f32(val)
        self._add_field(slot)

    fn add_field_f64(mut self, slot: Int, val: Float64) raises:
        self.prepend_f64(val)
        self._add_field(slot)

    fn add_field_bool(mut self, slot: Int, val: Bool) raises:
        self.prepend_bool(val)
        self._add_field(slot)

    fn end_table(mut self) raises -> UInt32:
        # 1. Find highest slot index
        var num_slots = 0
        for i in range(len(self._field_locs)):
            if self._field_locs[i].slot + 1 > num_slots:
                num_slots = self._field_locs[i].slot + 1

        # 2. object_size = bytes written for the table body since start_table
        #    (in prepend model: distance from current head to saved table_start)
        var object_size = self._table_start - self._head
        # Ensure object_size is positive (table may be empty)
        if object_size < 0:
            object_size = 0

        # 3. Prepend placeholder for soffset (Int32 = 0, will be patched)
        self._prep(4, 4)
        self._head -= 4
        write_i32_le(self._buf, self._head, Int32(0))
        var table_pos = self.offset()  # UOffset of this table object

        # 4. Build vtable entries (VOffset values = distance from table start)
        # VOffset for slot s: if field present, = table_pos - field.offset; else 0
        var vtable_slots = List[UInt16]()
        for s in range(num_slots):
            var voff = UInt16(0)
            for i in range(len(self._field_locs)):
                if self._field_locs[i].slot == s:
                    # field_offset_from_table_start = table_pos - field.offset
                    # (table_pos >= field.offset because table fields come after soffset)
                    var delta = Int(table_pos) - Int(self._field_locs[i].offset)
                    voff = UInt16(delta)
                    break
            vtable_slots.append(voff)

        # 5. vtable layout: [vtable_byte_size:u16][obj_byte_size:u16][slot0..slotN:u16]
        var vtable_size = UInt16(4 + num_slots * 2)
        var obj_size_u16 = UInt16(object_size + 4)  # +4 for the soffset field

        # 6. Check for duplicate vtable
        var buf_tail = len(self._buf)
        var match_vt_pos = -1
        for vi in range(len(self._vtables)):
            var vt_abs = buf_tail - Int(self._vtables[vi])
            # Compare vtable_size first
            var existing_vt_size = UInt16(self._buf[vt_abs]) | (UInt16(self._buf[vt_abs + 1]) << 8)
            if existing_vt_size != vtable_size:
                continue
            # Compare all entries
            var found = True
            # obj_size
            var existing_obj_size = UInt16(self._buf[vt_abs + 2]) | (UInt16(self._buf[vt_abs + 3]) << 8)
            if existing_obj_size != obj_size_u16:
                found = False
            if found:
                for s in range(num_slots):
                    var existing_slot = (UInt16(self._buf[vt_abs + 4 + s * 2])
                        | (UInt16(self._buf[vt_abs + 4 + s * 2 + 1]) << 8))
                    if existing_slot != vtable_slots[s]:
                        found = False
                        break
            if found:
                match_vt_pos = Int(self._vtables[vi])
                break

        if match_vt_pos >= 0:
            # Reuse existing vtable: patch soffset
            # soffset at table_pos points to vtable: vtable_abs = table_abs + soffset
            # table_abs = buf_tail - table_pos
            # vtable_abs = buf_tail - match_vt_pos
            # soffset = vtable_abs - table_abs = (buf_tail - match_vt_pos) - (buf_tail - table_pos)
            #         = table_pos - match_vt_pos
            var soffset = Int32(Int(table_pos) - match_vt_pos)
            var table_abs = buf_tail - Int(table_pos)
            write_i32_le(self._buf, table_abs, soffset)
        else:
            # Write new vtable (prepend: slots in reverse, then obj_size, then vtable_size)
            for s in range(num_slots - 1, -1, -1):
                self._head -= 2
                write_u16_le(self._buf, self._head, vtable_slots[s])
            self._head -= 2
            write_u16_le(self._buf, self._head, obj_size_u16)
            self._head -= 2
            write_u16_le(self._buf, self._head, vtable_size)
            var new_vt_offset = self.offset()
            self._vtables.append(new_vt_offset)
            # Patch soffset: vtable_abs = buf_tail - new_vt_offset
            # soffset = vtable_abs - table_abs = (buf_tail - new_vt_offset) - (buf_tail - table_pos)
            #         = table_pos - new_vt_offset
            var soffset = Int32(Int(table_pos) - Int(new_vt_offset))
            var table_abs = len(self._buf) - Int(table_pos)
            write_i32_le(self._buf, table_abs, soffset)

        self._in_table = False
        return table_pos

    # ------------------------------------------------------------------
    # finish: prepend root UOffset and return final buffer copy
    # ------------------------------------------------------------------

    fn finish(mut self, root: UInt32) raises -> List[UInt8]:
        # `root` is a tail-distance (UOffset in _buf coordinate space).
        # After prepending the 4-byte root field, the result buffer starts
        # at _head. The table's position within the result buffer is:
        #   table_pos_in_result = (len(_buf) - root) - _head
        # which is the correct UOffset value to store at result[0].
        self._prep(self._min_align, 4)
        self._head -= 4
        var table_pos_in_result = (len(self._buf) - Int(root)) - self._head
        write_u32_le(self._buf, self._head, UInt32(table_pos_in_result))
        var result = List[UInt8](capacity=len(self._buf) - self._head)
        for i in range(self._head, len(self._buf)):
            result.append(self._buf[i])
        return result^
