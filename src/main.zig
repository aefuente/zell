const std = @import("std");
const zell = @import("zell");
const assert = std.debug.assert;


pub fn main() !void {
 
    var buf: [1024]u8 = undefined;

    while (true) {
        const  size = try zell.readInput(&buf);

        var args_ptrs: [10:null]?[*:0]u8 = undefined;
        var i: usize = 0;
        var n: usize = 0;
        var ofs: usize = 0;
        while (i <= size) : (i += 1) {
            if (buf[i] == 0x20 or i == size) {
                buf[i] = 0;
                args_ptrs[n] = @as([*:0]u8, buf[ofs..i :0].ptr);
                n += 1;
                ofs = i + 1;
            }
        }

        args_ptrs[n] = null;

        // Fork 
        const fork_pid = try std.posix.fork();
        
        // If child
        if (fork_pid == 0) {
                const env = [_:null]?[*:0]u8{null};

            const result = std.posix.execvpeZ(args_ptrs[0].?, &args_ptrs, &env);
            std.debug.print("Result: {any}", .{result});

            return;

        // If parent
        } else {
            const wait_result = std.posix.waitpid(fork_pid, 0);
            if (wait_result.status != 0) {
                std.debug.print("Command returned {}.\n", .{wait_result.status});
            }

        }
    }
}
