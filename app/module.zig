//! GUI barrel for the zigbase native app.
//!
//! Re-exports every public type in `app/` so the entry point imports through
//! this module rather than reaching for sibling files directly. The tests
//! build it over ziggui's core barrel (no SDL); the executable, whose root
//! `main.zig` imports it, over `linkApp`'s app barrel.

const std = @import("std");

/// The app's window: the greeting, centered.
pub const Window = @import("window.zig").Window;

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
}
