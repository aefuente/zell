//! By convention, root.zig is the root source file when making a library.
const stdin = @import("stdin.zig");

pub const readInputAllocating = stdin.readInputAllocating;
pub const readInput = stdin.readInput;
