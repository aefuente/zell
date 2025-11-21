const std = @import("std");
const zell = @import("zell");
const Allocator = std.mem.Allocator;
const assert = std.debug.assert;

const builtIns = [_][]const u8 {"cd"};

const COMMAND_BUF_INIT_CAP: usize = 50;
const ARG_BUF_INIT_CAP: usize = 10;

const STDOUT_BUF_SIZE: usize = 1024;


pub fn main() !void {

    var debug_allocator: std.heap.DebugAllocator(.{}) = .init;
    defer assert(debug_allocator.deinit() == .ok);
    const gpa = debug_allocator.allocator();


    var arena = std.heap.ArenaAllocator.init(gpa);
    const arena_allocator = arena.allocator();
    defer arena.deinit();


    // Initialize the terminal struct. It will be used to switch between raw and
    // cooked modes.
    var terminal = try zell.Terminal.init();
    defer terminal.set_cooked();
    defer terminal.deinit();


    // Initialize stdout writer so we can print to screen
    var stdout_buffer: [STDOUT_BUF_SIZE]u8 = undefined;
    var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
    const stdout = &stdout_writer.interface;



    var history = try zell.HistoryManager.init(gpa);
    try history.load_history(gpa);

    defer history.deinit(gpa);
    defer history.save();

    const env = std.c.environ;

    // Initialize command array list. Will be used to hold the data interpreted
    // from raw tty input
    //
    var command_buffer = try std.ArrayList(u8).initCapacity(gpa, COMMAND_BUF_INIT_CAP);
    defer command_buffer.deinit(gpa);

    while (true) {

        command_buffer.clearRetainingCapacity();

        var arg_buffer = try std.ArrayList(?[*:0]u8).initCapacity(arena_allocator, ARG_BUF_INIT_CAP);

        // Print out the starting prompt
        try stdout.print("zell>> ",.{});
        try stdout.flush();

        try zell.read_line(gpa, &history, stdout, &command_buffer, &terminal);

        if (command_buffer.items.len == 0) {
            continue;
        }

        try history.store(gpa, command_buffer.items);

        const tokens = try zell.parser.tokenize(arena_allocator, command_buffer.items);
        try zell.parser.set_argv(arena_allocator, tokens, &arg_buffer);


        const command = std.mem.span(arg_buffer.items[0].?);

        if (command.len == 0) {
            continue;
        }

        if (std.mem.eql(u8, command, "exit")) {
            return;
        }

        if (std.mem.eql(u8, command, "history")) {
            try history.print();
            continue;
        }

        if (is_builtin(command)) {
            try run_builtin(command, @ptrCast(arg_buffer.items));
            continue;
        }

        const fork_pid = try std.posix.fork();
        if (fork_pid == 0) {
            const result = std.posix.execvpeZ(arg_buffer.items[0].?, @ptrCast(arg_buffer.items), env);
            switch (result) {
                std.posix.ExecveError.FileNotFound => {
                    std.debug.print("zell: {s}: command not found\n", .{command});
                },
                else => {
                    std.debug.print("Result: {any}\n", .{result});
                },
            }

            return;
        } else {
            const wait_result = std.posix.waitpid(fork_pid, 0);
            if (wait_result.status != 0) {
                std.debug.print("Command returned {}.\n", .{wait_result.status});
            }
        }
        _ = arena.reset(.free_all);
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
