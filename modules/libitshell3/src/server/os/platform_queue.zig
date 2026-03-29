const builtin = @import("builtin");
const kqueue = @import("kqueue.zig");
const epoll = @import("epoll.zig");

/// Platform-appropriate event loop context.
/// On macOS/BSD: wraps kqueue. On Linux: wraps epoll.
pub const PlatformContext = if (builtin.os.tag.isBSD())
    kqueue.KqueueContext
else if (builtin.os.tag == .linux)
    epoll.EpollContext
else
    @compileError("Unsupported platform: no event loop backend available");
