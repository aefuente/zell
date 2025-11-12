const std = @import("std");

fn sliceToZeroTerminated(allocator: std.mem.Allocator, arg: []const u8) ![*:0]const u8 {
    var buf = try allocator.alloc(u8, arg.len + 1);
    std.mem.copyForwards(u8, buf, arg);
    buf[arg.len] = 0;
    return @ptrCast(buf.ptr);
}

pub fn parseAllocating(allocator: std.mem.Allocator, line: []const u8) ![*:null]?[*:0]const u8 {
    var result = try std.ArrayList(?[*:0]const u8).initCapacity(allocator, 10);

    var position: usize = 0;
    while (position < line.len) {
        const start_it = position;
        while (position < line.len and line[position] != ' ') {
            position += 1;
        }
        const slice = try sliceToZeroTerminated(allocator, line[start_it..position]);

        try result.append(allocator,slice);
        position +=1;
    }
    try result.append(allocator, null);
    const slice = try result.toOwnedSlice(allocator);
    return @ptrCast(slice.ptr);

}

pub fn parseAlloc(line: []u8) ![*:null]?[*:0]const u8 {
        var args_ptrs: [20:null]?[*:0]u8 = undefined;

        // Split by a single space. Turn spaces and the final LF into null bytes
        var i: usize = 0;
        var n: usize = 0;
        var ofs: usize = 0;
        while (i <= line.len) : (i += 1) {
            if (line[i] == 0x20 or line[i] == 0xa) {
                line[i] = 0; // turn space or line feed into null byte as sentinel
                args_ptrs[n] = @ptrCast(&line[ofs..i :0]);
                n += 1;
                ofs = i + 1;
            }
        }
        args_ptrs[n] = null;
        return &args_ptrs;
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
