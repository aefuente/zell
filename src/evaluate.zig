const std = @import("std");
const parser = @import("parser.zig");
const posix = std.posix;
const Allocator = std.mem.Allocator;

const builtIns = [_][]const u8 {"cd", "exit"};

pub fn run(allocator: Allocator, ast: *parser.AST) !void {
    for (ast.pipelines.items) |pipeline| {
        try evaluatePipeline(allocator, pipeline);
    }
}

fn evaluatePipeline(allocator: Allocator, pipeline: *parser.Pipeline) !void {
    const n = pipeline.commands.items.len;

    if (n == 0) {
        return;
    }

    const command = std.mem.span(pipeline.commands.items[0].argv.items[0].?);
    if (is_builtin(command)) {
        try run_builtin(command, @ptrCast(pipeline.commands.items[0].argv.items));
        return;
    }

    var pipe: [2]posix.fd_t = undefined;
    var prev_read: i32 = -1;
    var pids = try std.ArrayList(i32).initCapacity(allocator, 3);
    const env = std.c.environ;

    for (pipeline.commands.items, 0..) | commands, i|{
        if (i < n - 1) {
            pipe = try posix.pipe();
        }

        const fork_pid = try std.posix.fork();

        if (fork_pid == 0){
            if (prev_read != -1) {
                try posix.dup2(prev_read, posix.STDIN_FILENO);
            }

            if (i < n - 1) {
                try posix.dup2(pipe[1], posix.STDOUT_FILENO);
            }

            if (prev_read != -1) {
                posix.close(prev_read);
            }

            if (i < n - 1){
                posix.close(pipe[0]);
                posix.close(pipe[1]);
            }

            const result = std.posix.execvpeZ(commands.argv.items[0].?, @ptrCast(commands.argv.items), env);
            switch (result) {
                std.posix.ExecveError.FileNotFound => {
                    std.debug.print("zell: {s}: command not found\n", .{commands.argv.items[0].?});
                },
                else => {
                    std.debug.print("Result: {any}\n", .{result});
                },
            }
            return;
        }

        try pids.append(allocator, fork_pid);

        if (prev_read != - 1) {
            posix.close(prev_read);
        }

        if (i < n - 1) {
            posix.close(pipe[1]);
            prev_read = pipe[0];
        }
    }

    for (pids.items) |pid| {
        _ = posix.waitpid(pid, 0);
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
    }else if (std.mem.eql(u8, command, "exit")) {
        std.process.exit(0);
    }
}
