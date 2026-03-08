/// PoC 07: RenderState Bulk Copy API Benchmark
///
/// Proves that:
/// 1. A separate Zig module can import ghostty-vt and use the bulk export API
/// 2. The bulk copy produces correct FlatCell data
/// 3. Performance is measured for various terminal sizes
///
/// This validates the server-side RenderState extraction performance
/// for the it-shell3 protocol.
const std = @import("std");
const vt = @import("ghostty-vt");

const Terminal = vt.Terminal;
const RenderState = vt.RenderState;
const FlatCell = vt.render_export.FlatCell;
const ExportResult = vt.render_export.ExportResult;
const bulkExport = vt.render_export.bulkExport;
const freeExport = vt.render_export.freeExport;

const print = std.debug.print;

/// Terminal sizes to benchmark.
const BenchSize = struct {
    cols: vt.size.CellCountInt,
    rows: vt.size.CellCountInt,
    label: []const u8,
};

const bench_sizes = [_]BenchSize{
    .{ .cols = 80, .rows = 24, .label = "80x24 (standard)" },
    .{ .cols = 120, .rows = 40, .label = "120x40 (large)" },
    .{ .cols = 200, .rows = 50, .label = "200x50 (wide)" },
    .{ .cols = 300, .rows = 80, .label = "300x80 (ultra)" },
};

const WARMUP_ITERS = 100;
const BENCH_ITERS = 1000;

pub fn main() !void {
    var gpa_state: std.heap.GeneralPurposeAllocator(.{}) = .init;
    defer _ = gpa_state.deinit();
    const alloc = gpa_state.allocator();

    print("=== PoC 07: RenderState Bulk Copy API Benchmark ===\n\n", .{});

    // Phase 1: Correctness verification
    print("--- Phase 1: Correctness Verification ---\n\n", .{});
    try verifyCorrectness(alloc);

    // Phase 2: Benchmark
    print("\n--- Phase 2: Performance Benchmark ---\n", .{});
    print("Warmup: {} iterations, Bench: {} iterations\n\n", .{ WARMUP_ITERS, BENCH_ITERS });

    print("{s:<25} {s:>10} {s:>10} {s:>12} {s:>10} {s:>12}\n", .{
        "Size", "Cells", "Bytes", "update us", "flat us", "total us",
    });
    print("{s:-<25} {s:->10} {s:->10} {s:->12} {s:->10} {s:->12}\n", .{
        "", "", "", "", "", "",
    });

    for (bench_sizes) |sz| {
        try benchmarkSize(alloc, sz);
    }

    // Phase 3: Incremental update benchmark
    print("\n--- Phase 3: Incremental Update (single row dirty) ---\n\n", .{});
    try benchmarkIncremental(alloc);

    print("\n=== PoC 07 COMPLETE ===\n", .{});
}

fn verifyCorrectness(alloc: std.mem.Allocator) !void {

    var term = try Terminal.init(alloc, .{ .cols = 80, .rows = 24 });
    defer term.deinit(alloc);

    // Write test content
    const ascii = "Hello, it-shell3!";
    for (ascii) |c| try term.print(c);
    term.carriageReturn();
    try term.linefeed();

    // Korean
    const korean = [_]u21{ 0xD55C, 0xAE00, ' ', 0xD14C, 0xC2A4, 0xD2B8 };
    for (korean) |cp| try term.print(cp);
    term.carriageReturn();
    try term.linefeed();

    // Bold red
    try term.setAttribute(.bold);
    try term.setAttribute(.{ .direct_color_fg = .{ .r = 255, .g = 0, .b = 0 } });
    for ("Red") |c| try term.print(c);
    try term.setAttribute(.unset);

    // Bulk export
    var state: RenderState = .empty;
    defer state.deinit(alloc);

    var result = try bulkExport(alloc, &state, &term);
    defer freeExport(alloc, &result);

    // Verify dimensions
    std.debug.assert(result.rows == 24);
    std.debug.assert(result.cols == 80);
    print("  Dimensions: {}x{} OK\n", .{ result.rows, result.cols });

    // Verify ASCII row
    const row0 = result.cells[0..80];
    std.debug.assert(row0[0].codepoint == 'H');
    std.debug.assert(row0[4].codepoint == 'o');
    std.debug.assert(row0[0].fg.tag == 0); // no style
    print("  Row 0 ASCII: '{c}{c}{c}{c}{c}...' OK\n", .{
        @as(u8, @intCast(row0[0].codepoint)),
        @as(u8, @intCast(row0[1].codepoint)),
        @as(u8, @intCast(row0[2].codepoint)),
        @as(u8, @intCast(row0[3].codepoint)),
        @as(u8, @intCast(row0[4].codepoint)),
    });

    // Verify Korean row (wide characters)
    const row1 = result.cells[80..160];
    std.debug.assert(row1[0].codepoint == 0xD55C); // 한
    std.debug.assert(row1[0].wide == 1); // wide
    std.debug.assert(row1[1].wide == 2); // spacer_tail
    std.debug.assert(row1[2].codepoint == 0xAE00); // 글
    std.debug.assert(row1[2].wide == 1); // wide
    print("  Row 1 Korean: U+{X:0>4} wide={} spacer={} OK\n", .{
        row1[0].codepoint, row1[0].wide, row1[1].wide,
    });

    // Verify styled row
    const row2 = result.cells[160..240];
    std.debug.assert(row2[0].codepoint == 'R');
    std.debug.assert(row2[0].fg.tag == 2); // rgb
    std.debug.assert(row2[0].fg.r == 255);
    std.debug.assert(row2[0].fg.g == 0);
    const flags_val: @TypeOf(row2[0].flags) = row2[0].flags;
    std.debug.assert(flags_val & 1 == 1); // bold bit
    print("  Row 2 Styled: fg=rgb({},{},{}) bold={} OK\n", .{
        row2[0].fg.r, row2[0].fg.g, row2[0].fg.b,
        flags_val & 1 == 1,
    });

    // Verify dirty bitmap
    std.debug.assert(result.dirty_bitmap[0] & 0b111 == 0b111); // rows 0,1,2 dirty
    print("  Dirty bitmap: 0b{b:0>8} (rows 0-2 dirty) OK\n", .{
        @as(u8, @intCast(result.dirty_bitmap[0] & 0xFF)),
    });

    // Verify cursor
    std.debug.assert(result.cursor_y == 2);
    print("  Cursor: ({},{}) OK\n", .{ result.cursor_x, result.cursor_y });

    // Verify FlatCell size
    print("  FlatCell size: {} bytes OK\n", .{@sizeOf(FlatCell)});

    print("\n  All correctness checks PASSED.\n", .{});
}

fn benchmarkSize(alloc: std.mem.Allocator, sz: BenchSize) !void {
    var term = try Terminal.init(alloc, .{ .cols = sz.cols, .rows = sz.rows });
    defer term.deinit(alloc);

    // Fill terminal with mixed content
    fillTerminal(&term, sz.cols, sz.rows) catch {};

    var state: RenderState = .empty;
    defer state.deinit(alloc);

    // Warmup
    for (0..WARMUP_ITERS) |_| {
        // Dirty the terminal to force re-update
        dirtyTerminal(&term) catch {};
        var result = try bulkExport(alloc, &state, &term);
        freeExport(alloc, &result);
    }

    // Benchmark: measure update and flatten separately
    var update_total_ns: u64 = 0;
    var flatten_total_ns: u64 = 0;

    for (0..BENCH_ITERS) |_| {
        // Dirty the terminal
        dirtyTerminal(&term) catch {};

        // Measure update
        const t0 = std.time.nanoTimestamp();
        try state.update(alloc, &term);
        const t1 = std.time.nanoTimestamp();

        // Measure flatten (inline the flatten portion)
        var result = try bulkExportFlattenOnly(alloc, &state);
        const t2 = std.time.nanoTimestamp();

        freeExport(alloc, &result);

        update_total_ns += @intCast(t1 - t0);
        flatten_total_ns += @intCast(t2 - t1);
    }

    const total_cells: usize = @as(usize, sz.cols) * @as(usize, sz.rows);
    const total_bytes = total_cells * @sizeOf(FlatCell);
    const update_avg_us = update_total_ns / BENCH_ITERS / 1000;
    const flatten_avg_us = flatten_total_ns / BENCH_ITERS / 1000;
    const total_avg_us = update_avg_us + flatten_avg_us;

    print("{s:<25} {d:>10} {d:>10} {d:>12} {d:>10} {d:>12}\n", .{
        sz.label,
        total_cells,
        total_bytes,
        update_avg_us,
        flatten_avg_us,
        total_avg_us,
    });
}

fn benchmarkIncremental(alloc: std.mem.Allocator) !void {
    const cols: vt.size.CellCountInt = 200;
    const rows: vt.size.CellCountInt = 50;

    var term = try Terminal.init(alloc, .{ .cols = cols, .rows = rows });
    defer term.deinit(alloc);

    fillTerminal(&term, cols, rows) catch {};

    var state: RenderState = .empty;
    defer state.deinit(alloc);

    // Initial full export
    var initial = try bulkExport(alloc, &state, &term);
    freeExport(alloc, &initial);

    // Now measure incremental updates (only 1 row dirty)
    var incr_total_ns: u64 = 0;

    for (0..BENCH_ITERS) |i| {
        // Write one character to dirty a single row (use proper API)
        const target_row: usize = i % rows;
        term.setCursorPos(target_row + 1, 1); // 1-based
        try term.print('X');

        const t0 = std.time.nanoTimestamp();
        var result = try bulkExport(alloc, &state, &term);
        const t1 = std.time.nanoTimestamp();
        freeExport(alloc, &result);

        incr_total_ns += @intCast(t1 - t0);
    }

    const incr_avg_us = incr_total_ns / BENCH_ITERS / 1000;
    const total_cells: usize = @as(usize, cols) * @as(usize, rows);

    print("  200x50 incremental (1 dirty row): {} us avg\n", .{incr_avg_us});
    print("  vs full export of {} cells\n", .{total_cells});
}

/// Fill terminal with mixed content for realistic benchmarks.
fn fillTerminal(term: *Terminal, cols: vt.size.CellCountInt, rows: vt.size.CellCountInt) !void {
    for (0..rows) |r| {
        // Mix of ASCII and styled content
        if (r % 3 == 0) {
            try term.setAttribute(.bold);
        }
        if (r % 5 == 0) {
            try term.setAttribute(.{ .direct_color_fg = .{ .r = 200, .g = 100, .b = 50 } });
        }

        const fill_cols = @min(cols, 78);
        for (0..fill_cols) |c| {
            const cp: u21 = if (r % 4 == 1 and c % 3 == 0)
                0xD55C // 한 (wide)
            else
                @intCast('A' + (c + r) % 26);
            try term.print(cp);
        }

        if (r + 1 < rows) {
            term.carriageReturn();
            try term.linefeed();
        }

        if (r % 3 == 0 or r % 5 == 0) {
            try term.setAttribute(.unset);
        }
    }
}

/// Dirty the terminal to force RenderState re-update.
fn dirtyTerminal(term: *Terminal) !void {
    term.setCursorPos(1, 1); // move to (0,0) using proper API (1-based)
    try term.print('.');
}

/// Flatten-only portion of bulkExport (for split benchmarking).
fn bulkExportFlattenOnly(alloc: std.mem.Allocator, state: *RenderState) !ExportResult {
    const rows = state.rows;
    const cols = state.cols;
    const total_cells: usize = @as(usize, rows) * @as(usize, cols);

    const flat_cells = try alloc.alloc(FlatCell, total_cells);

    const row_data = state.row_data.slice();
    const row_cells_arr = row_data.items(.cells);
    const row_dirties = row_data.items(.dirty);

    var dirty_bitmap: [4]u64 = .{ 0, 0, 0, 0 };

    for (0..rows) |y| {
        const cells_slice = row_cells_arr[y].slice();
        const cells_raw = cells_slice.items(.raw);
        const cells_style = cells_slice.items(.style);
        const cell_count = @min(cells_raw.len, cols);

        if (row_dirties[y] and y < 256) {
            dirty_bitmap[y / 64] |= @as(u64, 1) << @intCast(y % 64);
        }

        const row_offset = y * cols;
        const dest = flat_cells[row_offset .. row_offset + cols];

        for (0..cell_count) |x| {
            const raw = cells_raw[x];
            const style = cells_style[x];

            dest[x] = .{
                .codepoint = raw.codepoint(),
                .fg = vt.render_export.PackedColor.fromStyleColor(if (raw.hasStyling()) style.fg_color else .none),
                .bg = vt.render_export.PackedColor.fromStyleColor(if (raw.hasStyling()) style.bg_color else .none),
                .flags = if (raw.hasStyling()) @bitCast(style.flags) else 0,
                .wide = @intFromEnum(raw.wide),
                .content_tag = @intFromEnum(raw.content_tag),
            };
        }

        if (cell_count < cols) {
            @memset(dest[cell_count..], .{});
        }
    }

    return .{
        .cells = flat_cells.ptr,
        .rows = rows,
        .cols = cols,
        .dirty_bitmap = dirty_bitmap,
        .cursor_x = @intCast(state.cursor.active.x),
        .cursor_y = @intCast(state.cursor.active.y),
        .bg = .{ .tag = 2, .r = state.colors.background.r, .g = state.colors.background.g, .b = state.colors.background.b },
        .fg = .{ .tag = 2, .r = state.colors.foreground.r, .g = state.colors.foreground.g, .b = state.colors.foreground.b },
        .dirty_state = @intFromEnum(state.dirty),
        ._pad = .{ 0, 0, 0, 0, 0 },
    };
}
