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

    while (true) {
        defer _ = arena.reset(.free_all);

        var command_buffer = try std.ArrayList(u8).initCapacity(arena_allocator, COMMAND_BUF_INIT_CAP);

        // Print out the starting prompt
        try stdout.print("zell>> ",.{});
        try stdout.flush();

        try zell.read_line(arena_allocator, &history, stdout, &command_buffer, &terminal);

        if (command_buffer.items.len == 0) {
            continue;
        }

        try history.store(gpa, command_buffer.items);

        const ast = try zell.parser.parse(arena_allocator, command_buffer.items);
        ast.print();

        for (ast.pipelines.items) | pipeline| {
            for (pipeline.commands.items) | commands | {
                const command = std.mem.span(commands.argv.items[0].?);

                if (std.mem.eql(u8, command, "exit")) {
                    return;
                }
                const fork_pid = try std.posix.fork();
                if (fork_pid == 0) {
                    const result = std.posix.execvpeZ(commands.argv.items[0].?, @ptrCast(commands.argv.items), env);
                    switch (result) {
                        std.posix.ExecveError.FileNotFound => {
                            std.debug.print("zell: {s}: command not found\n", .{commands.argv.items[0].?});
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
