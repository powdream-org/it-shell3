//! Server-side Unix socket listener with stale-socket detection, UID
//! verification, and non-blocking I/O setup for accepted connections.

const std = @import("std");
const builtin = @import("builtin");
const transport = @import("transport.zig");
const helper = @import("transport_helper.zig");
const Transport = transport.Transport;

const socket_t = helper.socket_t;
const MAX_SOCKET_PATH = helper.MAX_SOCKET_PATH;
const newFd = helper.newFd;
const makeAddr = helper.makeAddr;

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

/// Result of probing whether an existing socket file belongs to a live daemon.
pub const StaleProbeResult = enum {
    no_prior_socket,
    stale_socket,
    daemon_running,
};

/// Manages a bound Unix listen socket and accepts UID-verified client connections.
pub const Listener = struct {
    listen_fd: socket_t,
    socket_path_storage: [MAX_SOCKET_PATH]u8,
    socket_path_length: usize,

    /// The listen fd for kqueue/epoll registration.
    pub fn fd(self: *const Listener) socket_t {
        return self.listen_fd;
    }

    pub fn socketPath(self: *const Listener) []const u8 {
        return self.socket_path_storage[0..self.socket_path_length];
    }

    /// Socket buffer size for accepted connections (256 KiB per spec).
    pub const SOCKET_BUFFER_SIZE: u32 = 256 * 1024;

    /// Accepts a new client with UID verification, O_NONBLOCK, and buffer tuning.
    pub fn accept(self: *Listener) AcceptError!transport.SocketConnection {
        const client_fd = std.posix.accept(self.listen_fd, null, null, 0) catch return error.Accept;
        errdefer std.posix.close(client_fd);

        // UID verification via getpeereid (macOS/BSD) or SO_PEERCRED (Linux).
        if (comptime builtin.os.tag.isBSD()) {
            var euid: std.posix.uid_t = undefined;
            var egid: std.posix.gid_t = undefined;
            if (getpeereid(client_fd, &euid, &egid) != 0) {
                return error.GetPeerCredFailed;
            }
            const my_uid = std.c.getuid();
            if (euid != my_uid) {
                return error.UidMismatch;
            }
        } else if (comptime builtin.os.tag == .linux) {
            const Ucred = extern struct { pid: i32, uid: u32, gid: u32 };
            var cred: Ucred = undefined;
            var cred_len: u32 = @sizeOf(Ucred);
            const rc = std.c.getsockopt(client_fd, std.posix.SOL.SOCKET, std.os.linux.SO.PEERCRED, @ptrCast(&cred), &cred_len);
            if (rc != 0) {
                return error.GetPeerCredFailed;
            }
            const my_uid = std.c.getuid();
            if (cred.uid != my_uid) {
                return error.UidMismatch;
            }
        }

        // O_NONBLOCK on accepted fd.
        setNonBlock(client_fd);

        // Buffer tuning: SO_SNDBUF and SO_RCVBUF per protocol spec.
        setSocketBufferSize(client_fd, SOCKET_BUFFER_SIZE);

        return transport.SocketConnection{ .fd = client_fd };
    }

    fn setSocketBufferSize(fd_val: socket_t, size: u32) void {
        const size_bytes: [4]u8 = @bitCast(size);
        const SOL_SOCKET: i32 = if (builtin.os.tag == .linux) 1 else 0xFFFF;
        const SO_SNDBUF: u32 = if (builtin.os.tag == .linux) 7 else 0x1001;
        const SO_RCVBUF: u32 = if (builtin.os.tag == .linux) 8 else 0x1002;
        std.posix.setsockopt(fd_val, SOL_SOCKET, SO_SNDBUF, &size_bytes) catch {};
        std.posix.setsockopt(fd_val, SOL_SOCKET, SO_RCVBUF, &size_bytes) catch {};
    }

    /// Releases the listener: closes the fd and removes the socket file from disk.
    pub fn deinit(self: *Listener) void {
        std.posix.close(self.listen_fd);
        const path = self.socketPath();
        std.posix.unlink(path) catch {};
    }
};

/// Binds and listens on a Unix socket at `socket_path`.
///
/// Returns error.DaemonAlreadyRunning if a daemon is already bound.
/// If a stale socket file exists (no daemon listening), it is automatically
/// unlinked and bind proceeds. See daemon-lifecycle spec.
pub fn listen(socket_path: []const u8) ListenError!Listener {
    if (socket_path.len > MAX_SOCKET_PATH) return error.PathTooLong;

    // Stale socket detection. Per daemon-lifecycle spec, unlink stale socket
    // and proceed with bind.
    switch (probeStaleSocket(socket_path)) {
        .daemon_running => return error.DaemonAlreadyRunning,
        .stale_socket => {
            // Unlink the stale socket file and continue with bind.
            std.posix.unlink(socket_path) catch {};
        },
        .no_prior_socket => {},
    }

    ensureDirectory(socket_path, 0o700) catch return error.DirectoryCreate;

    const fd = newFd() catch return error.SocketCreate;
    errdefer std.posix.close(fd);

    const addr = makeAddr(socket_path);
    std.posix.bind(fd, @ptrCast(&addr), @sizeOf(std.posix.sockaddr.un)) catch
        return error.Bind;

    // listen
    std.posix.listen(fd, 16) catch return error.Listen;

    chmodSocket(socket_path, 0o600);

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
    // Check if file exists first.
    std.fs.cwd().access(socket_path, .{}) catch return .no_prior_socket;

    // File exists — try connecting to see if a daemon is listening.
    const fd = newFd() catch return .stale_socket;
    defer std.posix.close(fd);

    const addr = makeAddr(socket_path);
    std.posix.connect(fd, @ptrCast(&addr), @sizeOf(std.posix.sockaddr.un)) catch {
        return .stale_socket;
    };
    return .daemon_running;
}

fn ensureDirectory(socket_path: []const u8, mode: std.posix.mode_t) !void {
    const dir = std.fs.path.dirname(socket_path) orelse return;
    std.posix.mkdir(dir, mode) catch |err| switch (err) {
        error.PathAlreadyExists => {},
        else => return err,
    };
}

const setNonBlock = helper.setNonBlock;

fn chmodSocket(socket_path: []const u8, mode: std.posix.mode_t) void {
    var path_buf: [MAX_SOCKET_PATH + 1]u8 = undefined;
    @memcpy(path_buf[0..socket_path.len], socket_path);
    path_buf[socket_path.len] = 0;
    _ = std.c.chmod(@ptrCast(&path_buf), mode);
}

// ── Tests ────────────────────────────────────────────────────────────────────

test "listen: returns PathTooLong when path exceeds MAX_SOCKET_PATH" {
    comptime if (!builtin.os.tag.isBSD() and builtin.os.tag != .linux)
        @compileError("listen tests require BSD or Linux");

    const long_path = "x" ** (MAX_SOCKET_PATH + 1);
    const result = listen(long_path);
    try std.testing.expectError(error.PathTooLong, result);
}

test "listen: returns DaemonAlreadyRunning when another listener is active" {
    comptime if (!builtin.os.tag.isBSD() and builtin.os.tag != .linux)
        @compileError("listen tests require BSD or Linux");

    const test_helpers = @import("testing/helpers.zig");
    const socket_path = test_helpers.generateTestSocketPath();

    // Manually create a listener to occupy the path.
    const first_fd = std.posix.socket(std.posix.AF.UNIX, std.posix.SOCK.STREAM, 0) catch
        return error.SocketCreate;
    defer std.posix.close(first_fd);

    var addr = makeAddr(socket_path);
    std.posix.bind(first_fd, @ptrCast(&addr), @sizeOf(std.posix.sockaddr.un)) catch
        return error.Bind;
    defer std.posix.unlink(socket_path) catch {};

    std.posix.listen(first_fd, 1) catch return error.Listen;

    // Second listen attempt on the same path should detect the running daemon.
    const result = listen(socket_path);
    try std.testing.expectError(error.DaemonAlreadyRunning, result);
}

test "listen: auto-unlinks stale socket and succeeds" {
    comptime if (!builtin.os.tag.isBSD() and builtin.os.tag != .linux)
        @compileError("listen tests require BSD or Linux");

    const test_helpers = @import("testing/helpers.zig");
    const socket_path = test_helpers.generateTestSocketPath();

    // Create a socket file by binding, then close without accepting.
    // This leaves a stale socket file on disk.
    const tmp_fd = std.posix.socket(std.posix.AF.UNIX, std.posix.SOCK.STREAM, 0) catch
        return error.SocketCreate;
    var addr = makeAddr(socket_path);
    std.posix.bind(tmp_fd, @ptrCast(&addr), @sizeOf(std.posix.sockaddr.un)) catch
        return error.Bind;
    // Close without unlinking -- leaves a stale socket file.
    std.posix.close(tmp_fd);

    // Per daemon-lifecycle spec, listen() should unlink the stale socket and proceed.
    var listener = try listen(socket_path);
    defer listener.deinit();

    try std.testing.expectEqualSlices(u8, socket_path, listener.socketPath());
}

test "listen: succeeds on a fresh path and returns a valid Listener" {
    comptime if (!builtin.os.tag.isBSD() and builtin.os.tag != .linux)
        @compileError("listen tests require BSD or Linux");

    const test_helpers = @import("testing/helpers.zig");
    const socket_path = test_helpers.generateTestSocketPath();

    var listener = try listen(socket_path);
    defer listener.deinit();

    try std.testing.expect(listener.fd() > 0 or listener.fd() == 0);
    try std.testing.expectEqualSlices(u8, socket_path, listener.socketPath());
}

test "Listener.fd: returns the listen file descriptor" {
    comptime if (!builtin.os.tag.isBSD() and builtin.os.tag != .linux)
        @compileError("listen tests require BSD or Linux");

    // Construct a Listener manually to test the accessor.
    const raw_fd = std.posix.socket(std.posix.AF.UNIX, std.posix.SOCK.STREAM, 0) catch
        return error.SocketCreate;

    var listener = Listener{
        .listen_fd = raw_fd,
        .socket_path_storage = undefined,
        .socket_path_length = 0,
    };
    defer std.posix.close(listener.listen_fd);

    try std.testing.expectEqual(raw_fd, listener.fd());
}

test "Listener.socketPath: returns the bound path" {
    comptime if (!builtin.os.tag.isBSD() and builtin.os.tag != .linux)
        @compileError("listen tests require BSD or Linux");

    const expected_path = "/tmp/itshell3-test.sock";
    var listener = Listener{
        .listen_fd = 0,
        .socket_path_storage = undefined,
        .socket_path_length = expected_path.len,
    };
    @memcpy(listener.socket_path_storage[0..expected_path.len], expected_path);

    try std.testing.expectEqualSlices(u8, expected_path, listener.socketPath());
}

test "Listener.close: closes fd and unlinks socket file" {
    comptime if (!builtin.os.tag.isBSD() and builtin.os.tag != .linux)
        @compileError("listen tests require BSD or Linux");

    const test_helpers = @import("testing/helpers.zig");
    const socket_path = test_helpers.generateTestSocketPath();

    // Create a real bound socket so close() has something to unlink.
    const fd = std.posix.socket(std.posix.AF.UNIX, std.posix.SOCK.STREAM, 0) catch
        return error.SocketCreate;
    var addr = makeAddr(socket_path);
    std.posix.bind(fd, @ptrCast(&addr), @sizeOf(std.posix.sockaddr.un)) catch {
        std.posix.close(fd);
        return error.Bind;
    };

    var listener = Listener{
        .listen_fd = fd,
        .socket_path_storage = undefined,
        .socket_path_length = socket_path.len,
    };
    @memcpy(listener.socket_path_storage[0..socket_path.len], socket_path);

    listener.deinit();

    // Verify socket file is removed: accessing it should fail.
    std.fs.cwd().access(socket_path, .{}) catch |err| {
        try std.testing.expectEqual(error.FileNotFound, err);
        return;
    };
    // If access succeeded, the file still exists — fail the test.
    return error.TestUnexpectedResult;
}

test "Listener.close: tolerates already-removed socket file" {
    comptime if (!builtin.os.tag.isBSD() and builtin.os.tag != .linux)
        @compileError("listen tests require BSD or Linux");

    const fd = std.posix.socket(std.posix.AF.UNIX, std.posix.SOCK.STREAM, 0) catch
        return error.SocketCreate;

    const ghost_path = "/tmp/itshell3-test-ghost-nonexistent.sock";
    var listener = Listener{
        .listen_fd = fd,
        .socket_path_storage = undefined,
        .socket_path_length = ghost_path.len,
    };
    @memcpy(listener.socket_path_storage[0..ghost_path.len], ghost_path);

    // Should not panic even though the socket file does not exist.
    listener.deinit();
}

test "listen: returns Bind when path parent is not a directory" {
    comptime if (!builtin.os.tag.isBSD() and builtin.os.tag != .linux)
        @compileError("listen tests require BSD or Linux");

    // /dev/null exists but is a device file, not a directory.
    // ensureDirectory sees PathAlreadyExists (OK), but bind fails with ENOTDIR.
    const result = listen("/dev/null/itshell3-test.sock");
    try std.testing.expectError(error.Bind, result);
}

test "listen: returns DirectoryCreate when parent path is not creatable" {
    comptime if (!builtin.os.tag.isBSD() and builtin.os.tag != .linux)
        @compileError("listen tests require BSD or Linux");

    // The parent path /nonexistent/subdir does not exist and cannot be created
    // because /nonexistent does not exist. mkdir fails with FileNotFound.
    const result = listen("/nonexistent/subdir/itshell3-test.sock");
    try std.testing.expectError(error.DirectoryCreate, result);
}

test "Listener.accept: accepts a client connection" {
    comptime if (!builtin.os.tag.isBSD() and builtin.os.tag != .linux)
        @compileError("accept tests require BSD or Linux");

    const test_helpers = @import("testing/helpers.zig");
    const socket_path = test_helpers.generateTestSocketPath();

    var listener = try listen(socket_path);
    defer listener.deinit();

    // Connect a client from another socket.
    const client_fd = helper.newFd() catch return error.SocketCreate;
    defer std.posix.close(client_fd);

    const addr = makeAddr(socket_path);
    std.posix.connect(client_fd, @ptrCast(&addr), @sizeOf(std.posix.sockaddr.un)) catch
        return error.Accept;

    // Accept should succeed with UID matching (same process).
    var conn = try listener.accept();
    defer conn.close();

    // Verify the connection works by sending/receiving data.
    _ = std.posix.write(client_fd, "hello") catch return error.Accept;
    var buf: [16]u8 = undefined;
    const result = conn.recv(&buf);
    switch (result) {
        .bytes_read => |n| try std.testing.expectEqualSlices(u8, "hello", buf[0..n]),
        else => return error.TestUnexpectedResult,
    }
}
