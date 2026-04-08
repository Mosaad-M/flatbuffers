from flatbuffers import FlatBufferBuilder, FlatBuffersReader
from std.time import perf_counter_ns


# ---------------------------------------------------------------------------
# Benchmark helpers
# ---------------------------------------------------------------------------


fn bench(name: String, iters: Int, ns: UInt):
    var per_op = ns // UInt(iters)
    print(name + ": " + String(per_op) + " ns/op  (" + String(iters) + " iters, " + String(ns) + " ns total)")


# ---------------------------------------------------------------------------
# Benchmarks
# ---------------------------------------------------------------------------


fn bench_build_scalar_table() raises:
    """Build a 3-field table: i32 + f64 + u32 (no heap allocations)."""
    var ITERS = 100_000
    var t0 = perf_counter_ns()
    for _ in range(ITERS):
        var b = FlatBufferBuilder(128)
        b.start_table()
        b.add_field_i32(0, Int32(42))
        b.add_field_f64(1, Float64(3.14))
        b.add_field_u32(2, UInt32(99))
        var root = b.end_table()
        _ = b.finish(root)
    var t1 = perf_counter_ns()
    bench("build_scalar_table", ITERS, t1 - t0)


fn bench_build_string_table() raises:
    """Build a table with one string field."""
    var ITERS = 100_000
    var t0 = perf_counter_ns()
    for _ in range(ITERS):
        var b = FlatBufferBuilder(128)
        var soff = b.create_string("hello flatbuffers")
        b.start_table()
        b.add_field_offset(0, soff)
        var root = b.end_table()
        _ = b.finish(root)
    var t1 = perf_counter_ns()
    bench("build_string_table", ITERS, t1 - t0)


fn bench_build_vector_u32() raises:
    """Build a table with a vector of 16 u32 values."""
    var ITERS = 50_000
    var data = List[UInt32]()
    for i in range(16):
        data.append(UInt32(i))
    var t0 = perf_counter_ns()
    for _ in range(ITERS):
        var b = FlatBufferBuilder(256)
        var voff = b.create_vector_u32(data)
        b.start_table()
        b.add_field_offset(0, voff)
        var root = b.end_table()
        _ = b.finish(root)
    var t1 = perf_counter_ns()
    bench("build_vector_u32[16]", ITERS, t1 - t0)


fn bench_build_nested_tables() raises:
    """Build 3-level nested tables."""
    var ITERS = 50_000
    var t0 = perf_counter_ns()
    for _ in range(ITERS):
        var b = FlatBufferBuilder(256)
        b.start_table()
        b.add_field_i32(0, Int32(1))
        var inner = b.end_table()
        b.start_table()
        b.add_field_offset(0, inner)
        b.add_field_i32(1, Int32(2))
        var mid = b.end_table()
        b.start_table()
        b.add_field_offset(0, mid)
        b.add_field_i32(1, Int32(3))
        var root = b.end_table()
        _ = b.finish(root)
    var t1 = perf_counter_ns()
    bench("build_nested_3level", ITERS, t1 - t0)


fn bench_read_scalar_table() raises:
    """Read 3 scalar fields from a pre-built buffer."""
    var ITERS = 200_000
    var b = FlatBufferBuilder(128)
    b.start_table()
    b.add_field_i32(0, Int32(42))
    b.add_field_f64(1, Float64(3.14))
    b.add_field_u32(2, UInt32(99))
    var root = b.end_table()
    var buf = b.finish(root)
    var t0 = perf_counter_ns()
    for _ in range(ITERS):
        var r = FlatBuffersReader(buf)
        var tp = r.root()
        _ = r.read_i32(tp, 0)
        _ = r.read_f64(tp, 1)
        _ = r.read_u32(tp, 2)
    var t1 = perf_counter_ns()
    bench("read_scalar_table[3 fields]", ITERS, t1 - t0)


fn bench_read_string_field() raises:
    """Read a single string field."""
    var ITERS = 100_000
    var b = FlatBufferBuilder(128)
    var soff = b.create_string("hello flatbuffers")
    b.start_table()
    b.add_field_offset(0, soff)
    var root = b.end_table()
    var buf = b.finish(root)
    var t0 = perf_counter_ns()
    for _ in range(ITERS):
        var r = FlatBuffersReader(buf)
        var tp = r.root()
        _ = r.read_string(tp, 0)
    var t1 = perf_counter_ns()
    bench("read_string_field", ITERS, t1 - t0)


fn bench_read_vector_u32() raises:
    """Read all 16 elements of a u32 vector."""
    var ITERS = 100_000
    var data = List[UInt32]()
    for i in range(16):
        data.append(UInt32(i))
    var b = FlatBufferBuilder(256)
    var voff = b.create_vector_u32(data)
    b.start_table()
    b.add_field_offset(0, voff)
    var root = b.end_table()
    var buf = b.finish(root)
    var t0 = perf_counter_ns()
    for _ in range(ITERS):
        var r = FlatBuffersReader(buf)
        var tp = r.root()
        var vp = r.read_vector(tp, 0)
        var n = r.vector_len(vp)
        for i in range(Int(n)):
            _ = r.vec_u32(vp, UInt32(i))
    var t1 = perf_counter_ns()
    bench("read_vector_u32[16]", ITERS, t1 - t0)


fn bench_vtable_dedup() raises:
    """Build 100 tables with the same 2-field schema — all deduplicate."""
    var ITERS = 1_000
    var t0 = perf_counter_ns()
    for _ in range(ITERS):
        var b = FlatBufferBuilder(4096)
        var offsets = List[UInt32]()
        for j in range(100):
            b.start_table()
            b.add_field_i32(0, Int32(j))
            b.add_field_i32(1, Int32(j * 2))
            offsets.append(b.end_table())
        var voff = b.create_vector_offsets(offsets)
        b.start_table()
        b.add_field_offset(0, voff)
        var root = b.end_table()
        _ = b.finish(root)
    var t1 = perf_counter_ns()
    bench("build_100_dedup_tables", ITERS, t1 - t0)


fn main() raises:
    print("=== flatbuffers benchmarks ===\n")
    bench_build_scalar_table()
    bench_build_string_table()
    bench_build_vector_u32()
    bench_build_nested_tables()
    bench_read_scalar_table()
    bench_read_string_field()
    bench_read_vector_u32()
    bench_vtable_dedup()
    print("\nDone.")
