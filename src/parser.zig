const std = @import("std");
const Allocator = std.mem.Allocator;


const TokenType = enum {
    Word,
    Pipe,
    RedirOut,
    RedirIn,
    Background,
};

pub const Token = struct {
    type: TokenType,
    value: []const u8,
};

fn match_glob(pattern: []const u8, name: []const u8) bool{

    var name_index: usize = 0;
    var pattern_index: usize = 0;

    while (pattern_index < pattern.len) {
        if (pattern[pattern_index] == '*') {
            pattern_index += 1;
            if (pattern_index == pattern.len) return true;
            while (name_index < name.len) {
                if (match_glob(pattern[pattern_index..], name[name_index..])) return true;
                name_index += 1;
            }
            return false;
        }
        else {
            if (name_index >= name.len or name[name_index] != pattern[pattern_index]) return false;
            name_index += 1;
            pattern_index += 1;
        }
    }
    return name_index == name.len;
}

test "match glob" {
    try std.testing.expect(match_glob("*.txt", "file.txt"));
    try std.testing.expect(match_glob("f*.txt", "file.txt"));
    try std.testing.expect(match_glob("fi*.txt", "file.txt"));
    try std.testing.expect(match_glob("fi*", "file.txt"));
    try std.testing.expect(match_glob("fi*", "fired"));
}

fn needs_expanding(pattern: []const u8) bool{
    for (pattern) |char | {
        if (char == '*') {
            return true;
        }
    }
    return false;
}

pub fn expand_command(allocator: Allocator, word: []const u8) !?[]u8 {
    if (! needs_expanding(word)) {
        return null;
    }

    var matches = try std.ArrayList([]u8).initCapacity(allocator, 5);

    // Need to open the directory that word is pointing to... if pointing to
    // directory
    const cwd = try std.fs.cwd().openDir("./", .{.iterate= true});
    defer cwd.close();

    var iterator = cwd.iterate();
    while (try iterator.next()) | file | {
        if (match_glob(word, file.name)) {
            matches.append(allocator, file.name);
        }
    }
}

pub fn set_argv(allocator: Allocator, tokens: []Token, arg_buffer: *std.ArrayList(?[*:0]u8)) !void {
    for (tokens) |token| {
        if (token.type == TokenType.Word) {
            const cstr: ?[*:0]u8 = try std.mem.Allocator.dupeZ( allocator, u8, token.value);
            try arg_buffer.append(allocator, cstr);
        }
    }
    try arg_buffer.append(allocator, null);
}

fn in(c: u8, chars: []const u8) bool {
    for (chars) |value| {
        if (value == c) {
            return true;
        }
    }
    return false;
}

pub fn tokenize(allocator: Allocator, input: []const u8) ![]Token {
    var tokens = try std.ArrayList(Token).initCapacity(allocator, 10);
    var index: usize = 0;

    while (index < input.len) {
        const c = input[index];
        switch (c) {
            0 => {
                break;
            },
            ' ', '\t', '\n' => {
                index += 1;
                continue;
            },
            '|' => {
                try tokens.append(allocator, Token{.type = TokenType.Pipe, .value = "|"});
                index += 1;
            },
            '>' => {
                try tokens.append(allocator, Token{.type = TokenType.RedirOut, .value = ">"});
                index += 1;
            },
            '<' => {
                try tokens.append(allocator, Token{.type = TokenType.RedirIn, .value = "<"});
                index += 1;
            },
            '&' => {
                try tokens.append(allocator, Token{.type = TokenType.Background, .value = "&"});
                index += 1;
            },
            '\"' => {

                index += 1;
                const start = index;

                while (index < input.len and input[index] != '\"') : (index += 1) {}

                if (input[index] != '\"') {
                    return error.MissingCloseQuote;
                }
                try tokens.append(allocator, .{ .type = .Word, .value = input[start..index] });
                index += 1;
            },
            '\'' => {
                index += 1;
                const start = index;

                while (index < input.len-1 and input[index] != '\'') : (index += 1) {}

                if (input[index] != '\'') {
                    return error.MissingCloseQuote;
                }
                try tokens.append(allocator, .{ .type = .Word, .value = input[start..index] });
                index += 1;
            },

            else => {
                const start = index;
                while (index < input.len and ! in(input[index], " \t\n|><&")) : (index += 1) {}
                try tokens.append(allocator, .{ .type = .Word, .value = input[start..index] });
            },
        }

    }
    return try tokens.toOwnedSlice(allocator);
}

fn test_tokenizer(allocator: Allocator, input: []const u8, result: []const Token) !void {
    const output = try tokenize(allocator, input);
    defer allocator.free(output);

    if (result.len != output.len) {
        return error.TestExpectedEqual;
    }

    for (result, output) |r, o| {
        try std.testing.expectEqual(r.type, o.type);
        try std.testing.expectEqualSlices(u8, r.value, o.value);
    }
}

test "test Tokenizer" {
    const allocator = std.testing.allocator;
    try test_tokenizer(allocator, "ls", &[_]Token{.{.type = TokenType.Word, .value = "ls"}});
    try test_tokenizer(allocator, "pwd", &[_]Token{.{.type = TokenType.Word, .value = "pwd"}});
    try test_tokenizer(allocator, "whoami", &[_]Token{.{.type = TokenType.Word, .value = "whoami"}});
    try test_tokenizer(allocator, "date", &[_]Token{.{.type = TokenType.Word, .value = "date"}});

    try test_tokenizer(allocator, "echo hello", &[_]Token{
        .{.type = TokenType.Word, .value = "echo"}, 
        .{.type = TokenType.Word, .value = "hello"},
    });
    try test_tokenizer(allocator, "echo \"Hello World\"", &[_]Token{
        .{.type = TokenType.Word, .value = "echo"},
        .{.type = TokenType.Word, .value = "Hello World"},
    });
    try test_tokenizer(allocator, "cd /usr/local", &[_]Token{
        .{.type = TokenType.Word, .value = "cd"},
        .{.type = TokenType.Word, .value = "/usr/local"},
    });
    try test_tokenizer(allocator, "mkdir test_dir", &[_]Token{
        .{.type = TokenType.Word, .value = "mkdir"},
        .{.type = TokenType.Word, .value = "test_dir"},
    });
    try test_tokenizer(allocator, "rm -rf /tmp/myfile", &[_]Token{
        .{.type = TokenType.Word, .value = "rm"},
        .{.type = TokenType.Word, .value = "-rf"},
        .{.type = TokenType.Word, .value = "/tmp/myfile"},
    });
    try test_tokenizer(allocator, "touch file.txt", &[_]Token{
        .{.type = TokenType.Word, .value = "touch"},
        .{.type = TokenType.Word, .value = "file.txt"},
    });
    try test_tokenizer(allocator, "cat file.txt", &[_]Token{
        .{.type = TokenType.Word, .value = "cat"},
        .{.type = TokenType.Word, .value = "file.txt"},
    });
    try test_tokenizer(allocator, "echo \"A quoted string\"", &[_]Token{
        .{.type = TokenType.Word, .value = "echo"},
        .{.type = TokenType.Word, .value = "A quoted string"},
    });
    try test_tokenizer(allocator, "echo \'single quotes\'", &[_]Token{
        .{.type = TokenType.Word, .value = "echo"},
        .{.type = TokenType.Word, .value = "single quotes"},
    });

}



