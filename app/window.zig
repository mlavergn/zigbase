const std = @import("std");
const log = std.log.scoped(.zigbase_window);
const mod = @import("zigbase");
const ziggui = @import("ziggui");

/// The one thing the demo GUI does: greet, in a window.
///
/// Everything the window shows lives here rather than in `main`, so the view
/// tree stays reachable from the unit tests below, which build it on ziggui's
/// core barrel with no SDL.
pub const Window = struct {
    const Self = @This();

    /// The point size the greeting is drawn at.
    pub const message_size: f32 = 24;

    /// Allocator for the greeting; outlives the window.
    allocator: std.mem.Allocator,
    /// The library value that builds and owns the greeting.
    base: mod.Base,

    /// The greeting, borrowed from `base` and valid until `deinit`.
    message: []const u8 = &.{},

    /// Constructs a window holding the default greeting.
    ///
    /// - `allocator`: allocator for the greeting; must outlive the value.
    /// - Returns: an initialized `Window`; propagates allocation failure.
    pub fn init(allocator: std.mem.Allocator) !Self {
        log.debug("{s}:{d} :: {s}", .{ @src().file, @src().line, @src().fn_name });

        var self = Self{ .allocator = allocator, .base = try mod.Base.init(allocator) };
        errdefer self.base.deinit();
        self.message = try self.base.getMessage("");
        return self;
    }

    /// Releases the window and the greeting it holds.
    ///
    /// - `self`: the window to tear down.
    pub fn deinit(self: *Self) void {
        self.base.deinit();
    }

    /// Builds the window's view tree: the greeting, centered.
    ///
    /// Called by the event loop each frame, inside ziggui's build scope, so it
    /// does not trace its entry.
    /// Read-only, but `*Self` rather than `*const Self`: that is the body
    /// signature `ziggui.App.run` takes.
    ///
    /// - `self`: the window.
    /// - Returns: the view.
    pub fn body(self: *Self) ziggui.View {
        return ziggui.VStack(.{
            ziggui.Text(self.message).size(message_size),
        }).frameMaxWidth().frameMaxHeight();
    }
};

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    std.testing.refAllDecls(Window);
}

test "window shows the default greeting" {
    const allocator = std.testing.allocator;

    var window = try Window.init(allocator);
    defer window.deinit();

    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    ziggui.BuildScope.shared().begin(arena.allocator());
    defer ziggui.BuildScope.shared().end();

    const view = window.body();
    const children = view.kind.stack.children;
    try std.testing.expectEqual(1, children.len);
    try std.testing.expectEqualStrings("Hello " ++ mod.Base.default_subject, children[0].kind.text.string);
}
