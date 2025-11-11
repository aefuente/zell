//! By convention, root.zig is the root source file when making a library.
const stdin = @import("stdin.zig");
const parser = @import("parser.zig");

pub const readInputAllocating = stdin.readInputAllocating;
pub const readInput = stdin.readInput;
pub const parseAllocating = parser.parseAllocating;
pub const parse = parser.parse;
