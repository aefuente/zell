const std = @import("std");
const Terminal = @import("terminal.zig").Terminal;

const Allocator = std.mem.Allocator;
const File = std.fs.File;
const linux = std.os.linux;
const posix = std.posix;

// HEX values for key presses
const ESC = '\x1b';
const BRACKET = '\x5b';
const UP_ARROW = '\x41';
const DOWN_ARROW = '\x42';
const RIGHT_ARROW = '\x43';
const LEFT_ARROW = '\x44';
const BACKSPACE = '\x7F';
const CTRL_C = '\x03';

const STDIN_BUF_SIZE: usize = 50;

const history_file = ".zell_history";

fn get_history_file() !File {
    if (posix.getenv("HOME")) |home |{
        const home_dir = try std.fs.openDirAbsolute(home, .{});
        home_dir.access(history_file, .{}) catch {
            return try home_dir.createFile(history_file, .{});
        };
        return home_dir.openFile(history_file, .{.mode = .read_write});
    }
    return error.MissingHomeDirectory;
}

pub const HistoryManager = struct {
    history_file: std.fs.File,
    array_list: std.ArrayList([]u8),

    pub fn init(allocator: Allocator) !HistoryManager {
        return .{
            .history_file = try get_history_file(),
            .array_list = try std.ArrayList([]u8).initCapacity(allocator, 10),
        };
    }

    pub fn store(self: *HistoryManager, allocator: Allocator, line: []u8) !void {
        var history_line = try allocator.alloc(u8, line.len);
        @memcpy(history_line[0..],line);
        try self.array_list.append(allocator, history_line);
    }

    pub fn print(self: *HistoryManager) !void {
        for (0.., self.array_list.items) |index, line| {
            std.debug.print("{d} {s}\n", .{index, line});
        }
    }

    pub fn save(self: *HistoryManager) void {
        // Create the writer
        var write_buffer: [100]u8 = undefined;
        var file_writer = std.fs.File.Writer.init(self.history_file, &write_buffer);
        const writer = &file_writer.interface;

        for (self.array_list.items) |line| {
            // Lines are 0 terminated strings. We replace them with returns
            line[line.len-1] = '\n';
            _ = writer.write(line) catch {return;};
        }

        _ =  writer.flush() catch {};
        return;
    }

    pub fn load_history(self: *HistoryManager, allocator: Allocator) !void {
        var read_buffer: [100]u8 = undefined;
        var file_reader = std.fs.File.Reader.init(self.history_file, &read_buffer);
        const reader = &file_reader.interface;

        while (true) {

            var writer = std.io.Writer.Allocating.init(allocator);
            defer writer.deinit();
            const size = reader.streamDelimiter(&writer.writer, '\n') catch {
                break;
            };
            // Stream is not inclusive so throw away the \n
            _ = try reader.takeByte();
            // We expect our strings to be 0 terminated
            try writer.writer.writeByte(0);
            const line = try writer.toOwnedSlice();
            if (size != 0) {
                try self.array_list.append(allocator, line);
            }
        }
    }

    pub fn get_suggestion(self: *HistoryManager, query: []const u8) ?[]const u8{
        var index: usize = self.array_list.items.len;
        while (index > 0) {
            index -= 1;
            const line = self.array_list.items[index];
            if (line.len >= query.len) {
                if (std.mem.eql(u8, query, line[0..query.len])) {
                    return line;
                }
            }
        }
        return null;
    }

    pub fn deinit(self: *HistoryManager, allocator: Allocator) void {
        self.history_file.close();
        for (self.array_list.items) |line| {
            allocator.free(line);
        }
        self.array_list.deinit(allocator);
    }
};

pub fn read_line(
    allocator: std.mem.Allocator,
    history: *HistoryManager,
    stdout: *std.Io.Writer,
    array_list: *std.ArrayList(u8),
    termianl: *Terminal
    ) !void {

    termianl.set_raw();
    defer termianl.set_cooked();

    // Initialize the reader for reading stdin
    var read_buf: [STDIN_BUF_SIZE]u8 = undefined;
    var stdin_reader = std.fs.File.stdin().reader(&read_buf);
    const stdin = &stdin_reader.interface;

    // Initialize the cursor position
    var cursor_position: usize = 0;

    // Decided to initialize history_position to max so we can recognize the
    // "start of history indexing".
    var history_position: usize = std.math.maxInt(usize);

    while (true) {
        // Read the character
        const c = try stdin.takeByte();

        if (c == BACKSPACE) {
            if (array_list.items.len == 0) {
                continue;
            }
            if (cursor_position == 0) {
                @panic("integer underflow");
            }

            cursor_position -= 1;
            _ = array_list.orderedRemove(cursor_position);
            try draw_line(stdout, array_list.items, cursor_position);
        }

        else if (c == '\n') {

            try stdout.print("\n", .{});
            try stdout.flush();

            var index: usize = array_list.items.len;

            // Remove white spaces
            while (index > 0) {
                index -= 1;
                const char = array_list.items[index];
                if (char != ' ' and char != '\t' and char != '\r') break;
            }

            array_list.shrinkAndFree(allocator, index+1);

            if (array_list.items.len > 0) {
                try array_list.append(allocator, 0);
            }
            break;
        }

        else if (c == CTRL_C) {
            array_list.clearRetainingCapacity();
            try stdout.print("\n", .{});
            try stdout.flush();
            break;
        }

        // Escape sequence
        else if (c == ESC){
            const code = try stdin.takeByte();
            if (code == BRACKET) {
                const next_code = try stdin.takeByte();
                switch (next_code) {
                    LEFT_ARROW => {
                        if (cursor_position == 0) {
                            continue;
                        }
                        cursor_position -= 1;
                        try draw_line(stdout, array_list.items, cursor_position);
                        continue;
                    },
                    RIGHT_ARROW => {
                        if (cursor_position + 1 > array_list.items.len) {
                            if (history.get_suggestion(array_list.items)) |suggestion| {
                                try array_list.resize(allocator, suggestion.len-1);
                                @memcpy(array_list.items, suggestion[0..suggestion.len-1]);
                                cursor_position = array_list.items.len;
                                try draw_line(stdout, array_list.items, cursor_position);
                            }
                            continue;
                        }
                        cursor_position += 1;
                        try draw_line(stdout, array_list.items, cursor_position);
                        continue;
                    },
                    UP_ARROW => {
                        // Identity if we are on the "start condition" of moving
                        // through history
                        if (history_position == std.math.maxInt(usize)) {
                            if (history.array_list.items.len == 0) {
                                history_position = 0;
                            }else {
                                history_position = history.array_list.items.len;
                            }

                        }
                        if (history_position == 0) {
                            continue;
                        }
                        history_position -= 1;
                        try array_list.resize(allocator, history.array_list.items[history_position].len);
                        @memcpy(array_list.items, history.array_list.items[history_position]);
                        cursor_position = array_list.items.len;
                        try draw_line(stdout, array_list.items, cursor_position);
                    },
                    DOWN_ARROW => {

                        if (history_position == std.math.maxInt(usize)) {
                            continue;
                        }

                        if (history_position + 1 < history.array_list.items.len) {
                            history_position += 1;
                            try array_list.resize(allocator, history.array_list.items[history_position].len);
                            @memcpy(array_list.items, history.array_list.items[history_position]);
                            cursor_position = array_list.items.len;
                            try draw_line(stdout, array_list.items, cursor_position);
                        }else {
                            history_position = std.math.maxInt(usize);
                            cursor_position = 0;
                            array_list.clearRetainingCapacity();
                            try draw_line(stdout, array_list.items, cursor_position);
                        }
                    },
                    else => { }
                }
            }
        }
        else {
            try array_list.insert(allocator, cursor_position, c);
            cursor_position +=1;
            const suggestion = history.get_suggestion(array_list.items);
            if (suggestion) |s | {
                try draw_line_suggestion(stdout, s, array_list.items, cursor_position);
            }else {
                try draw_line(stdout, array_list.items, cursor_position);
            }
        }
    }
}

fn draw_line_suggestion(writer: *std.Io.Writer, suggestion: []const u8, line: []const u8, cursor_pos: usize) !void {
    // Write our new line
    // \r -> start at column 0
    // zell>> {s} -> print our buffer 
    // \x1b[K clear what might be there from the previous write

    const suggestion_text = suggestion[line.len..];
    try writer.print("\rzell>> {s}\x1b[90m{s}\x1b[0m\x1b[K",.{line, suggestion_text});

    // Calculate where to put the cursor
    var diff: usize = 0;
    if (line.len + suggestion.len <= cursor_pos) {
        diff = 0;
    }else {
        diff = line.len - cursor_pos + suggestion_text.len - 1;
    }

    if (diff != 0) {
        // Move the cursor to the left
        try writer.print("\x1b[{d}D", .{diff});
    }
    try writer.flush();
}


fn draw_line(writer: *std.Io.Writer, line: []const u8, cursor_pos: usize) !void {
    // Write our new line
    // \r -> start at column 0
    // zell>> {s} -> print our buffer 
    // \x1b[K clear what might be there from the previous write
    try writer.print("\rzell>> {s}\x1b[K",.{line});

    // Calculate where to put the cursor
    var diff: usize = 0;
    if (line.len <= cursor_pos) {
        diff = 0;
    }else {
        diff = line.len - cursor_pos;
    }

    if (diff != 0) {
        // Move the cursor to the left
        try writer.print("\x1b[{d}D", .{diff});
    }

    try writer.flush();
}
