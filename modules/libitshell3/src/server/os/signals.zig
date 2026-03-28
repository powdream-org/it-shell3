const std = @import("std");
const interfaces = @import("interfaces.zig");

pub const real_signal_ops: interfaces.SignalOps = .{
    .blockSignals = realBlockSignals,
    .registerSignals = realRegisterSignals,
    .waitChild = realWaitChild,
};

fn realBlockSignals() interfaces.SignalOps.SignalError!void {
    var set = std.posix.sigemptyset();
    std.posix.sigaddset(&set, std.posix.SIG.CHLD);
    std.posix.sigaddset(&set, std.posix.SIG.TERM);
    std.posix.sigaddset(&set, std.posix.SIG.INT);
    std.posix.sigaddset(&set, std.posix.SIG.HUP);
    std.posix.sigprocmask(std.posix.SIG.BLOCK, &set, null);
}

fn realRegisterSignals(ctx: *anyopaque, event_ops: *const interfaces.EventLoopOps) interfaces.SignalOps.SignalError!void {
    const signals = [_]u8{
        std.posix.SIG.CHLD,
        std.posix.SIG.TERM,
        std.posix.SIG.INT,
        std.posix.SIG.HUP,
    };
    for (signals) |sig| {
        event_ops.registerRead(ctx, @intCast(sig), .{ .signal = .{ .signal_number = sig } }) catch return error.SignalSetupFailed;
    }
}

fn realWaitChild() ?interfaces.SignalOps.WaitResult {
    var status: c_int = 0;
    const rc = std.c.waitpid(-1, &status, std.posix.W.NOHANG);
    if (rc <= 0) return null;
    const pid: std.posix.pid_t = @intCast(rc);
    const exit_status: u8 = if (std.posix.W.IFEXITED(@bitCast(status)))
        std.posix.W.EXITSTATUS(@bitCast(status))
    else
        0;
    return .{ .pid = pid, .exit_status = exit_status };
}

test "realBlockSignals: does not crash" {
    try real_signal_ops.blockSignals();
}
