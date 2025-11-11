const std = @import("std");

pub fn parseAllocating(allocator: std.mem.Allocator, line: []const u8) ![][]const u8 {
    var result = try std.ArrayList([]const u8).initCapacity(allocator, 10);
    var position: usize = 0;
    while (position < line.len) {
        const start_it = position;
        while (position < line.len and line[position] != ' ') {
            position += 1;
        }
        try result.append(allocator,line[start_it..position]);
        position +=1;
    }
    return try result.toOwnedSlice(allocator);
}

pub fn parse(line: []const u8, buf: [][]const u8) !usize {
    var index: usize = 0;
    var position: usize = 0;
    while (position < line.len) {
        const start_it = position;
        while (position < line.len and line[position] != ' ') {
            position += 1;
        }
        if (index >= buf.len) {
            @panic("index out of bounds");
        }
        buf[index] = line[start_it..position];
        index += 1;
        position +=1;
    }
    return index;
}


test "test Parse" {
    const allocator = std.testing.allocator;
    const result = try parse(allocator, "what is this");
    defer allocator.free(result);
    for (result) |value| {
        std.debug.print("{s}\n", .{value});
    }
}
