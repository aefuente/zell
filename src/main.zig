const std = @import("std");
const zell = @import("zell");
const Allocator = std.mem.Allocator;
const assert = std.debug.assert;

const builtIns = [_][]const u8 {"cd"};

const COMMAND_BUF_INIT_CAP: usize = 50;
const ARG_BUF_INIT_CAP: usize = 10;



pub fn main() !void {

    var debug_allocator: std.heap.DebugAllocator(.{}) = .init;
    defer assert(debug_allocator.deinit() == .ok);
    const gpa = debug_allocator.allocator();

    // Initialize the terminal struct. It will be used to switch between raw and
    // cooked modes.
    var terminal = try zell.Terminal.init();
    defer terminal.set_cooked();
    defer terminal.deinit();


    // Initialize command array list. Will be used to hold the data interpreted
    // from raw tty input
    var command_buffer = try std.ArrayList(u8).initCapacity(gpa, COMMAND_BUF_INIT_CAP);
    defer command_buffer.deinit(gpa);

    var arg_buffer = try std.ArrayList(?[*:0]u8).initCapacity(gpa, ARG_BUF_INIT_CAP);
    defer arg_buffer.deinit(gpa);


    const env = std.c.environ;

    while (true) {
        // When starting the loop dump old data
        command_buffer.clearRetainingCapacity();
        arg_buffer.clearRetainingCapacity();

        try zell.read_line(gpa, &command_buffer, &terminal);

        if (command_buffer.items.len == 0) {
            continue;
        }

        var i: usize = 0;
        var n: usize = 0;
        var ofs: usize = 0;
        while (i <= command_buffer.items.len-1) : (i += 1) {
            if (command_buffer.items[i] == 0x20 or i == command_buffer.items.len-1) {
                command_buffer.items[i] = 0;
                try arg_buffer.append(gpa, @as([*:0]u8, command_buffer.items[ofs..i :0].ptr));
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
