const std = @import("std");
const zell = @import("zell");

pub fn main() !void {
    while (true) {
        var buf: [1024]u8 = undefined;
        var commands: [50][]const u8 = undefined;
        const size = try zell.readInput(&buf);
        std.debug.print("You entered: '{s}'\n", .{ buf[0..size] });
        _ = try zell.parse(buf[0..size], &commands);
        if (std.mem.eql(u8, commands[0], "exit")) {
            return;
        }
    }
}
