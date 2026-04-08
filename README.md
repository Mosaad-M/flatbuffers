# flatbuffers

Pure-Mojo FlatBuffers binary format encoder/decoder. No external dependencies.

[![Tests](https://github.com/Mosaad-M/flatbuffers/actions/workflows/test.yml/badge.svg)](https://github.com/Mosaad-M/flatbuffers/actions/workflows/test.yml)

## Overview

[FlatBuffers](https://flatbuffers.dev) is a high-performance binary serialization format. This library implements the FlatBuffers wire format in pure Mojo with no external dependencies.

The API is **schema-agnostic**: fields are addressed by slot index rather than field name. This makes it a natural building block for Apache Arrow IPC, which encodes schema metadata in FlatBuffers.

## Installation

```bash
pixi add flatbuffers  # via mojo-pkg-index
```

Or copy `flatbuffers.mojo` directly into your project.

## Usage

### Writing

```mojo
from flatbuffers import FlatBufferBuilder

var b = FlatBufferBuilder()

# Create strings and vectors before the table that references them
var name = b.create_string("Mojo")
var scores = List[UInt32]()
scores.append(UInt32(95))
scores.append(UInt32(87))
var vec = b.create_vector_u32(scores)

# Build the table
b.start_table()
b.add_field_i32(0, Int32(42))        # slot 0: id
b.add_field_offset(1, name)           # slot 1: name
b.add_field_offset(2, vec)            # slot 2: scores
var root = b.end_table()

var buf = b.finish(root)              # List[UInt8] — the finished buffer
```

### Reading

```mojo
from flatbuffers import FlatBuffersReader

var r = FlatBuffersReader(buf)
var tp = r.root()                     # absolute position of root table

var id    = r.read_i32(tp, 0)        # 42
var name  = r.read_string(tp, 1)     # "Mojo"
var vpos  = r.read_vector(tp, 2)     # vector position
var n     = r.vector_len(vpos)       # 2
var s0    = r.vec_u32(vpos, 0)       # 95
var s1    = r.vec_u32(vpos, 1)       # 87
```

### Nested tables

```mojo
# Build inner table first
b.start_table()
b.add_field_i32(0, Int32(99))
var inner = b.end_table()

# Reference it from outer table
b.start_table()
b.add_field_offset(0, inner)
var outer = b.end_table()
var buf = b.finish(outer)

# Read
var r = FlatBuffersReader(buf)
var outer_tp = r.root()
var inner_tp = r.read_table(outer_tp, 0)
var val = r.read_i32(inner_tp, 0)   # 99
```

### Unions

```mojo
# Write: type at slot N, value at slot N+1
b.start_table()
b.add_field_u8(2, UInt8(2))          # union type discriminant
b.add_field_offset(3, inner_table)   # union value
var toff = b.end_table()

# Read
var tp = r.root()
var utype = r.union_type(tp, 2)      # 2
var utbl  = r.union_table(tp, 3)     # absolute position of union table
```

## API Reference

### FlatBufferBuilder

| Method | Description |
|--------|-------------|
| `FlatBufferBuilder(initial_capacity=256)` | Create builder |
| `create_string(s)` | Prepend UTF-8 string, return UOffset |
| `create_vector_u8/u32/i32(data)` | Prepend typed vector, return UOffset |
| `create_vector_offsets(offsets)` | Prepend vector of UOffsets |
| `start_table()` | Begin table building |
| `add_field_i8/u8/i16/u16/i32/u32/i64/f32/f64/bool(slot, val)` | Add scalar field |
| `add_field_offset(slot, val)` | Add offset field (string, vector, nested table) |
| `end_table()` | Finish table, return UOffset |
| `finish(root)` | Prepend root UOffset, return `List[UInt8]` |

### FlatBuffersReader

| Method | Description |
|--------|-------------|
| `FlatBuffersReader(buf)` | Create reader (copies buf) |
| `root()` | Absolute position of root table |
| `read_i8/u8/i16/u16/i32/u32/i64/f32/f64/bool(tp, slot, default=...)` | Read scalar (default if absent) |
| `read_string(tp, slot)` | Read UTF-8 string (raises if absent) |
| `read_offset(tp, slot)` | Follow UOffset, return absolute position (raises if absent) |
| `read_table(tp, slot)` | Alias for `read_offset` |
| `read_vector(tp, slot)` | Return absolute position of vector length field |
| `vector_len(vec_pos)` | Element count |
| `vec_u8/u32/i32/f32/f64(vec_pos, i)` | Typed element access (bounds-checked) |
| `vec_offset(vec_pos, i)` | Follow UOffset element (bounds-checked) |
| `vec_string(vec_pos, i)` | Read string element |
| `union_type(tp, type_slot)` | Read union type discriminant (0 = absent) |
| `union_table(tp, value_slot)` | Follow union value UOffset (raises if absent) |

## Format Notes

- All values little-endian
- `UOffset = UInt32` — forward offset relative to storage position
- `SOffset = Int32` — table→vtable pointer (always negative; vtable precedes table)
- `VOffset = UInt16` — field offset within vtable (0 = field absent)
- Builder writes back-to-front; `finish()` returns `buf[head:]`
- Identical vtable schemas are deduplicated automatically

## Running tests

```bash
pixi run test-flatbuffers   # 58/58 pass
```

## License

MIT
