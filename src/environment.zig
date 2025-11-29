const std = @import("std");
const Allocator = std.mem.Allocator;

const Environment = struct {
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

    pub fn set(self: *Environment, allocator: Allocator, name: []const u8, value: []const u8, flags: VariableFlags) !void {
        for (self.vars.items, 0..) |variable, idx| {
            const eql = std.mem.eql(u8, name, variable.name);
            if (eql and variable.flags.mutable == true) {
                variable.deinit(allocator);
                self.vars.items[idx] = try EnvironmentVariable.init(allocator, name, value, flags);
                return;
            } else if (eql and variable.flags.mutable == false) {
                return error.ImmutableVariable;
            }
        }
        const new_var = try EnvironmentVariable.init(allocator, name, value, flags);
        try self.vars.append(allocator, new_var);
    }

    pub fn deinit(self: *Environment, allocator: Allocator) void {
        for (self.vars.items) |v| {
            v.deinit(allocator);
        }
        self.vars.deinit(allocator);
    }

};

const VariableFlags = struct {
    mutable: bool = false,
    // Use for exporting environment variables
    exp: bool = false,
};

// What does a variable look like?
const EnvironmentVariable = struct {
    name: []const u8,
    value: []const u8,
    flags: VariableFlags,

    pub fn init(allocator: Allocator, name: []const u8, value: []const u8, flags: VariableFlags) !*EnvironmentVariable {

        var var_name = try allocator.alloc(u8, name.len);
        errdefer allocator.free(var_name);
        @memcpy(var_name[0..], name);

        var var_value = try allocator.alloc(u8, value.len);
        errdefer allocator.free(var_value);
        @memcpy(var_value[0..], value);

        var env_var = try allocator.create(EnvironmentVariable);
        env_var.name = var_name;
        env_var.value = var_value;
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
