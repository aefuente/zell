const std = @import("std");
const Allocator = std.mem.Allocator;
const assert = std.debug.assert;

const builtIns = [_][]const u8 {"cd"};


pub fn main() !void {
    var debug_allocator: std.heap.DebugAllocator(.{}) = .init;
    defer assert(debug_allocator.deinit() == .ok);
    const gpa = debug_allocator.allocator();


    var stdout_buffer: [1024]u8 = undefined;
    var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
    const stdout = &stdout_writer.interface;

    var write_buffer = try std.ArrayList(u8).initCapacity(gpa, 50);
    defer write_buffer.deinit(gpa);

    var arg_buffer = try std.ArrayList(?[*:0]u8).initCapacity(gpa, 10);
    defer arg_buffer.deinit(gpa);

    const env = std.c.environ;

    while (true) {
        write_buffer.clearRetainingCapacity();
        arg_buffer.clearRetainingCapacity();
        try stdout.print("zell>> ",.{});
        try stdout.flush();

        const size = try read_stdin(gpa, &write_buffer);

        var i: usize = 0;
        var n: usize = 0;
        var ofs: usize = 0;
        while (i <= size) : (i += 1) {
            if (write_buffer.items[i] == 0x20 or i == size) {
                write_buffer.items[i] = 0;
                try arg_buffer.append(gpa, @as([*:0]u8, write_buffer.items[ofs..i :0].ptr));
                n += 1;
                ofs = i + 1;
            }
        }

        try arg_buffer.append(gpa, null);

        const command = std.mem.span(arg_buffer.items[0].?);

        if (command.len == 0) {
            continue;
        }

        if (std.mem.eql(u8, command, "exit")) {
            return;
        }

        if (is_builtin(command)) {
            try run_builtin(command, @ptrCast(arg_buffer.items));
            continue;
        }

        const fork_pid = try std.posix.fork();
        if (fork_pid == 0) {
            const result = std.posix.execvpeZ(arg_buffer.items[0].?, @ptrCast(arg_buffer.items), env);
            std.debug.print("Result: {any}\n", .{result});

            return;
        } else {
            const wait_result = std.posix.waitpid(fork_pid, 0);
            if (wait_result.status != 0) {
                std.debug.print("Command returned {}.\n", .{wait_result.status});
            }
        }
    }
}

pub fn read_stdin(allocator: Allocator, array_list: *std.ArrayList(u8)) !usize {
    var input_buf: [20]u8 = undefined;
    var stdin = std.fs.File.stdin().reader(&input_buf);
    var reader = &stdin.interface;

    var allocating_writer = std.Io.Writer.Allocating.fromArrayList(allocator, array_list);
    const count = try reader.streamDelimiter(&allocating_writer.writer, '\n');
    array_list.* = allocating_writer.toArrayList();
    try array_list.append(allocator, 0);
    return count;
}


fn is_builtin(command: []const u8) bool {
    for (builtIns) |builtin| {
        if (std.mem.eql(u8, builtin, command)) {
            return true;
        }
    }
    return false;
}

fn run_builtin(command: []const u8, args: [:null]const?[*:0]const u8) !void {
    if (std.mem.eql(u8, command, "cd")) {
        std.posix.chdirZ(args[1].?) catch | err | {
            std.debug.print("{any}\n", .{err});
        };
    }
}
