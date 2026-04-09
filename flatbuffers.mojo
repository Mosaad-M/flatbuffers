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

    fn _grow(mut self) raises:
        var old_size = len(self._buf)
        # Guard: doubling a buffer over half of Int max would overflow.
        # In practice this is ~4.6 EB; treat as a programming error.
        if old_size > 0x3FFF_FFFF_FFFF_FFFF:
            raise Error("flatbuffers: builder buffer too large to grow")
        var new_size = old_size * 2
        var written  = old_size - self._head
        # Single forward-append pass: prefix zeros then copy of written bytes.
        # Forward sequential writes have better cache behaviour than the old
        # approach of zero-filling new_size bytes then writing backwards
        # into the middle via random-access subscript.
        var new_buf  = List[UInt8](capacity=new_size)
        var new_head = new_size - written
        for _ in range(new_head):
            new_buf.append(UInt8(0))
        for i in range(written):
            new_buf.append(self._buf[self._head + i])
        self._buf  = new_buf^
        self._head = new_head

    # ------------------------------------------------------------------
    # Internal: ensure headroom and add alignment padding
    # _prep(align, needed): add pad so (written+needed) % align == 0;
    # padding bytes go at lowest addresses (before the object in forward view).
    # ------------------------------------------------------------------

    fn _prep(mut self, align: Int, needed: Int = 0) raises:
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

    fn prepend_u8(mut self, val: UInt8) raises:
        self._prep(1, 1)
        self._head -= 1
        self._buf[self._head] = val

    fn prepend_bool(mut self, val: Bool) raises:
        self.prepend_u8(UInt8(1) if val else UInt8(0))

    fn prepend_u16(mut self, val: UInt16) raises:
        self._prep(2, 2)
        self._head -= 2
        write_u16_le(self._buf, self._head, val)

    fn prepend_i16(mut self, val: Int16) raises:
        self._prep(2, 2)
        self._head -= 2
        var v = Int32(val)
        self._buf[self._head]     = UInt8(Int32(v & Int32(0xFF)))
        self._buf[self._head + 1] = UInt8(Int32((v >> 8) & Int32(0xFF)))

    fn prepend_u32(mut self, val: UInt32) raises:
        self._prep(4, 4)
        self._head -= 4
        write_u32_le(self._buf, self._head, val)

    fn prepend_i32(mut self, val: Int32) raises:
        self._prep(4, 4)
        self._head -= 4
        write_i32_le(self._buf, self._head, val)

    fn prepend_u64(mut self, val: UInt64) raises:
        self._prep(8, 8)
        self._head -= 8
        write_u64_le(self._buf, self._head, val)

    fn prepend_i64(mut self, val: Int64) raises:
        self._prep(8, 8)
        self._head -= 8
        write_i64_le(self._buf, self._head, val)

    fn prepend_f32(mut self, val: Float32) raises:
        self._prep(4, 4)
        self._head -= 4
        write_f32_le(self._buf, self._head, val)

    fn prepend_f64(mut self, val: Float64) raises:
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

    fn create_vector_u8(mut self, data: List[UInt8]) raises -> UInt32:
        var n = len(data)
        self._prep(4, n)
        for i in range(n - 1, -1, -1):
            self._head -= 1
            self._buf[self._head] = data[i]
        self._head -= 4
        write_u32_le(self._buf, self._head, UInt32(n))
        return self.offset()

    fn create_vector_u32(mut self, data: List[UInt32]) raises -> UInt32:
        var n = len(data)
        self._prep(4, n * 4)
        for i in range(n - 1, -1, -1):
            self._head -= 4
            write_u32_le(self._buf, self._head, data[i])
        self._head -= 4
        write_u32_le(self._buf, self._head, UInt32(n))
        return self.offset()

    fn create_vector_i32(mut self, data: List[Int32]) raises -> UInt32:
        var n = len(data)
        self._prep(4, n * 4)
        for i in range(n - 1, -1, -1):
            self._head -= 4
            write_i32_le(self._buf, self._head, data[i])
        self._head -= 4
        write_u32_le(self._buf, self._head, UInt32(n))
        return self.offset()

    fn create_vector_offsets(mut self, offsets: List[UInt32]) raises -> UInt32:
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

    fn create_vector_structs(
        mut self,
        data: List[UInt8],
        count: Int,
        struct_size: Int,
        struct_align: Int,
    ) raises -> UInt32:
        """Create a vector of inline FlatBuffers structs.

        data       — count * struct_size bytes, structs laid out in forward order.
        count      — number of struct elements.
        struct_size — byte size of each struct element.
        struct_align — alignment of each struct element (typically 8 for Arrow structs).

        Returns a UOffset suitable for add_field_offset.
        Elements are read back with vec_struct_bytes(vec_pos, i, struct_size).
        """
        if count < 0:
            raise Error("flatbuffers: create_vector_structs: negative count")
        if len(data) != count * struct_size:
            raise Error(
                "flatbuffers: create_vector_structs: data length "
                + String(len(data))
                + " != count("
                + String(count)
                + ") * struct_size("
                + String(struct_size)
                + ")"
            )
        var n_bytes = count * struct_size
        # Align so that struct data has struct_align alignment from the tail.
        self._prep(struct_align, n_bytes)
        # Write struct bytes in reverse (prepend model → forward order in result).
        for i in range(n_bytes - 1, -1, -1):
            self._head -= 1
            self._buf[self._head] = data[i]
        # Write count (u32, 4 bytes) — immediately before struct data.
        self._head -= 4
        write_u32_le(self._buf, self._head, UInt32(count))
        return self.offset()

    # ------------------------------------------------------------------
    # Table building
    # ------------------------------------------------------------------

    fn start_table(mut self) raises:
        if self._in_table:
            raise Error("flatbuffers: start_table called while already building a table")
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

    fn _add_field(mut self, slot: Int) raises:
        if not self._in_table:
            raise Error("flatbuffers: add_field called outside start_table/end_table")
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


# ============================================================================
# FlatBuffersReader
#
# Reads a finished FlatBuffers buffer.  All table positions (`tp`) are
# absolute byte offsets in the buffer (not tail-distances).
#
# The root UOffset stored at bytes [0..3] is an absolute table position.
# ============================================================================


struct FlatBuffersReader(Movable):
    var _buf: List[UInt8]

    fn __init__(out self, buf: List[UInt8]):
        self._buf = buf.copy()

    fn __moveinit__(out self, deinit take: Self):
        self._buf = take._buf^

    # ------------------------------------------------------------------
    # Root: position 0 holds the root UOffset (absolute table position)
    # ------------------------------------------------------------------

    fn root(self) raises -> UInt32:
        return read_u32_le(self._buf, 0)

    # ------------------------------------------------------------------
    # Internal: vtable position for a given table
    # soffset at tp is negative; vtable_pos = tp + soffset < tp
    # ------------------------------------------------------------------

    fn _vtable_pos(self, table_pos: UInt32) raises -> Int:
        var soffset = read_i32_le(self._buf, Int(table_pos))
        var vt_pos = Int(table_pos) + Int(soffset)
        if vt_pos < 0 or vt_pos >= len(self._buf):
            raise Error("flatbuffers: vtable position out of bounds: " + String(vt_pos))
        return vt_pos

    # ------------------------------------------------------------------
    # Internal: VOffset for `slot` in the table at `table_pos`
    # Returns 0 if slot is absent (vtable too small or slot not set)
    # ------------------------------------------------------------------

    fn _field_voffset(self, table_pos: UInt32, slot: Int) raises -> UInt16:
        var vt = self._vtable_pos(table_pos)
        var vt_size = Int(read_u16_le(self._buf, vt))
        var slot_byte = 4 + slot * 2
        # Check 1: slot is within the vtable's declared size.
        if slot_byte + 1 >= vt_size:
            return UInt16(0)
        # Check 2 (defense-in-depth): vtable slot bytes must be within the buffer.
        # A malicious vt_size could pass check 1 while vt+slot_byte is past len(_buf).
        if vt + slot_byte + 1 >= len(self._buf):
            return UInt16(0)
        return read_u16_le(self._buf, vt + slot_byte)

    # ------------------------------------------------------------------
    # Scalar readers — return default when field absent
    # ------------------------------------------------------------------

    fn read_i8(self, tp: UInt32, slot: Int, default: Int8 = 0) raises -> Int8:
        var voff = self._field_voffset(tp, slot)
        if voff == 0:
            return default
        var u = read_u8(self._buf, Int(tp) + Int(voff))
        var tmp = alloc[UInt8](1)
        tmp[] = u
        var result = tmp.bitcast[Int8]()[]
        tmp.free()
        return result

    fn read_u8(self, tp: UInt32, slot: Int, default: UInt8 = 0) raises -> UInt8:
        var voff = self._field_voffset(tp, slot)
        if voff == 0:
            return default
        return read_u8(self._buf, Int(tp) + Int(voff))

    fn read_i16(self, tp: UInt32, slot: Int, default: Int16 = 0) raises -> Int16:
        var voff = self._field_voffset(tp, slot)
        if voff == 0:
            return default
        var u = read_u16_le(self._buf, Int(tp) + Int(voff))
        var tmp = alloc[UInt16](1)
        tmp[] = u
        var result = tmp.bitcast[Int16]()[]
        tmp.free()
        return result

    fn read_u16(self, tp: UInt32, slot: Int, default: UInt16 = 0) raises -> UInt16:
        var voff = self._field_voffset(tp, slot)
        if voff == 0:
            return default
        return read_u16_le(self._buf, Int(tp) + Int(voff))

    fn read_i32(self, tp: UInt32, slot: Int, default: Int32 = 0) raises -> Int32:
        var voff = self._field_voffset(tp, slot)
        if voff == 0:
            return default
        return read_i32_le(self._buf, Int(tp) + Int(voff))

    fn read_u32(self, tp: UInt32, slot: Int, default: UInt32 = 0) raises -> UInt32:
        var voff = self._field_voffset(tp, slot)
        if voff == 0:
            return default
        return read_u32_le(self._buf, Int(tp) + Int(voff))

    fn read_i64(self, tp: UInt32, slot: Int, default: Int64 = 0) raises -> Int64:
        var voff = self._field_voffset(tp, slot)
        if voff == 0:
            return default
        return read_i64_le(self._buf, Int(tp) + Int(voff))

    fn read_f32(self, tp: UInt32, slot: Int, default: Float32 = 0.0) raises -> Float32:
        var voff = self._field_voffset(tp, slot)
        if voff == 0:
            return default
        return read_f32_le(self._buf, Int(tp) + Int(voff))

    fn read_f64(self, tp: UInt32, slot: Int, default: Float64 = 0.0) raises -> Float64:
        var voff = self._field_voffset(tp, slot)
        if voff == 0:
            return default
        return read_f64_le(self._buf, Int(tp) + Int(voff))

    fn read_bool(self, tp: UInt32, slot: Int, default: Bool = False) raises -> Bool:
        var voff = self._field_voffset(tp, slot)
        if voff == 0:
            return default
        return read_u8(self._buf, Int(tp) + Int(voff)) != UInt8(0)

    # ------------------------------------------------------------------
    # String reader — raises if field absent
    # Layout at str_pos: [length:u32][utf8 bytes][null byte]
    # ------------------------------------------------------------------

    fn read_string(self, tp: UInt32, slot: Int) raises -> String:
        var voff = self._field_voffset(tp, slot)
        if voff == 0:
            raise Error("flatbuffers: absent string field at slot " + String(slot))
        var ref_pos = Int(tp) + Int(voff)
        var str_pos = ref_pos + Int(read_u32_le(self._buf, ref_pos))
        var length = Int(read_u32_le(self._buf, str_pos))
        if str_pos + 4 + length > len(self._buf):
            raise Error("flatbuffers: string extends beyond buffer")
        var bytes = List[UInt8](capacity=length)
        for i in range(length):
            bytes.append(self._buf[str_pos + 4 + i])
        return String(unsafe_from_utf8=bytes^)

    # ------------------------------------------------------------------
    # Offset reader — raises if field absent; returns absolute position
    # of the referenced object (follows the UOffset stored in the field)
    # ------------------------------------------------------------------

    fn read_offset(self, tp: UInt32, slot: Int) raises -> UInt32:
        var voff = self._field_voffset(tp, slot)
        if voff == 0:
            raise Error("flatbuffers: absent offset field at slot " + String(slot))
        var ref_pos = Int(tp) + Int(voff)
        return UInt32(ref_pos) + read_u32_le(self._buf, ref_pos)

    # ------------------------------------------------------------------
    # Phase 5: Vector accessors
    # vec_pos = absolute position of the vector's length field (u32)
    # Elements follow immediately: vec_pos+4, vec_pos+4+elem_size, ...
    # ------------------------------------------------------------------

    fn read_vector(self, tp: UInt32, slot: Int) raises -> UInt32:
        """Return absolute position of the vector's length field."""
        return self.read_offset(tp, slot)

    fn vector_len(self, vec_pos: UInt32) raises -> UInt32:
        return read_u32_le(self._buf, Int(vec_pos))

    fn vec_u8(self, vec_pos: UInt32, i: UInt32) raises -> UInt8:
        var vlen = self.vector_len(vec_pos)
        if i >= vlen:
            raise Error("flatbuffers: vec index " + String(i) + " >= len " + String(vlen))
        return read_u8(self._buf, Int(vec_pos) + 4 + Int(i))

    fn vec_u32(self, vec_pos: UInt32, i: UInt32) raises -> UInt32:
        var vlen = self.vector_len(vec_pos)
        if i >= vlen:
            raise Error("flatbuffers: vec index " + String(i) + " >= len " + String(vlen))
        return read_u32_le(self._buf, Int(vec_pos) + 4 + Int(i) * 4)

    fn vec_i32(self, vec_pos: UInt32, i: UInt32) raises -> Int32:
        var vlen = self.vector_len(vec_pos)
        if i >= vlen:
            raise Error("flatbuffers: vec index " + String(i) + " >= len " + String(vlen))
        return read_i32_le(self._buf, Int(vec_pos) + 4 + Int(i) * 4)

    fn vec_f32(self, vec_pos: UInt32, i: UInt32) raises -> Float32:
        var vlen = self.vector_len(vec_pos)
        if i >= vlen:
            raise Error("flatbuffers: vec index " + String(i) + " >= len " + String(vlen))
        return read_f32_le(self._buf, Int(vec_pos) + 4 + Int(i) * 4)

    fn vec_f64(self, vec_pos: UInt32, i: UInt32) raises -> Float64:
        var vlen = self.vector_len(vec_pos)
        if i >= vlen:
            raise Error("flatbuffers: vec index " + String(i) + " >= len " + String(vlen))
        return read_f64_le(self._buf, Int(vec_pos) + 4 + Int(i) * 8)

    fn vec_offset(self, vec_pos: UInt32, i: UInt32) raises -> UInt32:
        """Follow the UOffset at element i of an offset vector."""
        var vlen = self.vector_len(vec_pos)
        if i >= vlen:
            raise Error("flatbuffers: vec index " + String(i) + " >= len " + String(vlen))
        var elem_pos = Int(vec_pos) + 4 + Int(i) * 4
        return UInt32(elem_pos) + read_u32_le(self._buf, elem_pos)

    fn vec_struct_bytes(
        self, vec_pos: UInt32, i: UInt32, struct_size: Int
    ) raises -> List[UInt8]:
        """Return struct_size bytes for element i of a struct vector.

        vec_pos    — absolute position of the vector's length field (from read_vector).
        i          — zero-based element index.
        struct_size — byte size of each struct element.
        """
        var vlen = self.vector_len(vec_pos)
        if i >= vlen:
            raise Error(
                "flatbuffers: vec_struct_bytes index "
                + String(i)
                + " >= len "
                + String(vlen)
            )
        var start = Int(vec_pos) + 4 + Int(i) * struct_size
        var end = start + struct_size
        if end > len(self._buf):
            raise Error("flatbuffers: vec_struct_bytes extends beyond buffer")
        var result = List[UInt8](capacity=struct_size)
        for j in range(struct_size):
            result.append(self._buf[start + j])
        return result^

    fn read_string_at(self, str_pos: UInt32) raises -> String:
        """Read a string directly from its absolute buffer position."""
        var length = Int(read_u32_le(self._buf, Int(str_pos)))
        if Int(str_pos) + 4 + length > len(self._buf):
            raise Error("flatbuffers: string extends beyond buffer")
        var bytes = List[UInt8](capacity=length)
        for i in range(length):
            bytes.append(self._buf[Int(str_pos) + 4 + i])
        return String(unsafe_from_utf8=bytes^)

    fn vec_string(self, vec_pos: UInt32, i: UInt32) raises -> String:
        return self.read_string_at(self.vec_offset(vec_pos, i))

    # Alias: tables are accessed the same way as any offset field
    fn read_table(self, tp: UInt32, slot: Int) raises -> UInt32:
        return self.read_offset(tp, slot)

    # ------------------------------------------------------------------
    # Phase 5: Union accessors
    # Union stores two slots: type (u8) at type_slot, value (UOffset) at value_slot
    # type=0 means NONE; union_table raises when value slot is absent
    # ------------------------------------------------------------------

    fn union_type(self, tp: UInt32, type_slot: Int) raises -> UInt8:
        return self.read_u8(tp, type_slot)

    fn union_table(self, tp: UInt32, value_slot: Int) raises -> UInt32:
        return self.read_offset(tp, value_slot)
