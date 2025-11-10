const std = @import("std");

pub fn readInputAllocating(allocator: std.mem.Allocator) ![]u8 {
    var input_buf: [1024]u8 = undefined;
    var stdinFile = std.fs.File.stdin().reader(&input_buf);
    const stdin_reader = &stdinFile.interface;

    var writer = std.Io.Writer.Allocating.init(allocator);
    defer writer.deinit();

    _ = try stdin_reader.streamDelimiter(&writer.writer, '\n');
    const line = writer.written();
    const result = try allocator.alloc(u8, line.len);
    @memcpy(result, line);
    return result;
}

pub fn readInput(buf: []u8) !usize {
    var input_buf: [100]u8 = undefined;
    var stdin = std.fs.File.stdin().reader(&input_buf);
    var reader = &stdin.interface;
    var mem_writer = std.Io.Writer.fixed(buf);
    const count = try reader.streamDelimiter(&mem_writer, '\n');
    return count;
}
