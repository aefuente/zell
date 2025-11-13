const std = @import("std");
const zell = @import("zell");

const builtIns = [_][]const u8 {"cd"};

const ARGS_MAX_SIZE: usize = 10;
const MAX_INPUT_SIZE: usize = 1024;

fn isBuiltin(command: []const u8) bool {
    for (builtIns) |builtin| {
        if (std.mem.eql(u8, builtin, command)) {
            return true;
        }
    }
    return false;
}

fn runBuiltin(command: []const u8, args: [:null]const?[*:0]const u8) !void {
    if (std.mem.eql(u8, command, "cd")) {
        std.posix.chdirZ(args[1].?) catch | err | {
            std.debug.print("{any}\n", .{err});
        };
    }
}

pub fn main() !void {
    var buf: [MAX_INPUT_SIZE]u8 = undefined;

    const env = std.c.environ;

    while (true) {
        const  size = try zell.readInput(&buf);

        var failedInput = false;
        var args_ptrs: [ARGS_MAX_SIZE:null]?[*:0]u8 = undefined;
        var i: usize = 0;
        var n: usize = 0;
        var ofs: usize = 0;
        while (i <= size) : (i += 1) {
            if (i >= MAX_INPUT_SIZE) {
                std.debug.print("error input too large\n", .{});
                failedInput = true;
                break;
            }
            if (n >= ARGS_MAX_SIZE) {
                std.debug.print("error too many arguments\n", .{});
                failedInput = true;
                break;
            }
            if (buf[i] == 0x20 or i == size) {
                buf[i] = 0;
                args_ptrs[n] = @as([*:0]u8, buf[ofs..i :0].ptr);
                n += 1;
                ofs = i + 1;
            }
        }

        if (failedInput) {
            continue;
        }

        args_ptrs[n] = null;

        const command = std.mem.span(args_ptrs[0].?);

        if (command.len == 0) {
            continue;
        }

        if (std.mem.eql(u8, command, "exit")) {
            return;
        }

        if (isBuiltin(command)) {
            try runBuiltin(command, &args_ptrs);
            continue;
        }

        const fork_pid = try std.posix.fork();
        if (fork_pid == 0) {
            const result = std.posix.execvpeZ(args_ptrs[0].?, &args_ptrs, env);
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
