const std = @import("std");
const builtin = @import("builtin");
const transport_mod = @import("transport.zig");
const Transport = transport_mod.Transport;

const socket_t = std.posix.socket_t;
const MAX_SOCKET_PATH: usize = @as(std.posix.sockaddr.un, undefined).path.len;

// getpeereid is not in std — declare it directly.
extern "c" fn getpeereid(fd: socket_t, euid: *std.posix.uid_t, egid: *std.posix.gid_t) c_int;

pub const ListenError = error{
    PathTooLong,
    SocketCreate,
    Bind,
    Listen,
    DaemonAlreadyRunning,
    DirectoryCreate,
};

pub const AcceptError = error{
    Accept,
    UidMismatch,
    GetPeerCredFailed,
};

pub const StaleProbeResult = enum {
    no_prior_socket,
    stale_cleaned,
    daemon_running,
};

pub const Listener = struct {
    listen_fd: socket_t,
    socket_path_storage: [MAX_SOCKET_PATH]u8,
    socket_path_length: usize,

    /// Returns the listen fd for kqueue/epoll registration.
    pub fn fd(self: *const Listener) socket_t {
        return self.listen_fd;
    }

    pub fn socketPath(self: *const Listener) []const u8 {
        return self.socket_path_storage[0..self.socket_path_length];
    }

    /// Accept a new client connection.
    /// Performs UID verification, sets O_NONBLOCK and SO_SNDBUF/SO_RCVBUF on the
    /// accepted fd.
    pub fn accept(self: *Listener) AcceptError!socket_t {
        _ = self;
        // TODO: implement
        return error.Accept;
    }

    pub fn close(self: *Listener) void {
        std.posix.close(self.listen_fd);
        const path = self.socketPath();
        std.posix.unlink(path) catch {};
    }
};

/// Create a server listener.
///
/// ```
///   socket() → stale detection (report to caller) → ensureDirectory(0700) →
///   bind() → listen() → chmod(0600) → O_NONBLOCK
/// ```
///
/// Returns error.DaemonAlreadyRunning if the socket is alive (not stale).
pub fn listen(socket_path: []const u8) ListenError!Listener {
    if (socket_path.len > MAX_SOCKET_PATH) return error.PathTooLong;

    // Stale socket detection — report result to caller per spec §1.5.5.
    switch (probeStaleSocket(socket_path)) {
        .daemon_running => return error.DaemonAlreadyRunning,
        .stale_cleaned, .no_prior_socket => {},
    }

    // Ensure directory exists with 0700 permissions.
    ensureDirectory(socket_path) catch return error.DirectoryCreate;

    const fd = std.posix.socket(std.posix.AF.UNIX, std.posix.SOCK.STREAM, 0) catch
        return error.SocketCreate;
    errdefer std.posix.close(fd);

    // Bind
    var addr: std.posix.sockaddr.un = .{ .path = undefined };
    @memset(&addr.path, 0);
    @memcpy(addr.path[0..socket_path.len], socket_path);
    std.posix.bind(fd, @ptrCast(&addr), @sizeOf(std.posix.sockaddr.un)) catch
        return error.Bind;

    // listen
    std.posix.listen(fd, 16) catch return error.Listen;

    // chmod 0600 on socket file (defense-in-depth; directory is 0700).
    chmodSocket(socket_path);

    // O_NONBLOCK on listen fd
    setNonBlock(fd);

    var result = Listener{
        .listen_fd = fd,
        .socket_path_storage = undefined,
        .socket_path_length = socket_path.len,
    };
    @memcpy(result.socket_path_storage[0..socket_path.len], socket_path);
    return result;
}

/// Probe whether a prior socket exists and is alive or stale.
fn probeStaleSocket(socket_path: []const u8) StaleProbeResult {
    const probe_fd = std.posix.socket(std.posix.AF.UNIX, std.posix.SOCK.STREAM, 0) catch
        return .no_prior_socket;
    defer std.posix.close(probe_fd);

    var addr: std.posix.sockaddr.un = .{ .path = undefined };
    @memset(&addr.path, 0);
    if (socket_path.len >= addr.path.len) return .no_prior_socket;
    @memcpy(addr.path[0..socket_path.len], socket_path);

    std.posix.connect(probe_fd, @ptrCast(&addr), @sizeOf(std.posix.sockaddr.un)) catch {
        // Connection failed — stale socket, clean it up.
        std.posix.unlink(socket_path) catch {};
        return .stale_cleaned;
    };
    // Connection succeeded — daemon is already running.
    return .daemon_running;
}

fn ensureDirectory(socket_path: []const u8) !void {
    const dir = std.fs.path.dirname(socket_path) orelse return;
    std.posix.mkdir(dir, 0o700) catch |err| switch (err) {
        error.PathAlreadyExists => {},
        else => return err,
    };
}

fn chmodSocket(socket_path: []const u8) void {
    var path_buf: [MAX_SOCKET_PATH + 1]u8 = undefined;
    @memcpy(path_buf[0..socket_path.len], socket_path);
    path_buf[socket_path.len] = 0;
    _ = std.c.chmod(@ptrCast(&path_buf), 0o600);
}

fn setNonBlock(fd: socket_t) void {
    const flags = std.posix.fcntl(fd, std.posix.F.GETFL, 0) catch return;
    _ = std.posix.fcntl(fd, std.posix.F.SETFL, flags | @as(u32, @bitCast(std.posix.O{ .NONBLOCK = true }))) catch {};
}
