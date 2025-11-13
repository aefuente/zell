const std = @import("std");

pub fn readInput(buf: []u8) !usize {
    var input_buf: [100]u8 = undefined;
    var stdin = std.fs.File.stdin().reader(&input_buf);
    var reader = &stdin.interface;
    var mem_writer = std.Io.Writer.fixed(buf);
    const count = try reader.streamDelimiter(&mem_writer, '\n');
    return count;
}
