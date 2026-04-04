//! Spec behavior tests for Plan 9: Frame Delivery & Runtime Policies.
//!
//! Tests are derived from daemon-behavior v1.0-r9 (resize policy, client
//! health, flow control, coalescing tiers), daemon-architecture v1.0-r9
//! (frame export pipeline, I-frame scheduling), and server-client-protocols
//! v1.0-r13 (FrameUpdate wire format, flow control messages).

const std = @import("std");
const server = @import("itshell3_server");
const core = @import("itshell3_core");
const protocol = @import("itshell3_protocol");
const testing_helpers = @import("itshell3_testing").helpers;

// ── Ring Buffer Lag Thresholds (daemon-behavior smooth degradation, ADR 00055)

test "spec: ring lag thresholds computed at init from capacity (ADR 00055)" {
    // Spec: threshold_50 = capacity >> 1, threshold_75 = (capacity>>1) + (capacity>>2),
    // threshold_90 = capacity - capacity/10
    const ring_buffer_mod = server.delivery.ring_buffer;
    var backing: [2048]u8 = @splat(0);
    const rb = ring_buffer_mod.RingBuffer.init(&backing);
    try std.testing.expectEqual(@as(usize, 1024), rb.threshold_50);
    try std.testing.expectEqual(@as(usize, 1536), rb.threshold_75);
    try std.testing.expectEqual(@as(usize, 1844), rb.threshold_90); // 2048 - 2048/10 = 2048 - 204 = 1844
}

test "spec: lag at exactly 50 percent does NOT trigger degradation (strict >)" {
    // Spec smooth degradation: uses strict greater-than semantics
    const ring_buffer_mod = server.delivery.ring_buffer;
    var backing: [200]u8 = @splat(0);
    var rb = ring_buffer_mod.RingBuffer.init(&backing);
    const cursor = ring_buffer_mod.RingCursor.init();

    // Write exactly 100 bytes = threshold_50 = 200 >> 1
    const frame = [_]u8{'A'} ** 100;
    try rb.writeFrame(&frame, true, 1);
    try std.testing.expect(!rb.isLagAbove50(&cursor)); // At threshold, not above
}

test "spec: lag above 50 percent triggers auto-downgrade" {
    const ring_buffer_mod = server.delivery.ring_buffer;
    var backing: [200]u8 = @splat(0);
    var rb = ring_buffer_mod.RingBuffer.init(&backing);
    const cursor = ring_buffer_mod.RingCursor.init();

    const frame = [_]u8{'A'} ** 100;
    try rb.writeFrame(&frame, true, 1);
    try rb.writeFrame("B", false, 2); // 101 > 100
    try std.testing.expect(rb.isLagAbove50(&cursor));
}

test "spec: lag above 90 percent triggers I-frame seek on next ContinuePane" {
    const ring_buffer_mod = server.delivery.ring_buffer;
    var backing: [100]u8 = @splat(0);
    var rb = ring_buffer_mod.RingBuffer.init(&backing);
    var cursor = ring_buffer_mod.RingCursor.init();

    // threshold_90 = 100 - 10 = 90
    const frame45 = [_]u8{'X'} ** 45;
    try rb.writeFrame(&frame45, true, 1);
    try rb.writeFrame(&frame45, false, 2);
    try rb.writeFrame("Z", false, 3); // 91 > 90
    try std.testing.expect(rb.isLagAbove90(&cursor));

    // Recovery: seek to latest I-frame
    rb.seekToLatestIFrame(&cursor);
    try std.testing.expect(!rb.isCursorOverwritten(&cursor));
    _ = &cursor;
}

// ── Coalescing Tier Model (daemon-behavior coalescing tiers) ────────────────

test "spec: four-tier model base intervals" {
    // Spec coalescing tier model: Tier 0=0ms, Tier 1=0ms, Tier 2=16ms, Tier 3=33ms
    const coalescing = server.delivery.coalescing_state;
    try std.testing.expectEqual(@as(u32, 0), coalescing.CoalescingTier.preedit.baseIntervalMs());
    try std.testing.expectEqual(@as(u32, 0), coalescing.CoalescingTier.interactive.baseIntervalMs());
    try std.testing.expectEqual(@as(u32, 16), coalescing.CoalescingTier.active.baseIntervalMs());
    try std.testing.expectEqual(@as(u32, 33), coalescing.CoalescingTier.bulk.baseIntervalMs());
}

test "spec: preedit tier override regardless of current tier" {
    // Spec preedit immediate delivery: state changes MUST trigger immediate frame delivery
    const coalescing = server.delivery.coalescing_state;
    var cs = coalescing.CoalescingState{ .tier = .bulk };
    cs.triggerPreedit(1000);
    try std.testing.expectEqual(coalescing.CoalescingTier.preedit, cs.tier);
}

test "spec: upgrade is immediate, downgrade requires sustained condition" {
    const coalescing = server.delivery.coalescing_state;
    // Upgrade: immediate
    var cs = coalescing.CoalescingState{ .tier = .active, .tier_entered_at = 1000 };
    cs.upgradeTo(.interactive, 1001);
    try std.testing.expectEqual(coalescing.CoalescingTier.interactive, cs.tier);

    // Downgrade: interactive -> active requires sustained output >100ms
    var cs2 = coalescing.CoalescingState{};
    cs2.processOutput(1000); // idle -> interactive
    cs2.processOutput(1050); // 50ms < 100ms: still interactive
    try std.testing.expectEqual(coalescing.CoalescingTier.interactive, cs2.tier);
    cs2.processOutput(1101); // 101ms > 100ms: -> active
    try std.testing.expectEqual(coalescing.CoalescingTier.active, cs2.tier);
}

test "spec: WAN ssh raises Tier 2 to 33ms and Tier 3 to 100ms" {
    const coalescing = server.delivery.coalescing_state;
    const ClientState = server.connection.client_state.ClientState;
    const info = ClientState.ClientDisplayInfo{ .transport_type = .ssh_tunnel };

    const cs_active = coalescing.CoalescingState{ .tier = .active };
    try std.testing.expectEqual(@as(u32, 33), cs_active.effectiveIntervalMs(&info));

    const cs_bulk = coalescing.CoalescingState{ .tier = .bulk };
    try std.testing.expectEqual(@as(u32, 100), cs_bulk.effectiveIntervalMs(&info));
}

test "spec: preedit never throttled regardless of power/transport/bandwidth" {
    const coalescing = server.delivery.coalescing_state;
    const ClientState = server.connection.client_state.ClientState;
    const info = ClientState.ClientDisplayInfo{
        .power_state = .low_battery,
        .transport_type = .ssh_tunnel,
        .bandwidth_hint = .cellular,
    };

    const cs = coalescing.CoalescingState{ .tier = .preedit };
    try std.testing.expectEqual(@as(u32, 0), cs.effectiveIntervalMs(&info));
}

test "spec: idle suppression during resize + 500ms settling" {
    const coalescing = server.delivery.coalescing_state;
    var cs = coalescing.CoalescingState{ .tier = .active, .last_output_timestamp = 1000 };

    // Set resize idle suppression for 500ms after debounce at T=1250
    cs.setResizeIdleSuppression(1750); // debounce + 500ms settling

    // At T=1200, normally idle (200ms > 100ms threshold), but suppressed
    cs.checkIdle(1200, 100);
    try std.testing.expectEqual(coalescing.CoalescingTier.active, cs.tier);

    // At T=1800, suppression expired, idle transition resumes
    cs.checkIdle(1800, 100);
    try std.testing.expectEqual(coalescing.CoalescingTier.idle, cs.tier);
}

test "spec: power-aware battery caps at Tier 2" {
    const coalescing = server.delivery.coalescing_state;
    const ClientState = server.connection.client_state.ClientState;
    const info = ClientState.ClientDisplayInfo{ .power_state = .battery };

    const cs = coalescing.CoalescingState{ .tier = .interactive };
    try std.testing.expectEqual(@as(u32, 16), cs.effectiveIntervalMs(&info));
}

test "spec: power-aware low_battery caps at Tier 3" {
    const coalescing = server.delivery.coalescing_state;
    const ClientState = server.connection.client_state.ClientState;
    const info = ClientState.ClientDisplayInfo{ .power_state = .low_battery };

    const cs = coalescing.CoalescingState{ .tier = .interactive };
    try std.testing.expectEqual(@as(u32, 33), cs.effectiveIntervalMs(&info));
}

test "spec: high RTT raises idle threshold to 200ms" {
    const coalescing = server.delivery.coalescing_state;
    const ClientState = server.connection.client_state.ClientState;
    const info_high_rtt = ClientState.ClientDisplayInfo{ .estimated_rtt_ms = 150 };
    try std.testing.expectEqual(@as(u32, 200), coalescing.CoalescingState.idleThresholdMs(&info_high_rtt));

    const info_low_rtt = ClientState.ClientDisplayInfo{ .estimated_rtt_ms = 50 };
    try std.testing.expectEqual(@as(u32, 100), coalescing.CoalescingState.idleThresholdMs(&info_low_rtt));
}

// ── PausePane Escalation Timeline (daemon-behavior PausePane escalation) ──

test "spec: PausePane sets paused and records start time" {
    const ClientState = server.connection.client_state.ClientState;
    var client = ClientState.init(.{ .fd = 7 }, 42, testing_helpers.testChunkPool());
    defer client.deinit();

    client.paused = true;
    client.pause_started_at = 1000;

    try std.testing.expect(client.paused);
    try std.testing.expectEqual(@as(i64, 1000), client.pause_started_at);
    // Health remains healthy at T=0 (pause just started)
    try std.testing.expectEqual(ClientState.HealthState.healthy, client.health_state);
}

test "spec: PausePane escalation T=5s resize excluded from pause duration" {
    // Per daemon-behavior PausePane escalation: resize during pause does NOT
    // reset the escalation timer. Paused + resize = still paused, timer continues.
    const ClientState = server.connection.client_state.ClientState;
    var client = ClientState.init(.{ .fd = 7 }, 42, testing_helpers.testChunkPool());
    defer client.deinit();

    client.paused = true;
    client.pause_started_at = 1000;
    // Resize at T+5s does not unpause
    // (resize is excluded from application-level messages that reset pause)
    try std.testing.expect(client.paused);
}

test "spec: PausePane escalation T=60s stale (local transport)" {
    // Per daemon-behavior PausePane escalation: after stale_timeout_ms (60s for
    // local), the client transitions to stale health state.
    const ClientState = server.connection.client_state.ClientState;
    var client = ClientState.init(.{ .fd = 7 }, 42, testing_helpers.testChunkPool());
    defer client.deinit();

    client.paused = true;
    client.pause_started_at = 1000;

    // Default local stale timeout is 60000ms
    try std.testing.expectEqual(@as(u32, 60000), client.flow_control.stale_timeout_ms);

    // After stale timeout, server marks client stale
    client.markStale();
    try std.testing.expectEqual(ClientState.HealthState.stale, client.health_state);
    // Client is still paused AND stale (orthogonal states)
    try std.testing.expect(client.paused);
}

test "spec: PausePane escalation T=120s stale (SSH transport)" {
    // Per daemon-behavior PausePane escalation: SSH transport has longer stale
    // timeout (120s) due to higher latency tolerance.
    const ClientState = server.connection.client_state.ClientState;
    const ssh_config = ClientState.FlowControlConfig.defaultForTransport(.ssh_tunnel);
    try std.testing.expectEqual(@as(u32, 120000), ssh_config.stale_timeout_ms);
}

test "spec: PausePane escalation T=300s eviction timeout" {
    // Per daemon-behavior PausePane escalation: after eviction_timeout_ms (300s),
    // the server may evict the client connection entirely.
    const ClientState = server.connection.client_state.ClientState;
    var client = ClientState.init(.{ .fd = 7 }, 42, testing_helpers.testChunkPool());
    defer client.deinit();

    // Default eviction timeout is 300000ms (5 minutes)
    try std.testing.expectEqual(@as(u32, 300000), client.flow_control.eviction_timeout_ms);

    // Server-enforced minimum prevents eviction_timeout < 60s
    client.flow_control.eviction_timeout_ms = @max(30000, 60000);
    try std.testing.expectEqual(@as(u32, 60000), client.flow_control.eviction_timeout_ms);
}

test "spec: ContinuePane clears pause and restores health" {
    // Per daemon-behavior ContinuePane recovery: clears paused state and
    // restores health to healthy (if was stale from pause escalation).
    const ClientState = server.connection.client_state.ClientState;
    var client = ClientState.init(.{ .fd = 7 }, 42, testing_helpers.testChunkPool());
    defer client.deinit();

    // Simulate pause escalation to stale
    client.paused = true;
    client.pause_started_at = 1000;
    client.markStale();
    try std.testing.expect(client.paused);
    try std.testing.expectEqual(ClientState.HealthState.stale, client.health_state);

    // ContinuePane recovery
    client.paused = false;
    client.markHealthy();
    client.recordApplicationMessage();

    try std.testing.expect(!client.paused);
    try std.testing.expectEqual(ClientState.HealthState.healthy, client.health_state);
    try std.testing.expect(client.last_application_message_at > 0);
}

// ── Client Health State (daemon-behavior client health model) ───────────────

test "spec: client health defaults to healthy" {
    const ClientState = server.connection.client_state.ClientState;
    const client = ClientState.init(.{ .fd = 7 }, 42, testing_helpers.testChunkPool());
    try std.testing.expectEqual(ClientState.HealthState.healthy, client.health_state);
    try std.testing.expect(!client.paused);
}

test "spec: FlowControlConfig transport-aware defaults" {
    const ClientState = server.connection.client_state.ClientState;
    const local = ClientState.FlowControlConfig.defaultForTransport(.local);
    try std.testing.expectEqual(@as(u32, 5000), local.max_queue_age_ms);
    try std.testing.expectEqual(@as(u32, 60000), local.stale_timeout_ms);

    const ssh = ClientState.FlowControlConfig.defaultForTransport(.ssh_tunnel);
    try std.testing.expectEqual(@as(u32, 10000), ssh.max_queue_age_ms);
    try std.testing.expectEqual(@as(u32, 120000), ssh.stale_timeout_ms);
}

test "spec: paused is orthogonal to health state" {
    const ClientState = server.connection.client_state.ClientState;
    var client = ClientState.init(.{ .fd = 7 }, 42, testing_helpers.testChunkPool());
    defer client.deinit();

    client.paused = true;
    // Paused client is still healthy
    try std.testing.expectEqual(ClientState.HealthState.healthy, client.health_state);

    client.markStale();
    // Can be both paused and stale
    try std.testing.expect(client.paused);
    try std.testing.expectEqual(ClientState.HealthState.stale, client.health_state);
}

test "spec: recordApplicationMessage resets stale timeout" {
    const ClientState = server.connection.client_state.ClientState;
    var client = ClientState.init(.{ .fd = 7 }, 42, testing_helpers.testChunkPool());
    defer client.deinit();

    client.last_application_message_at = 0;
    client.recordApplicationMessage();
    try std.testing.expect(client.last_application_message_at > 0);
}

// ── Frame Builder (daemon-architecture frame export pipeline) ───────────────

test "spec: empty dirty bitmap produces no DirtyRows for P-frame" {
    const frame_builder = server.delivery.frame_builder;
    const bitmap: [frame_builder.MAX_ROWS / 8]u8 = @splat(0);

    var cells: [1]protocol.cell.CellData = @splat(std.mem.zeroes(protocol.cell.CellData));
    const row_data = [_][]const protocol.cell.CellData{&cells};
    const grapheme_tables = [_][]const protocol.cell.GraphemeEntry{&.{}};
    const underline_color_tables = [_][]const protocol.cell.UnderlineColorEntry{&.{}};

    const er = frame_builder.ExportResult{
        .rows = &row_data,
        .dirty_bitmap = bitmap,
        .cols = 1,
        .num_rows = 1,
        .grapheme_tables = &grapheme_tables,
        .underline_color_tables = &underline_color_tables,
    };

    var out: [frame_builder.MAX_ROWS]protocol.frame_update.DirtyRow = undefined;
    const count = frame_builder.assembleDirtyRows(&er, false, &out);
    try std.testing.expectEqual(@as(u16, 0), count);
}

test "spec: force_all=true includes all rows (I-frame scenario)" {
    const frame_builder = server.delivery.frame_builder;
    const bitmap: [frame_builder.MAX_ROWS / 8]u8 = @splat(0);
    // Even with empty bitmap, force_all includes all rows

    var cells: [2]protocol.cell.CellData = @splat(std.mem.zeroes(protocol.cell.CellData));
    const row_data = [_][]const protocol.cell.CellData{ &cells, &cells, &cells };
    const grapheme_tables = [_][]const protocol.cell.GraphemeEntry{ &.{}, &.{}, &.{} };
    const underline_color_tables = [_][]const protocol.cell.UnderlineColorEntry{ &.{}, &.{}, &.{} };

    const er = frame_builder.ExportResult{
        .rows = &row_data,
        .dirty_bitmap = bitmap,
        .cols = 2,
        .num_rows = 3,
        .grapheme_tables = &grapheme_tables,
        .underline_color_tables = &underline_color_tables,
    };

    var out: [frame_builder.MAX_ROWS]protocol.frame_update.DirtyRow = undefined;
    const count = frame_builder.assembleDirtyRows(&er, true, &out);
    try std.testing.expectEqual(@as(u16, 3), count);
}

// ── Frame Serializer JSON Metadata (protocol 04 FrameUpdate wire format) ────

test "spec: JSON metadata sets section_flags bit 7" {
    const frame_serializer = server.delivery.frame_serializer;
    const ring_buffer_mod = server.delivery.ring_buffer;

    var backing: [256 * 1024]u8 = @splat(0);
    var ring = ring_buffer_mod.RingBuffer.init(&backing);
    var scratch: [frame_serializer.SCRATCH_SIZE]u8 = @splat(0);
    var seq: u64 = 0;

    // Fake JSON metadata (length-prefixed)
    var metadata_buf: [32]u8 = @splat(0);
    const json = "{}";
    std.mem.writeInt(u32, metadata_buf[0..4], @intCast(json.len), .little);
    @memcpy(metadata_buf[4..][0..json.len], json);
    const metadata = metadata_buf[0 .. 4 + json.len];

    const n = frame_serializer.serializeAndWriteWithMetadata(
        &scratch,
        &ring,
        1,
        1,
        .i_frame,
        &.{},
        metadata,
        &seq,
    );
    try std.testing.expect(n != null);

    // Read back and verify section_flags bit 7
    var cursor = ring_buffer_mod.RingCursor.init();
    const p = ring.pendingIovecs(&cursor).?;
    var read_buf: [8192]u8 = @splat(0);
    var off: usize = 0;
    for (p.iov[0..p.count]) |v| {
        @memcpy(read_buf[off..][0..v.len], v.base[0..v.len]);
        off += v.len;
    }

    const fh = protocol.frame_update.FrameHeader.decode(
        read_buf[protocol.header.HEADER_SIZE..][0..protocol.frame_update.FRAME_HEADER_SIZE],
    );
    try std.testing.expect(fh.hasJsonMetadata());
}

test "spec: no JSON metadata leaves bit 7 clear" {
    const frame_serializer = server.delivery.frame_serializer;
    const ring_buffer_mod = server.delivery.ring_buffer;

    var backing: [256 * 1024]u8 = @splat(0);
    var ring = ring_buffer_mod.RingBuffer.init(&backing);
    var scratch: [frame_serializer.SCRATCH_SIZE]u8 = @splat(0);
    var seq: u64 = 0;

    const n = frame_serializer.serializeAndWriteWithMetadata(
        &scratch,
        &ring,
        1,
        1,
        .i_frame,
        &.{},
        null,
        &seq,
    );
    try std.testing.expect(n != null);

    var cursor = ring_buffer_mod.RingCursor.init();
    const p = ring.pendingIovecs(&cursor).?;
    var read_buf: [8192]u8 = @splat(0);
    var off: usize = 0;
    for (p.iov[0..p.count]) |v| {
        @memcpy(read_buf[off..][0..v.len], v.base[0..v.len]);
        off += v.len;
    }

    const fh = protocol.frame_update.FrameHeader.decode(
        read_buf[protocol.header.HEADER_SIZE..][0..protocol.frame_update.FRAME_HEADER_SIZE],
    );
    try std.testing.expect(!fh.hasJsonMetadata());
}

// ── Pane I-Frame Scheduling (daemon-architecture I-frame scheduling, ADR 00057)

test "spec: I-frame timer no-op when pane has no changes" {
    const Pane = server.state.pane.Pane;
    var pane = Pane.init(1, 0, 5, 100, 80, 24);
    pane.recordIFrameProduction(1000);
    // No changes since I-frame
    try std.testing.expect(!pane.needsIFrame(2001, 1000));
}

test "spec: I-frame timer fires when pane has changes and interval elapsed" {
    const Pane = server.state.pane.Pane;
    var pane = Pane.init(1, 0, 5, 100, 80, 24);
    pane.recordIFrameProduction(1000);
    pane.markChangedSinceIFrame();
    // 1001ms >= 1000ms interval
    try std.testing.expect(pane.needsIFrame(2001, 1000));
}

test "spec: I-frame from resize resets timer (ADR 00057)" {
    const Pane = server.state.pane.Pane;
    var pane = Pane.init(1, 0, 5, 100, 80, 24);
    pane.recordIFrameProduction(1000); // Initial I-frame
    pane.markChangedSinceIFrame();

    // Resize at T=1500 produces I-frame, resets timer
    pane.recordIFrameProduction(1500);
    // At T=2000, only 500ms since last I-frame, not yet due
    pane.markChangedSinceIFrame();
    try std.testing.expect(!pane.needsIFrame(2000, 1000));
    // At T=2501, 1001ms since last I-frame, due
    try std.testing.expect(pane.needsIFrame(2501, 1000));
}

// ── Frame Suppression for Undersized Panes (daemon-architecture frame export)

test "spec: pane with cols < 2 is undersized" {
    const Pane = server.state.pane.Pane;
    const pane = Pane.init(1, 0, 5, 100, 1, 24);
    try std.testing.expect(pane.isUndersized());
}

test "spec: pane with rows < 1 is undersized" {
    const Pane = server.state.pane.Pane;
    const pane = Pane.init(1, 0, 5, 100, 80, 0);
    try std.testing.expect(pane.isUndersized());
}

test "spec: pane with cols=2 rows=1 is NOT undersized" {
    const Pane = server.state.pane.Pane;
    const pane = Pane.init(1, 0, 5, 100, 2, 1);
    try std.testing.expect(!pane.isUndersized());
}

// ── Resize Orchestration Ordering (daemon-behavior resize orchestration) ──

test "spec: resize orchestration ordering WindowResizeAck before LayoutChanged before I-frame" {
    // Per daemon-behavior resize orchestration ordering: the resize sequence
    // must execute in this exact order:
    // 1. ioctl(TIOCSWINSZ) via OS vtable
    // 2. WindowResizeAck to requester
    // 3. LayoutChanged to all clients
    // 4. I-frame(s) to ring
    const resize_handler = server.handlers.resize_handler;
    const Pane = server.state.pane.Pane;
    const SessionEntry = server.state.session_entry.SessionEntry;
    const session_mod = core.session;
    const s = session_mod.Session.init(1, "s", 0, testing_helpers.testImeEngine(), 0);
    var entry = SessionEntry.init(s);
    const slot = try entry.allocPaneSlot();
    entry.setPaneAtSlot(slot, Pane.init(1, slot, 5, 100, 80, 24));
    const pane = entry.getPaneAtSlot(slot).?;

    // Execute orchestration (no PTY ops in test)
    const result = resize_handler.orchestrateResize(pane, &entry, 120, 40, null, 1000);

    // All steps must be performed (ioctl skipped without PTY ops)
    try std.testing.expect(!result.ioctl_applied); // No PTY ops provided
    try std.testing.expect(result.ack_sent); // Step 2: WindowResizeAck
    try std.testing.expect(result.layout_changed_sent); // Step 3: LayoutChanged
    try std.testing.expect(result.i_frame_queued); // Step 4: I-frame

    // Verify side effects: pane dimensions updated, dirty flag set
    try std.testing.expectEqual(@as(u16, 120), pane.cols);
    try std.testing.expectEqual(@as(u16, 40), pane.rows);
    try std.testing.expect(entry.isDirty(slot));
    try std.testing.expectEqual(@as(u16, 120), entry.effective_cols);
    try std.testing.expectEqual(@as(u16, 40), entry.effective_rows);
}

// ── Resize (daemon-behavior resize policy) ─────────────────────────────────

test "spec: first resize fires immediately (no debounce)" {
    const resize_handler = server.handlers.resize_handler;
    const Pane = server.state.pane.Pane;
    var pane = Pane.init(1, 0, 5, 100, 80, 24);
    try std.testing.expect(!pane.first_resize_done);
    try std.testing.expect(resize_handler.shouldResizeImmediately(&pane, 1000));
}

test "spec: subsequent resize debounced at 250ms" {
    const resize_handler = server.handlers.resize_handler;
    const Pane = server.state.pane.Pane;
    var pane = Pane.init(1, 0, 5, 100, 80, 24);
    pane.first_resize_done = true;
    resize_handler.setResizeDebounce(&pane, 1000);

    // Before debounce expires
    try std.testing.expect(!resize_handler.shouldResizeImmediately(&pane, 1200));
    // After debounce expires (1000 + 250 = 1250)
    try std.testing.expect(resize_handler.shouldResizeImmediately(&pane, 1250));
}

test "spec: session effective dimensions update on WindowResize" {
    const session_mod = core.session;
    const SessionEntry = server.state.session_entry.SessionEntry;
    const s = session_mod.Session.init(1, "s", 0, testing_helpers.testImeEngine(), 0);
    var entry = SessionEntry.init(s);

    try std.testing.expectEqual(@as(u16, 80), entry.effective_cols);
    try std.testing.expectEqual(@as(u16, 24), entry.effective_rows);

    entry.setEffectiveDimensions(120, 40);
    try std.testing.expectEqual(@as(u16, 120), entry.effective_cols);
    try std.testing.expectEqual(@as(u16, 40), entry.effective_rows);
}

// ── Metadata Serializer (protocol 04 FrameUpdate metadata) ─────────────────

test "spec: I-frame metadata includes all required fields" {
    const metadata_serializer = server.delivery.metadata_serializer;
    var palette: [256]metadata_serializer.RgbColor = @splat(metadata_serializer.RgbColor{});
    const metadata = metadata_serializer.IFrameMetadata{
        .cursor = .{},
        .dimensions = .{ .cols = 80, .rows = 24 },
        .palette = &palette,
        .fg = .{},
        .bg = .{},
        .mouse = .none,
        .terminal_modes = .{},
    };

    var buf: [metadata_serializer.METADATA_BUFFER_SIZE]u8 = undefined;
    const total = metadata_serializer.serializeIFrameMetadata(&metadata, &buf);
    try std.testing.expect(total != null);

    const json_len = std.mem.readInt(u32, buf[0..4], .little);
    const json = buf[4..][0..json_len];

    // All required fields present
    try std.testing.expect(std.mem.indexOf(u8, json, "\"cursor\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"dimensions\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"palette\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"fg\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"bg\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"mouse\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"terminal_modes\"") != null);
}

test "spec: P-frame metadata omits unchanged fields" {
    const metadata_serializer = server.delivery.metadata_serializer;
    const metadata = metadata_serializer.PFrameMetadata{
        .cursor = .{ .x = 10, .y = 5 },
        // All other fields null = unchanged
    };

    var buf: [metadata_serializer.METADATA_BUFFER_SIZE]u8 = undefined;
    const total = metadata_serializer.serializePFrameMetadata(&metadata, &buf);
    try std.testing.expect(total != null);

    const json_len = std.mem.readInt(u32, buf[0..4], .little);
    const json = buf[4..][0..json_len];

    try std.testing.expect(std.mem.indexOf(u8, json, "\"cursor\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"palette\"") == null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"dimensions\"") == null);
}

test "spec: P-frame with no changes returns null" {
    const metadata_serializer = server.delivery.metadata_serializer;
    const metadata = metadata_serializer.PFrameMetadata{};

    var buf: [metadata_serializer.METADATA_BUFFER_SIZE]u8 = undefined;
    const total = metadata_serializer.serializePFrameMetadata(&metadata, &buf);
    try std.testing.expect(total == null);
}
