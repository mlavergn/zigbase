const std = @import("std");
const log = std.log.scoped(.zigbase_server);
const mod = @import("zigbase");
const builtin = @import("builtin");

/// A single-threaded HTTP listener that serves the library's greeting.
///
/// One connection is handled at a time and every response closes it. That is
/// enough for a local demo, and it keeps the loop free of the concurrency a
/// shared-state server would need.
pub const Server = struct {
    const Self = @This();

    /// Buffers for one connection's request head and response.
    const connection_buffer_size = 16 * 1024;

    /// Loopback only. A demo server has no business accepting remote traffic,
    /// so this is a compile-time invariant, not something a flag can widen.
    pub const host: []const u8 = "127.0.0.1";

    /// The IANA user port range, inclusive: below it needs privileges, above it
    /// is the ephemeral range the OS hands out to outbound connections.
    pub const min_port: u16 = 1024;
    pub const max_port: u16 = 49151;

    allocator: std.mem.Allocator,
    io: std.Io,
    address: std.Io.net.IpAddress,

    /// Constructs a listener bound to `port` on the loopback address.
    ///
    /// Parameters:
    /// - `allocator`: allocator for per-request state.
    /// - `io`: IO interface used for the listening socket and its streams.
    /// - `port`: the port to bind, or null to pick one at random so several
    ///   consoles can run side by side without colliding.
    ///
    /// Return: an initialized `Server`; propagates address-parsing failures.
    pub fn init(allocator: std.mem.Allocator, io: std.Io, port: ?u16) !Self {
        return Self{
            .allocator = allocator,
            .io = io,
            .address = try std.Io.net.IpAddress.parse(host, port orelse randomPort(io)),
        };
    }

    /// Releases the listener.
    ///
    /// Parameters:
    /// - `self`: the listener to tear down.
    ///
    /// Return: nothing. The socket is owned by `run` for its duration.
    pub fn deinit(self: *Self) void {
        _ = self;
    }

    /// Binds the socket and serves connections until the process is stopped.
    ///
    /// Parameters:
    /// - `self`: the listener supplying the address and allocator.
    /// - `writer`: destination for the startup banner; flushed before serving.
    ///
    /// Return: never returns normally; propagates bind failures.
    pub fn run(self: *const Self, writer: *std.Io.Writer) !void {
        log.debug("{s}:{d} :: {s}", .{ @src().file, @src().line, @src().fn_name });

        var listener = try self.address.listen(self.io, .{});
        defer listener.deinit(self.io);

        const url = try self.allocator.print("http://{f}/", .{self.address});
        defer self.allocator.free(url);

        try writer.print("zigbase console listening on {s}\n", .{url});
        try writer.flush();

        // Only once the socket is bound, so the browser cannot beat us to it.
        self.openInBrowser(url);

        while (true) {
            const stream = listener.accept(self.io) catch |err| {
                log.err("accept failed [{t}]", .{err});
                continue;
            };
            defer stream.close(self.io);

            self.serveConnection(stream) catch |err| {
                log.err("connection failed [{t}]", .{err});
            };
        }
    }

    /// Launches the system browser against the console, best effort.
    ///
    /// A demo that makes the operator copy a URL out of the terminal has an
    /// avoidable step in it, and the port is random so there is nothing to
    /// bookmark. Failure is deliberately not fatal: a headless host has no
    /// browser to launch, and the server is perfectly usable without one.
    ///
    /// Parameters:
    /// - `self`: the listener supplying the IO interface.
    /// - `url`: the address to open.
    ///
    /// Return: nothing; launch failures are logged, not propagated.
    fn openInBrowser(self: *const Self, url: []const u8) void {
        const argv: []const []const u8 = switch (builtin.os.tag) {
            .macos => &.{ "open", url },
            .windows => &.{ "cmd", "/c", "start", "", url },
            else => &.{ "xdg-open", url },
        };

        var child = std.process.spawn(self.io, .{
            .argv = argv,
            .stdout = .ignore,
            .stderr = .ignore,
        }) catch |err| {
            log.warn("could not launch a browser for {s} [{t}]", .{ url, err });
            return;
        };

        // The launcher exits as soon as it has handed the url off; waiting reaps
        // it rather than leaving a zombie for the lifetime of the server.
        _ = child.wait(self.io) catch |err| {
            log.warn("browser launcher did not exit cleanly [{t}]", .{err});
        };
    }

    /// Serves exactly one request on `stream`, then lets the caller close it.
    ///
    /// Parameters:
    /// - `self`: the listener supplying the IO interface.
    /// - `stream`: the accepted connection.
    ///
    /// Return: nothing on success; propagates request and response failures.
    fn serveConnection(self: *const Self, stream: std.Io.net.Stream) !void {
        var read_buffer: [connection_buffer_size]u8 = undefined;
        var write_buffer: [connection_buffer_size]u8 = undefined;

        var reader = stream.reader(self.io, &read_buffer);
        var writer = stream.writer(self.io, &write_buffer);

        var http_server = std.http.Server.init(&reader.interface, &writer.interface);
        var request = http_server.receiveHead() catch |err| switch (err) {
            // A browser that opens a speculative connection and closes it is
            // routine, not an error worth reporting.
            error.HttpConnectionClosing => return,
            else => return err,
        };

        try self.handle(&request);
    }

    /// Routes one request to the greeting page or a 404.
    ///
    /// Parameters:
    /// - `self`: the listener supplying the allocator.
    /// - `request`: the received request.
    ///
    /// Return: nothing on success; propagates response failures.
    fn handle(self: *const Self, request: *std.http.Server.Request) !void {
        const path = pathOf(request.head.target);
        log.debug("{s} {s}", .{ @tagName(request.head.method), path });

        if (!std.mem.eql(u8, path, "/")) {
            return request.respond("not found\n", .{ .status = .not_found, .keep_alive = false });
        }

        return self.respondGreeting(request);
    }

    /// Renders the library's greeting as the response body.
    ///
    /// Parameters:
    /// - `self`: the listener supplying the allocator.
    /// - `request`: the request to answer.
    ///
    /// Return: nothing on success; propagates allocation and write failures.
    fn respondGreeting(self: *const Self, request: *std.http.Server.Request) !void {
        var base = try mod.Base.init(self.allocator);
        defer base.deinit();

        const message = try base.getMessage("");

        const html = try self.renderOwned(message);
        defer self.allocator.free(html);

        return request.respond(html, .{
            .keep_alive = false,
            .extra_headers = &.{
                .{ .name = "content-type", .value = "text/html; charset=utf-8" },
            },
        });
    }

    /// Wraps `message` in the demo page, transferring the result to the caller.
    ///
    /// Unlike `Base.getMessage`, which lends out a buffer it keeps, this hands
    /// over responsibility for the release: the page is built per request and
    /// there is nothing on the listener worth keeping it alive for.
    ///
    /// Parameters:
    /// - `self`: the listener supplying the allocator.
    /// - `message`: the greeting to display.
    ///
    /// Return: an HTML document the caller frees with the listener's
    /// allocator; propagates allocation failure.
    fn renderOwned(self: *const Self, message: []const u8) ![]u8 {
        return self.allocator.print(
            \\<!doctype html>
            \\<html lang="en">
            \\<head><meta charset="utf-8"><title>zigbase</title></head>
            \\<body><h1>{s}</h1></body>
            \\</html>
            \\
        , .{message});
    }

    /// Picks a port uniformly-ish from the user range.
    ///
    /// `io.random` is the seeded generator, not `randomSecure`: the port only
    /// has to be unlikely to collide, and nothing about it is a secret.
    ///
    /// Parameters:
    /// - `io`: IO interface supplying the entropy.
    ///
    /// Return: a port in `min_port...max_port`.
    fn randomPort(io: std.Io) u16 {
        var bytes: [2]u8 = undefined;
        io.random(&bytes);

        const span: u32 = @as(u32, max_port) - min_port + 1;
        const value: u32 = std.mem.readInt(u16, &bytes, .little);
        return @intCast(min_port + value % span);
    }

    /// Strips the query string from a request target.
    ///
    /// Parameters:
    /// - `target`: the raw request target.
    ///
    /// Return: the path portion, borrowed from `target`.
    fn pathOf(target: []const u8) []const u8 {
        const split = std.mem.findScalar(u8, target, '?') orelse return target;
        return target[0..split];
    }
};

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    std.testing.refAllDecls(Server);
}

test "server strips the query from a target" {
    try std.testing.expectEqualStrings("/", Server.pathOf("/"));
    try std.testing.expectEqualStrings("/", Server.pathOf("/?a=b"));
    try std.testing.expectEqualStrings("/favicon.ico", Server.pathOf("/favicon.ico"));
}

test "server renders the greeting into the page" {
    const allocator = std.testing.allocator;

    var server = try Server.init(allocator, std.testing.io, 0);
    defer server.deinit();

    const html = try server.renderOwned(mod.test_greeting);
    defer allocator.free(html);

    try std.testing.expect(std.mem.containsAtLeast(u8, html, 1, "<h1>Hello Zig</h1>"));
}

test "server defaults to a port in the user range" {
    var server = try Server.init(std.testing.allocator, std.testing.io, null);
    defer server.deinit();

    const port = server.address.getPort();
    try std.testing.expect(port >= Server.min_port);
    try std.testing.expect(port <= Server.max_port);
}

test "server binds the port it is given" {
    var server = try Server.init(std.testing.allocator, std.testing.io, 8080);
    defer server.deinit();

    try std.testing.expectEqual(@as(u16, 8080), server.address.getPort());
}
