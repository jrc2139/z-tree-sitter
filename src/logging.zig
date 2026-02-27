//! Scoped logging module for z-tree-sitter
//!
//! Provides scoped logging with "zts_" prefix for all log messages.
//! This allows consuming applications to distinguish z-tree-sitter logs
//! from their own logs.
//!
//! Usage:
//!   const zts = @import("zts");
//!   const log = zts.logging.parser;
//!   log.info("language set", .{});
//!
//!   // Produces: info(zts_parser): language set

const std = @import("std");

/// Controls whether info/debug logs are printed.
/// Warn/err always print regardless of this flag.
pub var debug_enabled: bool = false;

fn ScopedLog(comptime scope: @Type(.enum_literal)) type {
    return struct {
        const std_log = std.log.scoped(scope);

        pub fn debug(comptime fmt: []const u8, args: anytype) void {
            if (!debug_enabled) return;
            std_log.debug(fmt, args);
        }

        pub fn info(comptime fmt: []const u8, args: anytype) void {
            if (!debug_enabled) return;
            std_log.info(fmt, args);
        }

        pub fn warn(comptime fmt: []const u8, args: anytype) void {
            std_log.warn(fmt, args);
        }

        pub fn err(comptime fmt: []const u8, args: anytype) void {
            std_log.err(fmt, args);
        }
    };
}

pub const parser = ScopedLog(.zts_parser);
pub const query = ScopedLog(.zts_query);
pub const grammars = ScopedLog(.zts_grammars);
pub const default = ScopedLog(.zts);
