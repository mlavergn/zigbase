const std = @import("std");
const log = std.log.scoped(.zigbase_app_main);
const gui = @import("module.zig");
const config = @import("config");
const ziggui = @import("ziggui");
const builtin = @import("builtin");

/// Log configuration for the executable.
pub const std_options: std.Options = .{
    .log_level = if (builtin.mode == .debug) .debug else .warn,
};

/// Entry point for the zigbase native app.
///
/// Keeps the executable thin: everything the window shows lives in
/// `gui.Window` so it stays reachable from the unit test suite. This is the
/// only file that touches SDL (`ziggui.App`).
///
/// - `init`: process capabilities supplied by the runtime (allocator, IO, args).
/// - Returns: nothing once the window closes; propagates allocation and
///   window-system failures.
pub fn main(init: std.process.Init) !void {
    log.debug("{s}:{d} :: {s}", .{ @src().file, @src().line, @src().fn_name });

    var window = try gui.Window.init(init.gpa);
    defer window.deinit();

    try ziggui.App.shared().run(init.gpa, gui.Window, &window, .{
        .title = config.app_name,
        .width = 480,
        .height = 320,
    }, gui.Window.body, null);
}
