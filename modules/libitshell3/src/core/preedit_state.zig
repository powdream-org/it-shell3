const std = @import("std");
const types = @import("types.zig");

pub const ClientId = types.ClientId;

pub const PreeditState = struct {
    owner: ?ClientId, // Which client owns the current composition, or null
    session_id: u32, // Monotonically increasing sequence counter

    pub fn init() PreeditState {
        return .{ .owner = null, .session_id = 0 };
    }

    pub fn incrementSessionId(self: *PreeditState) void {
        self.session_id += 1;
    }
};

test "PreeditState.init: returns null owner and session_id 0" {
    const ps = PreeditState.init();
    try std.testing.expectEqual(@as(?ClientId, null), ps.owner);
    try std.testing.expectEqual(@as(u32, 0), ps.session_id);
}

test "PreeditState.incrementSessionId: increments by 1" {
    var ps = PreeditState.init();
    try std.testing.expectEqual(@as(u32, 0), ps.session_id);
    ps.incrementSessionId();
    try std.testing.expectEqual(@as(u32, 1), ps.session_id);
    ps.incrementSessionId();
    try std.testing.expectEqual(@as(u32, 2), ps.session_id);
}

test "PreeditState: can set owner and verify it" {
    var ps = PreeditState.init();
    const client: ClientId = 123;
    ps.owner = client;
    try std.testing.expectEqual(@as(?ClientId, 123), ps.owner);
}
