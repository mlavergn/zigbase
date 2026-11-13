const std = @import("std");
const log = std.log.scoped(.zigbase_cli_main);
const cli = @import("module.zig");
const builtin = @import("builtin");

/// Log configuration for the executable.
pub const std_options: std.Options = .{
    .log_level = if (builtin.mode == .debug) .debug else .warn,
};

/// Entry point for the zigbase demo CLI.
///
/// Keeps the executable thin: everything the CLI does lives in `cli.Client`
/// so it stays reachable from the unit test suite.
///
/// - `init`: process capabilities supplied by the runtime (allocator, IO, args).
/// - Returns: nothing on success; propagates whatever the client failed with.
pub fn main(init: std.process.Init) !void {
    log.debug("{s}:{d} :: {s}", .{ @src().file, @src().line, @src().fn_name });

    const args = try init.minimal.args.toSlice(init.arena.allocator());

    var buffer: [1024]u8 = undefined;
    var stdout = std.Io.File.stdout().writerStreaming(init.io, &buffer);

    var client = try cli.Client.init(init.gpa, init.io);
    defer client.deinit();

    try client.run(&stdout.interface, args);
}
