const std = @import("std");
const Allocator = std.mem.Allocator;


const TokenType = enum {
    Word,
    Pipe,
    RedirOut,
    RedirIn,
    Background,
    Eof,
};

pub const Token = struct {
    type: TokenType,
    value: []const u8,
};

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
    try tokens.append(allocator, .{ .type = .Eof, .value = "" });
    return try tokens.toOwnedSlice(allocator);
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


test "tokenize" {
    const allocator = std.testing.allocator;
    const line = "ls";
    const result = try tokenize(allocator, line);
    defer allocator.free(result);
    for (result) |value | {
        std.debug.print("Token: [{any}, {s}] ", .{value.type, value.value});
    }

}

// 1. Describe the syntax
// kj
//
//
// 2. Build the tokenizer
//
// 3. Build the AST 
//
// 4. Write a recursive decent parser
//
// 5. Execution layer
