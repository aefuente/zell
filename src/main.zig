const std = @import("std");
const zell = @import("zell");
const assert = std.debug.assert;

// pub fn execvpeZ( file: [*:0]const u8, argv_ptr: [*:null]const ?[*:0]const u8, envp: [*:null]const ?[*:0]const u8, ) ExecveError
const Command  = struct {
    file: [*:0]const u8,
    argv_ptr: [*:null]const ?[*:0]const u8,
    env: [*:null]const ?[*:0]const u8,

};


fn create_command(allocator: std.mem.Allocator, line: []const u8) !Command{

    var split_it = std.mem.splitSequence(u8, line, " ");
    const first = split_it.first();

    var file = try allocator.alloc(u8, first.len + 1);
    std.mem.copyForwards(u8, file, first);
    file[first.len] = 0;

    var args = try std.ArrayList(?[*:0]const u8).initCapacity(allocator, 10);

    _ = split_it.next();
    while (split_it.next()) |arg | {
        var alarg = try allocator.alloc(u8, arg.len + 1);
        std.mem.copyForwards(u8, alarg, arg);
        alarg[arg.len] = 0;
        try args.append(allocator, @ptrCast(alarg.ptr));
    }

    const argv_ptr = try args.toOwnedSliceSentinel(allocator, null);


    return Command{
        .file = @ptrCast(file.ptr),
        .argv_ptr = @ptrCast(argv_ptr.ptr),
        .env = &[_:null]?[*:0]u8{null},
    };
}

pub fn main() !void {

    var debug_allocator: std.heap.DebugAllocator(.{}) = .init;
    defer assert(debug_allocator.deinit() == .ok);
    const gpa = debug_allocator.allocator();


    while (true) {

        const stdin = std.fs.File.stdin();
        var stdin_read_buf: [100]u8 = undefined;
        var stdin_reader = stdin.reader(&stdin_read_buf);
        const reader = &stdin_reader.interface;

        var writer = std.Io.Writer.Allocating.init(gpa);
        defer writer.deinit();

        _ = try reader.streamDelimiter(&writer.writer, '\n');

        const line = writer.written();
        std.debug.print("line: {s}\n", .{line});

        const command = try create_command(gpa, line);
        std.debug.print("command: {any}\n", .{command});

        // Parse/format the input for  the input
        
        // Fork 
        const fork_pid = try std.posix.fork();
        
        // If child
        if (fork_pid == 0) {

            const result = std.posix.execvpeZ(command.file, command.argv_ptr, command.env);
            std.debug.print("Result: {any}", .{result});
        // pub fn execvpeZ( file: [*:0]const u8, argv_ptr: [*:null]const ?[*:0]const u8, envp: [*:null]const ?[*:0]const u8, ) ExecveError

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
