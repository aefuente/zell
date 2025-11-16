//! By convention, root.zig is the root source file when making a library.
const std = @import("std");

// Constant decimal values for key presses
const ESC = '\x1b';
const BRACKET = '\x5b';
const UP_ARROW = '\x41';
const DOWN_ARROW = '\x42';
const RIGHT_ARROW = '\x43';
const LEFT_ARROW = '\x44';
const BACKSPACE = 127;
const CTRL_C = 3;


const STDOUT_BUF_SIZE: usize = 1024;
const STDIN_BUF_SIZE: usize = 50;


pub const Terminal = struct {
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

pub fn read_line(
    allocator: std.mem.Allocator,
    array_list: *std.ArrayList(u8),
    termianl: *Terminal
    ) !void {

    termianl.set_raw();
    defer termianl.set_cooked();
    // Initialize stdout writer so we can print to screen
    var stdout_buffer: [STDOUT_BUF_SIZE]u8 = undefined;
    var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
    const stdout = &stdout_writer.interface;

    try stdout.print("zell>> ",.{});
    try stdout.flush();

    var read_buf: [STDIN_BUF_SIZE]u8 = undefined;
    var stdin_reader = std.fs.File.stdin().reader(&read_buf);
    const stdin = &stdin_reader.interface;

    while (true) {
        const c = try stdin.takeByte();

        if (c == BACKSPACE) {
            if (array_list.items.len == 0) {
                continue;
            }
            try stdout.print("\x08 \x08", .{});
            _ = array_list.pop();
            try stdout.flush();
            continue;
        }

        if (c == '\n') {
            try stdout.print("\n", .{});
            try stdout.flush();
            try array_list.append(allocator, 0);
            break;
        }

        if (c == CTRL_C) {
            array_list.clearRetainingCapacity();
            try stdout.print("\n", .{});
            try stdout.flush();
            break;
        }

        if (c == ESC){
            const code = try stdin.takeByte();
            if (code == BRACKET) {
                const next_code = try stdin.takeByte();
                switch (next_code) {
                    // Modify current line
                    LEFT_ARROW => {
                        continue;
                    },
                    // Modify current line
                    RIGHT_ARROW => {
                        continue;
                    },
                    // Backwards in history
                    UP_ARROW => {
                        continue;
                    },
                    // Forfwards in history
                    DOWN_ARROW => {
                        continue;
                    },
                    else => { }
                }
            }
        }
        try array_list.append(allocator, c);
        try stdout.print("{c}", .{c});
        //try stdout.print("{c}", .{c});
        try stdout.flush();
    }

}
