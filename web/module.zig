//! Web barrel for the zigbase console executable.
//!
//! Re-exports every public type in `web/` so the entry point imports through
//! this module rather than reaching for sibling files directly.

const std = @import("std");

pub const Server = @import("server.zig").Server;

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
}
