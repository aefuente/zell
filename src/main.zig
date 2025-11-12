const std = @import("std");
const zell = @import("zell");

pub fn main() !void {

    //var gpa = std.heap.DebugAllocator(.{}){};
    //const allocator = gpa.allocator();
    //const regex: zell.regex.Regex = zell.regex.compile("^exit$").?;

    while (true) {
        var buf: [1024]u8 = undefined;
        const size = try zell.readInput(&buf);
        std.debug.print("line: {s}\n", .{buf[0..size]});

        const fork_pid = try std.posix.fork();

        if (fork_pid == 0) {

            return;

        } else {
            const wait_result = std.posix.waitpid(fork_pid, 0);
            if (wait_result.status != 0) {
                std.debug.print("Command returned {}.\n", .{wait_result.status});
            }

        }

    }


}
