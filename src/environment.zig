const std = @import("std");
const Allocator = std.mem.Allocator;

fn toCstr(allocator: Allocator, str: []const u8) ![]u8 {
    var c_str = try allocator.alloc(u8, str.len+1);
    @memcpy(c_str[0..str.len], str);
    c_str[str.len] = 0;
    return c_str;
}

pub const Environment = struct {
    vars: std.ArrayList(*EnvironmentVariable),

    pub fn init(allocator: Allocator) !Environment {
        return Environment{
            .vars = try std.ArrayList(*EnvironmentVariable).initCapacity(allocator, 10)
        };
    }

    pub fn get(self: Environment, name: []const u8) ?[]const u8 {
        for (self.vars.items)  |variable| {
            if (std.mem.eql(u8, variable.name, name)) {
                return variable.value;
            }
        }
        return null;
    }

    pub fn set(self: *Environment, allocator: Allocator, name: [:0]const u8, value: [:0]const u8, flags: VariableFlags) !void {
        const norm_name = std.mem.span(name.ptr);
        for (self.vars.items, 0..) |variable, idx| {
            if (std.mem.eql(u8, norm_name, variable.name)) {
                variable.deinit(allocator);
                self.vars.items[idx] = try EnvironmentVariable.init(allocator, name, value, flags);
                return;
            }
        }
        const new_var = try EnvironmentVariable.init(allocator, name, value, flags);
        try self.vars.append(allocator, new_var);
    }

    pub fn loadDefaults(self: *Environment, allocator: Allocator) !void {

        var user = try getPasswd(allocator);
        defer user.deinit(allocator);

        const home = [_]u8{'H', 'O', 'M', 'E', 0};
        const c_dir = try toCstr(allocator, user.home);
        defer allocator.free(c_dir);

        try self.set(allocator, @ptrCast(&home), @ptrCast(c_dir), .{ .exp = true });

        const user_key = [_]u8{'U', 'S', 'E', 'R', 0};
        const c_user = try toCstr(allocator, user.username);
        defer allocator.free(c_user);

        try self.set(allocator, @ptrCast(&user_key), @ptrCast(c_user), .{ .exp = true });

        const path_key = [_]u8{'P', 'A', 'T', 'H', 0};
        const c_path = try toCstr(allocator, "/usr/local/bin:/usr/bin");
        defer allocator.free(c_path);
        try self.set(allocator, @ptrCast(&path_key), @ptrCast(c_path), .{ .exp = true });

    }

    pub fn get_env(self: *Environment, allocator: Allocator) ![*:null]?[*:0]u8{
        var result = try std.ArrayList(?[*:0]const u8).initCapacity(allocator, 5);
        for (self.vars.items) |env_var | {
            if (env_var.flags.exp == true) {
                const pair = try std.fmt.allocPrintSentinel(allocator, "{s}={s}", .{env_var.name, env_var.value}, 0);
                try result.append(allocator, pair);
            }
        }
        return @ptrCast(try result.toOwnedSliceSentinel(allocator, null));
    }

    pub fn deinit(self: *Environment, allocator: Allocator) void {
        for (self.vars.items) |v| {
            v.deinit(allocator);
        }
        self.vars.deinit(allocator);
    }
};

const passwd = struct {
    line: []const u8,
    username: []const u8,
    password: []const u8,
    uid: u32,
    gid: u32,
    rname: []const u8,
    home: []const u8,
    shell: []const u8,

    fn deinit(self: *passwd, allocator: Allocator) void {
        allocator.free(self.line);
    }
};

fn splitPasswd(allocator: Allocator, tmp_line: []const u8) !passwd {
    var start: usize = 0;
    var fields: [7][]const u8 = undefined;

    var fields_index: usize = 0;

    const line = try allocator.dupe(u8, tmp_line);

    for (line, 0..) |c, idx| {
        if (c == ':' or c == '\n') {

            if (fields_index >= fields.len) {
                return error.BadFieldCount;
            }

            fields[fields_index] = line[start..idx];
            fields_index += 1;
            start = idx+1;
        }
    }

    if (fields_index != 7) {
        return error.BadFieldCount;
    }

    return passwd{
        .line = line,
        .username = fields[0],
        .password  = fields[1],
        .uid = try std.fmt.parseInt(u32, fields[2], 10),
        .gid = try std.fmt.parseInt(u32, fields[3], 10),
        .rname  = fields[4],
        .home = fields[5],
        .shell = fields[6],
    };
}

pub fn getPasswd(allocator: Allocator) !passwd {
    const uid = std.posix.getuid();

    var read_buffer: [100]u8 = undefined;
    const passwd_file = try std.fs.openFileAbsolute("/etc/passwd", .{.mode = .read_only});
    var passwd_reader = passwd_file.reader(&read_buffer);
    var reader = &passwd_reader.interface;

    while (true) {
        const line = try reader.takeDelimiterInclusive('\n');
        var pas = try splitPasswd(allocator, line);
        if (pas.uid == uid) {
            return pas;
        }else {
            pas.deinit(allocator);
        }
    }
    return error.NotFound;
}

const VariableFlags = struct {
    exp: bool = false,
    alias: bool = false,
};

// What does a variable look like?
const EnvironmentVariable = struct {
    name: []const u8,
    value: []const u8,
    flags: VariableFlags,

    pub fn init(allocator: Allocator, name: [:0]const u8, value: [:0]const u8, flags: VariableFlags) !*EnvironmentVariable {
        var env_var = try allocator.create(EnvironmentVariable);
        env_var.name = try allocator.dupe(u8, name[0..name.len-1]);
        env_var.value = try allocator.dupe(u8, value[0..value.len-1]);
        env_var.flags = flags;

        return env_var;
    }

    pub fn deinit(self: *EnvironmentVariable, allocator: Allocator) void {
        allocator.free(self.name);
        allocator.free(self.value);
        allocator.destroy(self);
    }
};
