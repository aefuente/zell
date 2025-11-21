//! By convention, root.zig is the root source file when making a library.
const std = @import("std");
const posix = std.posix;

pub const Terminal = @import("terminal.zig").Terminal;
pub const HistoryManager = @import("io.zig").HistoryManager;
pub const read_line = @import("io.zig").read_line;

