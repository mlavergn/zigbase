//! CLI barrel for the zigbase demo executable.
//!
//! Re-exports every public type in `cli/` so the entry point imports through
//! this module rather than reaching for sibling files directly.

const std = @import("std");

/// The demo CLI's behavior: greet, and say so on stdout.
pub const Client = @import("client.zig").Client;

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
}
