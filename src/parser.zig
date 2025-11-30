const std = @import("std");
const Allocator = std.mem.Allocator;

pub fn parse(allocator: Allocator, input: []const u8) !*AST {
    const tokens = try tokenize(allocator, input);

    var parser_state = ParserState{
        .tokens = tokens,
        .pos = 0,
    };

    var ast = try AST.init(allocator);

    try ast.pipelines.append(allocator, try parse_pipeline(allocator, &parser_state));

    while (parser_state.match(TokenType.Semi)) {
        parser_state.next();
        try ast.pipelines.append(allocator, try parse_pipeline(allocator, &parser_state));
    }

    return ast;
}

// AST
// GRAMMER:
// List -> pipline ( Semi Pipeline )*
// pipeline -> command (Pipe command)*
// command → (Assignment | redirect)* word? (word | redirect)*
// Assignment -> AssignmentKeyword? word=word
// redirect -> RedirIn word
//             RedirOut word
//             RedirOutApp word
pub const RedirectType = enum {
    RedirOut,
    RedirOutApp,
    RedirIn,
    RedirOutErr,
    RedirOutErrApp,
    RedirErr,
    RedirErrApp,
};

const Redirect = struct {
    redir_type: RedirectType,
    file_name: [:0]const u8,
};

const Command = struct {
    argv: std.ArrayList(?[*:0]const u8),
    redirects: std.ArrayList(Redirect),

    pub fn init(allocator: Allocator) !*Command {
        const cm = try allocator.create(Command);
        cm.argv = try std.ArrayList(?[*:0]const u8).initCapacity(allocator, 10);
        cm.redirects = try std.ArrayList(Redirect).initCapacity(allocator, 10);
        return cm;
    }
};

const AssignmentType = enum {
    Alias,
    Export,
    Local,
};

const Assignment = struct {
    assignment_type: AssignmentType,
    key: [:0]const u8,
    value: [:0]const u8,

};

pub const Pipeline = struct {
    commands: std.ArrayList(*Command),

    pub fn init(allocator: Allocator) !*Pipeline {
        const pl = try allocator.create(Pipeline);
        pl.commands = try std.ArrayList(*Command).initCapacity(allocator, 10);
        return pl;
    }
};

pub const AST = struct {
    pipelines: std.ArrayList(*Pipeline),

    pub fn init(allocator: Allocator) !*AST {
        const ln = try allocator.create(AST);
        ln.pipelines = try std.ArrayList(*Pipeline).initCapacity(allocator, 10);
        return ln;
    }

    pub fn print(self: AST) void {
        std.debug.print("AST List ({d} Piplines):\n", .{self.pipelines.items.len});
        for (self.pipelines.items) |pipeline | {
            print_pipeline(pipeline, 1);
        }
    }
};

const ParserState = struct {
    tokens: []const Token,
    pos: usize,

    pub fn match(self: *ParserState, token_type: TokenType) bool {
        if (self.pos < self.tokens.len and self.tokens[self.pos].type == token_type) {
            return true;
        }
        return false;
    }

    pub fn next(self: *ParserState) void {
        if (self.pos + 1 < self.tokens.len) {
            self.pos += 1;
        }
    }

    pub fn get(self: ParserState) !Token {
        if (self.pos >= self.tokens.len) {
            return error.OutOfBounds;
        }
        return self.tokens[self.pos];
    }

    pub fn is_redirect(self: ParserState) bool {
        if (self.pos >= self.tokens.len) {
            return false;
        }
        const token_type = self.tokens[self.pos].type;
        return token_type == TokenType.RedirIn or token_type == TokenType.RedirOut 
        or token_type == TokenType.RedirOutApp or token_type == TokenType.RedirOutErr
        or token_type == TokenType.RedirOutErrApp or token_type == TokenType.RedirErr
        or token_type == TokenType.RedirErrApp;
    }
};

fn parse_redirect(tokens: *ParserState) !Redirect{

    var rd: Redirect = undefined;
    if (tokens.is_redirect()) {
        const token = try tokens.get();
        const ttype: RedirectType =  switch (token.type) {
            TokenType.RedirIn => RedirectType.RedirIn,
            TokenType.RedirOut => RedirectType.RedirOut,
            TokenType.RedirOutApp => RedirectType.RedirOutApp,
            TokenType.RedirOutErr => RedirectType.RedirOutErr,
            TokenType.RedirOutErrApp => RedirectType.RedirOutErrApp,
            TokenType.RedirErr => RedirectType.RedirErr,
            TokenType.RedirErrApp => RedirectType.RedirErrApp,
            else => {
                unreachable;
            }

        };
        rd = Redirect{.redir_type = ttype, .file_name = token.value};
    }else  {
        return error.ExpectedRedirect;
    }

    tokens.next();

    const token = try tokens.get();

    if (! is_word(token.type)) {
        return error.ExpectedFileName;
    }
    rd.file_name = token.value;
    tokens.next();

    return rd;
}

fn is_word(token_type: TokenType) bool {
    return token_type == TokenType.WordLiteral or token_type == TokenType.Word;
}

fn parse_assignment(tokens: *ParserState) !Assignment {

    const token = tokens.get() catch {
        return error.ExpectedAssignment;
    };

    const token_span = std.mem.span(token.value);
    var assignment: Assignment = undefined;

    if (std.mem.eql(u8, token_span, "export")) {
        assignment.assignment_type = AssignmentType.Export;
        tokens.next();
    }else if (std.mem.eql(u8, token_span, "alias")) {
        assignment.assignment_type = AssignmentType.Alias;
        tokens.next();
    }else {
        if (! is_word(token.type)) {
            return error.ExpectedAssignmentKey;
        }
        assignment.assignment_type = AssignmentType.Local;
    }

    const key = tokens.get() catch {
        return error.ExpectedAssignment;
    };

    assignment.key = key.value;

    tokens.next();

    const eql = tokens.get() catch {
        return error.ExpectedAssignment;
    };

    if (eql.type != TokenType.Assignment) {
        return error.ExpectedAssignment;
    }

    tokens.next();

    const value = tokens.get() catch {
        return error.ExpectedAssignment;
    };

    assignment.key = value.value;

    return assignment;

}
 
fn parse_command(allocator: Allocator, tokens: *ParserState) !*Command{

    const token = tokens.get() catch {
        return error.ExpectedCommand;
    };

    if (! is_word(token.type)) {
        return error.ExpectedCommand;
    }

    var cm = try Command.init(allocator);

    if (token.type == TokenType.Word and needs_expanding(token.value)) {
        const expanded = try expand_command(allocator, token.value);
        try cm.argv.appendSlice(allocator, expanded);
    }else {
        try cm.argv.append(allocator, token.value);
    }

    tokens.next();

    while (tokens.match(TokenType.Word) or tokens.match(TokenType.WordLiteral) or tokens.is_redirect()) {
        if (tokens.is_redirect()) {
            try cm.redirects.append(allocator, try parse_redirect(tokens));
        }else {
            const t = try tokens.get();
            if (t.type == TokenType.Word and needs_expanding(t.value)) {
                const expanded = try expand_command(allocator, t.value);
                try cm.argv.appendSlice(allocator, expanded);
            }else {
                try cm.argv.append(allocator, t.value);
            }
            tokens.next();
        }
    }

    try cm.argv.append(allocator, null);
    return cm;
}

fn parse_pipeline(allocator: Allocator, tokens: *ParserState) !*Pipeline{
    var pl = try Pipeline.init(allocator);

    try pl.commands.append(allocator, try parse_command(allocator, tokens));

    while (tokens.match(TokenType.Pipe)) {
        tokens.next();
        try pl.commands.append(allocator, try parse_command(allocator, tokens));
    }
    return pl;

}

fn parse_list(allocator: Allocator, tokens: []Token) !*AST {

    var parser_state = ParserState{
        .tokens = tokens,
        .pos = 0,
    };
    var list = try AST.init(allocator);
    try list.pipelines.append(allocator, try parse_pipeline(allocator, &parser_state));

    while (parser_state.match(TokenType.Semi)) {
        parser_state.next();
        try list.pipelines.append(allocator, try parse_pipeline(allocator, &parser_state));
    }

    return list;
}


const TokenType = enum {
    Export,
    Assignment,
    Word,
    WordLiteral,
    Pipe,
    RedirOut,
    RedirOutApp,
    RedirIn,
    RedirOutErr,
    RedirOutErrApp,
    RedirErr,
    RedirErrApp,
    Semi,
    Background,
    End,
};

pub const Token = struct {
    type: TokenType,
    value: [:0]const u8,
};

fn toCstr(allocator: Allocator, str: []const u8) ![:0]u8 {
    var cstr: []u8 = try allocator.alloc(u8, str.len + 1);
    @memcpy(cstr[0..str.len], str);
    cstr[str.len]  = 0;
    return @ptrCast(cstr);
}

fn tokenize(allocator: Allocator, input: []const u8) ![]Token {
    var tokens = try std.ArrayList(Token).initCapacity(allocator, 10);
    var index: usize = 0;

    while (index < input.len) {
        const c = input[index];
        switch (c) {
            0, '\n' => {
                break;
            },
            ' ', '\t' => {
                index += 1;
                continue;
            },
            '|' => {
                try tokens.append(allocator, Token{.type = TokenType.Pipe, .value = "|"});
                index += 1;
            },
            ';' => {
                try tokens.append(allocator, Token{.type = TokenType.Semi, .value = ";"});
                index += 1;
            },
            '>' => {
                if (index + 1 < input.len and input[index+1] == '>') {
                    try tokens.append(allocator, Token{.type = TokenType.RedirOutApp, .value = ">>"});
                    index += 2;
                    continue;
                }
                try tokens.append(allocator, Token{.type = TokenType.RedirOut, .value = ">"});
                index += 1;
            },
            '<' => {
                try tokens.append(allocator, Token{.type = TokenType.RedirIn, .value = "<"});
                index += 1;
            },
            '&' => {
                if (index + 2 < input.len and input[index + 1] == '>' and input[index + 2] == '>') {
                    try tokens.append(allocator, Token{.type = TokenType.RedirOutErrApp, .value = "&>>"});
                    index += 3;
                    continue;
                }

                if (index + 1 < input.len and input[index+1] == '>') {
                    try tokens.append(allocator, Token{.type = TokenType.RedirOutErr, .value = "&>"});
                    index += 2;
                    continue;
                }

                try tokens.append(allocator, Token{.type = TokenType.Background, .value = "&"});
                index += 1;
            },
            '\"' => {
                index += 1;
                const start = index;

                while (index < input.len-1 and input[index] != '\"') : (index += 1) {}

                if (input[index] != '\"') {
                    return error.MissingCloseQuote;
                }
                const cstr = try toCstr(allocator, input[start..index]);
                try tokens.append(allocator, .{ .type = .Word, .value = cstr });
                index += 1;
            },
            '\'' => {
                index += 1;
                const start = index;

                while (index < input.len-1 and input[index] != '\'') : (index += 1) {}

                if (input[index] != '\'') {
                    return error.MissingCloseQuote;
                }
                const cstr = try toCstr(allocator, input[start..index]);
                try tokens.append(allocator, .{ .type = .WordLiteral, .value = cstr });
                index += 1;
            },
            '2' => {
                if (index + 2 < input.len and input[index + 1] == '>' and input[index + 2] == '>') {
                    try tokens.append(allocator, Token{.type = TokenType.RedirErrApp, .value = "2>>"});
                    index += 3;
                    continue;
                }

                if (index + 1 < input.len and input[index+1] == '>') {
                    try tokens.append(allocator, Token{.type = TokenType.RedirErr, .value = "2>"});
                    index += 2;
                    continue;
                }


                const start = index;
                index = span_word(input, index);

                const cstr = try toCstr(allocator, input[start..index]);
                try tokens.append(allocator, .{ .type = .Word, .value = cstr });
            },
            '=' => {
                try tokens.append(allocator, .{.type = .Assignment, .value = "="});
            },

            else => {
                const start = index;
                index = span_word(input, index);

                const word = input[start..index];
                var tokenType: TokenType = undefined;

                if (std.mem.eql(u8, word, "export")) {
                    tokenType = TokenType.Export;
                }else {
                    tokenType = TokenType.Word;
                }

                const cstr = try toCstr(allocator, input[start..index]);
                try tokens.append(allocator, .{ .type = tokenType, .value = cstr });
            },
        }
    }

    try tokens.append(allocator, .{.type = .End, .value = "\n"});
    return try tokens.toOwnedSlice(allocator);
}

fn span_word(input: []const u8, index: usize) usize{
    while (index < input.len and ! in(input[index], " \t\n|><&=") and input[index] != 0) : (index += 1) {}
    return index;
}


fn needs_expanding(pattern: []const u8) bool{
    for (pattern) |char | {
        if (char == '*') {
            return true;
        }
    }
    return false;
}

fn expand_command(allocator: Allocator, word: [:0]const u8) ![]?[*:0]u8 {

    var matches = try std.ArrayList(?[*:0]u8).initCapacity(allocator, 5);
    var dir_pos: usize = std.math.maxInt(usize);
    for (word, 0..) |char, index| {
        if (char == '/') {
            dir_pos = index;
        }
    }

    var dir: std.fs.Dir = undefined;
    defer dir.close();

    if (dir_pos != std.math.maxInt(usize)) {
        if (std.fs.path.isAbsolute(word[0..dir_pos])) {
            dir = try std.fs.openDirAbsolute(word[0..dir_pos], .{ .iterate = true });
        }else {
            dir = try std.fs.cwd().openDir(word[0..dir_pos], .{ .iterate = true});
        }

        const dir_name = word[0..dir_pos];

        var iterator = dir.iterate();
        while (try iterator.next()) | file | {
            const file_path = try std.fs.path.joinZ(allocator, &[_][]const u8{dir_name, file.name});
            if (match_glob(word[0..word.len-1], file_path)) {
                try matches.append(allocator, file_path);
            }
        }

    } else {
        dir = try std.fs.cwd().openDir("./", .{.iterate = true});
        var iterator = dir.iterate();
        while (try iterator.next()) | file | {
            if (match_glob(word[0..word.len-1], file.name)) {
                const file_name = try std.mem.Allocator.dupeZ(allocator, u8, file.name);
                try matches.append(allocator, file_name);
            }
        }
    }

    return try matches.toOwnedSlice(allocator);
}

fn in(c: u8, chars: []const u8) bool {
    for (chars) |value| {
        if (value == c) {
            return true;
        }
    }
    return false;
}


fn print_level(lvl: i32) void {
    var i: i32 = 0;
    while (i < lvl) : (i += 1){
        std.debug.print("  ", .{});
    }

}

fn print_redirects(rd: Redirect, level: i32) void {
    print_level(level);
    var op: []const u8 = undefined;

    if (rd.redir_type == RedirectType.In){
        op = "<";
    }
    else if (rd.redir_type == RedirectType.Out){
        op = ">";
    }
    else {
        op = ">>";
    }

    std.debug.print("Redirect: {s} {s}\n", .{op, rd.file_name});

}


fn print_command(cm: *Command, level: i32) void {
    print_level(level);
    std.debug.print("Command:\n", .{});
    print_level(level + 2);
    std.debug.print("Args: ", .{});

    for (cm.argv.items) |arg| {
        if (arg) |a | {
            std.debug.print(" {s}", .{a});
        }
    }
    std.debug.print("\n", .{});

    for (cm.redirects.items) |redir| {
        print_redirects(redir, level + 2);

    }

}

fn print_pipeline(pl: *Pipeline, level: i32) void {
    print_level(level);
    for (pl.commands.items) |cm | {
        print_command(cm, level + 1);
    }
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
    const talloc = std.testing.allocator;
    var arena = std.heap.ArenaAllocator.init(talloc);
    const allocator = arena.allocator();
    defer arena.deinit();
    try test_tokenizer(allocator, "ls\n", &[_]Token{
        .{.type = TokenType.Word, .value = "ls"},
        .{.type = TokenType.End, .value = "\n"},
    });
    try test_tokenizer(allocator, "pwd", &[_]Token{
        .{.type = TokenType.Word, .value = "pwd"},
        .{.type = TokenType.End, .value = "\n"},
    });
    try test_tokenizer(allocator, "whoami", &[_]Token{
        .{.type = TokenType.Word, .value = "whoami"},
        .{.type = TokenType.End, .value = "\n"},
    });
    try test_tokenizer(allocator, "date", &[_]Token{
        .{.type = TokenType.Word, .value = "date"},
        .{.type = TokenType.End, .value = "\n"},
    });

    try test_tokenizer(allocator, "echo hello", &[_]Token{
        .{.type = TokenType.Word, .value = "echo"}, 
        .{.type = TokenType.Word, .value = "hello"},
        .{.type = TokenType.End, .value = "\n"},
    });
    try test_tokenizer(allocator, "echo \"Hello World\"", &[_]Token{
        .{.type = TokenType.Word, .value = "echo"},
        .{.type = TokenType.Word, .value = "Hello World"},
        .{.type = TokenType.End, .value = "\n"},
    });
    try test_tokenizer(allocator, "cd /usr/local", &[_]Token{
        .{.type = TokenType.Word, .value = "cd"},
        .{.type = TokenType.Word, .value = "/usr/local"},
        .{.type = TokenType.End, .value = "\n"},
    });
    try test_tokenizer(allocator, "mkdir test_dir", &[_]Token{
        .{.type = TokenType.Word, .value = "mkdir"},
        .{.type = TokenType.Word, .value = "test_dir"},
        .{.type = TokenType.End, .value = "\n"},
    });
    try test_tokenizer(allocator, "rm -rf /tmp/myfile", &[_]Token{
        .{.type = TokenType.Word, .value = "rm"},
        .{.type = TokenType.Word, .value = "-rf"},
        .{.type = TokenType.Word, .value = "/tmp/myfile"},
        .{.type = TokenType.End, .value = "\n"},
    });
    try test_tokenizer(allocator, "touch file.txt", &[_]Token{
        .{.type = TokenType.Word, .value = "touch"},
        .{.type = TokenType.Word, .value = "file.txt"},
        .{.type = TokenType.End, .value = "\n"},
    });
    try test_tokenizer(allocator, "cat file.txt", &[_]Token{
        .{.type = TokenType.Word, .value = "cat"},
        .{.type = TokenType.Word, .value = "file.txt"},
        .{.type = TokenType.End, .value = "\n"},
    });
    try test_tokenizer(allocator, "echo \"A quoted string\"", &[_]Token{
        .{.type = TokenType.Word, .value = "echo"},
        .{.type = TokenType.Word, .value = "A quoted string"},
        .{.type = TokenType.End, .value = "\n"},
    });
    try test_tokenizer(allocator, "echo \'single quotes\'", &[_]Token{
        .{.type = TokenType.Word, .value = "echo"},
        .{.type = TokenType.Word, .value = "single quotes"},
        .{.type = TokenType.End, .value = "\n"},
    });

}





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
    try std.testing.expect(match_glob("t*t", "tt"));
    try std.testing.expect(match_glob("*.txt", ".txt"));
    try std.testing.expect(match_glob("tt*", "ttxtt"));
    try std.testing.expect(match_glob("f*.txt", "file.txt"));
    try std.testing.expect(match_glob("fi*.txt", "file.txt"));
    try std.testing.expect(match_glob("fi*", "file.txt"));
    try std.testing.expect(match_glob("fi*", "fired"));
    try std.testing.expect(!match_glob("*.txt", "txt"));
    try std.testing.expect(!match_glob("*.txt", "t"));
    try std.testing.expect(!match_glob("t*t", "ttx"));
    try std.testing.expect(!match_glob("t*t", "xtt"));
    try std.testing.expect(!match_glob("t*t", "xtxt"));
    try std.testing.expect(!match_glob("tt*", "xtt"));
    try std.testing.expect(!match_glob("tt*", "txttx"));
}
