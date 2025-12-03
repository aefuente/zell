const std = @import("std");
const Allocator = std.mem.Allocator;

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

test "environment" {
    const allocator = std.testing.allocator;
    var env = try Environment.init(allocator);
    defer env.deinit(allocator);
    try std.testing.expect(env.get("some") == null);
    try env.set(allocator, "key", "value", .{});
    try std.testing.expectEqualSlices(u8, env.get("key").?, "value");
}
