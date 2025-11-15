const std = @import("std");
const Allocator = std.mem.Allocator;
const assert = std.debug.assert;

const builtIns = [_][]const u8 {"cd"};

// Constant decimal values for key presses
const BACKSPACE = 127;
const CTRL_C = 3;


const COMMAND_BUF_INIT_CAP: usize = 50;
const ARG_BUF_INIT_CAP: usize = 10;

const STDOUT_BUF_SIZE: usize = 1024;
const STDIN_BUF_SIZE: usize = 50;


pub fn main() !void {

    var debug_allocator: std.heap.DebugAllocator(.{}) = .init;
    defer assert(debug_allocator.deinit() == .ok);
    const gpa = debug_allocator.allocator();

    // Initialize the terminal struct. It will be used to switch between raw and
    // cooked modes.
    var terminal = try Terminal.init();
    defer terminal.set_cooked();
    defer terminal.deinit();

    // Initialize stdout writer so we can print to screen
    var stdout_buffer: [STDOUT_BUF_SIZE]u8 = undefined;
    var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
    const stdout = &stdout_writer.interface;

    // Initialize command array list. Will be used to hold the data interpreted
    // from raw tty input
    var command_buffer = try std.ArrayList(u8).initCapacity(gpa, COMMAND_BUF_INIT_CAP);
    defer command_buffer.deinit(gpa);

    var arg_buffer = try std.ArrayList(?[*:0]u8).initCapacity(gpa, ARG_BUF_INIT_CAP);
    defer arg_buffer.deinit(gpa);

    var read_buf: [STDIN_BUF_SIZE]u8 = undefined;
    var stdin_reader = std.fs.File.stdin().reader(&read_buf);
    var reader = &stdin_reader.interface;

    const env = std.c.environ;

    while (true) {
        // When starting the loop dump old data
        command_buffer.clearRetainingCapacity();
        arg_buffer.clearRetainingCapacity();

        try stdout.print("zell>> ",.{});
        try stdout.flush();

        terminal.set_raw();
        while (true) {
            const c = try reader.takeByte();

            if (c == BACKSPACE) {
                if (command_buffer.items.len == 0) {
                    continue;
                }
                try stdout.print("\x08 \x08", .{});
                _ = command_buffer.pop();
                try stdout.flush();
                continue;
            }

            if (c == '\n') {
                try stdout.print("\n", .{});
                try stdout.flush();
                try command_buffer.append(gpa, 0);
                break;
            }

            if (c == CTRL_C) {
                command_buffer.clearRetainingCapacity();
                try stdout.print("\n", .{});
                try stdout.flush();
                break;
            }

            try command_buffer.append(gpa, c);

            try stdout.print("{c}", .{c});
            try stdout.flush();
        }
        terminal.set_cooked();

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

const Terminal = struct {
    tty_file: std.fs.File,
    raw_settings: std.os.linux.termios,
    cooked_settings: std.os.linux.termios,

    pub fn init() !Terminal {
        const tty_file = try std.fs.openFileAbsolute("/dev/tty", .{});

        var cooked_settings: std.os.linux.termios = undefined;
        _ = std.os.linux.tcgetattr(tty_file.handle, &cooked_settings);

        // Holds the raw settings listed below
        var raw_settings: std.os.linux.termios = cooked_settings;

        // In noncanonical mode input is available immediately. Essentially we
        // don't have to wait for new line characters to receive the data and we
        // can immediately receive keypresses
        raw_settings.lflag.ICANON = false;

        // Turns off echoing characters. Essentially means we are responsible
        // for writing what the user types to stdout
        raw_settings.lflag.ECHO = false;

        // When any of the characters INTR, QUIT, SUSP, or DSUSP are received
        // generate the corresponding signal. Allows us to capture these
        // commands rather than ending the program
        raw_settings.lflag.ISIG = false;

        return Terminal{
            .raw_settings = raw_settings,
            .cooked_settings = cooked_settings,
            .tty_file =  tty_file,
        };
    }

    pub fn set_raw(self: Terminal) void {
        _ = std.os.linux.tcsetattr(self.tty_file.handle, std.os.linux.TCSA.NOW, &self.raw_settings);
    }
    pub fn set_cooked(self: Terminal) void {
        _ = std.os.linux.tcsetattr(self.tty_file.handle, std.os.linux.TCSA.NOW, &self.cooked_settings);
    }

    pub fn deinit(self: Terminal) void {
        self.tty_file.close();
    }
};

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
