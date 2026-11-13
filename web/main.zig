const std = @import("std");
const log = std.log.scoped(.zigbase_web_main);
const web = @import("module.zig");
const builtin = @import("builtin");

/// Log configuration for the executable.
pub const std_options: std.Options = .{
    .log_level = if (builtin.mode == .debug) .debug else .info,
};

/// Entry point for the zigbase web console.
///
/// Keeps the executable thin: everything the console does lives in `web.Server`
/// so it stays reachable from the unit test suite.
///
/// - `init`: process capabilities supplied by the runtime (allocator, IO, args).
/// - Returns: does not return while serving; propagates argument and bind errors.
pub fn main(init: std.process.Init) !void {
    log.debug("{s}:{d} :: {s}", .{ @src().file, @src().line, @src().fn_name });

    const args = try init.minimal.args.toSlice(init.arena.allocator());
    const port: ?u16 = if (args.len > 1) try std.fmt.parseInt(u16, args[1], 10) else null;

    var buffer: [1024]u8 = undefined;
    var stdout = std.Io.File.stdout().writerStreaming(init.io, &buffer);

    var server = try web.Server.init(init.gpa, init.io, port);
    defer server.deinit();

    try server.run(&stdout.interface);
}
