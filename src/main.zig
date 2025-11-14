const std = @import("std");
const Allocator = std.mem.Allocator;
const assert = std.debug.assert;

const builtIns = [_][]const u8 {"cd"};

const Terminal = struct {
    tty_file: std.fs.File,
    active_settings: std.os.linux.termios,
    normal_settings: std.os.linux.termios,

    pub fn init() !Terminal {
        const tty_file = try std.fs.openFileAbsolute("/dev/tty", .{});

        var old_settings: std.os.linux.termios = undefined;
        _ = std.os.linux.tcgetattr(tty_file.handle, &old_settings);

        var new_settings: std.os.linux.termios = old_settings;
        new_settings.lflag.ICANON = false;
        new_settings.lflag.ECHO = false;

        return Terminal{
            .active_settings = new_settings,
            .normal_settings = old_settings,
            .tty_file =  tty_file,
        };

    }

    pub fn set_active(self: Terminal) void {
        _ = std.os.linux.tcsetattr(self.tty_file.handle, std.os.linux.TCSA.NOW, &self.active_settings);
    }
    pub fn set_normal(self: Terminal) void {
        _ = std.os.linux.tcsetattr(self.tty_file.handle, std.os.linux.TCSA.NOW, &self.normal_settings);
    }
    pub fn deinit(self: Terminal) void {
        self.tty_file.close();
    }
};

pub fn main() !void {
    var debug_allocator: std.heap.DebugAllocator(.{}) = .init;
    defer assert(debug_allocator.deinit() == .ok);
    const gpa = debug_allocator.allocator();

    var terminal = try Terminal.init();
    defer terminal.set_normal();
    defer terminal.deinit();

    var stdout_buffer: [1024]u8 = undefined;
    var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
    const stdout = &stdout_writer.interface;

    var command_buffer = try std.ArrayList(u8).initCapacity(gpa, 50);
    defer command_buffer.deinit(gpa);

    var arg_buffer = try std.ArrayList(?[*:0]u8).initCapacity(gpa, 10);
    defer arg_buffer.deinit(gpa);

    var read_buf: [100]u8 = undefined;
    var stdin_reader = std.fs.File.stdin().reader(&read_buf);
    var reader = &stdin_reader.interface;

    const env = std.c.environ;

    while (true) {
        command_buffer.clearRetainingCapacity();
        arg_buffer.clearRetainingCapacity();

        try stdout.print("zell>> ",.{});
        try stdout.flush();

        terminal.set_active();
        while (true) {
            const c = try reader.takeByte();
            if (c == '\n') {
                try stdout.print("\n", .{});
                try stdout.flush();
                try command_buffer.append(gpa, 0);
                break;
            }

            if (c == 127) {
                if (command_buffer.items.len == 0) {
                    continue;
                }
                try stdout.print("\x08 \x08", .{});
                _ = command_buffer.pop();
                try stdout.flush();
                continue;
            }

            try command_buffer.append(gpa, c);

            try stdout.print("{c}", .{c});
            try stdout.flush();
        }

        terminal.set_normal();

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
