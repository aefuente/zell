const std = @import("std");
const zell = @import("zell");
const Allocator = std.mem.Allocator;
const assert = std.debug.assert;

const COMMAND_BUF_INIT_CAP: usize = 50;
const ARG_BUF_INIT_CAP: usize = 10;

const STDOUT_BUF_SIZE: usize = 1024;


pub fn main() !u8 {

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

    var environment = try zell.environment.Environment.init(gpa);
    defer environment.deinit(gpa);
    try environment.loadDefaults(gpa);

    while (true) {
        defer _ = arena.reset(.free_all);

        var command_buffer = try std.ArrayList(u8).initCapacity(arena_allocator, COMMAND_BUF_INIT_CAP);

        try stdout.print("zell>> ",.{});
        try stdout.flush();

        try zell.read_line(arena_allocator, &history, stdout, &command_buffer, &terminal);

        if (command_buffer.items.len == 0) {
            continue;
        }

        try history.store(gpa, command_buffer.items);

        const ast = try zell.parser.parse(arena_allocator, command_buffer.items, environment);

        zell.eval.run(gpa, arena_allocator, ast, &environment) catch |err| {
            switch (err) {
                error.ExitingShell => {
                    return 0;
                },
                else => {
                    return 1;
                }
            }
        };
    }
}

