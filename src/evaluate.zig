const std = @import("std");
const parser = @import("parser.zig");
const environment = @import("environment.zig");
const posix = std.posix;
const Allocator = std.mem.Allocator;

const builtIns = [_][]const u8 {"cd", "exit"};

pub fn run(gpa: Allocator, arena: Allocator, ast: *parser.AST, env: *environment.Environment) !void {
    for (ast.pipelines.items) |pipeline| {
        try evaluatePipeline(gpa, arena ,pipeline, env);
    }
}

fn evaluatePipeline(gpa: Allocator, arena: Allocator, pipeline: *parser.Pipeline, env: *environment.Environment) !void {
    const n = pipeline.commands.items.len;

    if (n == 0) {
        return;
    }

    var pipe: [2]posix.fd_t = undefined;
    var prev_read: i32 = -1;
    var pids = try std.ArrayList(i32).initCapacity(arena, 3);
    const cenv = std.c.environ;

    for (pipeline.commands.items, 0..) | commands, i|{

        for (commands.assignment.items) |assignments| {
            try env.set(gpa, assignments.key, assignments.value, .{ .exp = true });
        }

        if (commands.argv.items.len == 0) {
            continue;
        }
        
        const command = std.mem.span(commands.argv.items[0].?);
        if (is_builtin(command)) {
            try run_builtin(command, @ptrCast(commands.argv.items));
            return;
        }

        const notLast = i < n - 1;
        const notStart = prev_read != -1;

        if (notLast) {
            pipe = try posix.pipe();
        }

        const fork_pid = try std.posix.fork();

        // 0 is child
        if (fork_pid == 0) {
            for (commands.redirects.items) | redirects | {
                const redir_type = redirects.redir_type;
                const file_name = redirects.file_name[0..redirects.file_name.len-1];
                var file: std.fs.File = undefined;

                switch (redir_type) {
                    parser.RedirectType.RedirOut => {
                        file = try std.fs.cwd().createFile(file_name, .{.truncate = true});
                        try posix.dup2(file.handle, posix.STDOUT_FILENO);
                    },
                    parser.RedirectType.RedirOutApp => {
                        file = try std.fs.cwd().createFile(file_name, .{.read = true, .truncate = false});
                        const endPos = try file.getEndPos();
                        try file.seekTo(endPos);
                        try posix.dup2(file.handle, posix.STDOUT_FILENO);
                    },
                    parser.RedirectType.RedirOutErr => {
                        file = try std.fs.cwd().createFile(file_name, .{.truncate = true});
                        try posix.dup2(file.handle, posix.STDOUT_FILENO);
                        try posix.dup2(file.handle, posix.STDERR_FILENO);
                    },
                    parser.RedirectType.RedirOutErrApp => {
                        file = try std.fs.cwd().createFile(file_name, .{.read = true, .truncate = false});
                        const endPos = try file.getEndPos();
                        try file.seekTo(endPos);
                        try posix.dup2(file.handle, posix.STDOUT_FILENO);
                        try posix.dup2(file.handle, posix.STDERR_FILENO);
                    },
                    parser.RedirectType.RedirErr => {
                        file = try std.fs.cwd().createFile(file_name, .{.truncate = true});
                        try posix.dup2(file.handle, posix.STDERR_FILENO);
                    },
                    parser.RedirectType.RedirErrApp => {
                        file = try std.fs.cwd().createFile(file_name, .{.read = true, .truncate = false});
                        const endPos = try file.getEndPos();
                        try file.seekTo(endPos);
                        try posix.dup2(file.handle, posix.STDERR_FILENO);
                    },
                    parser.RedirectType.RedirIn => {
                        file = try std.fs.cwd().openFile(file_name, .{.mode = .read_only});
                        try posix.dup2(file.handle, posix.STDIN_FILENO);
                    }
                }
                file.close();
            }

            if (notStart) {
                try posix.dup2(prev_read, posix.STDIN_FILENO);
                posix.close(prev_read);
            }

            if (notLast) {
                try posix.dup2(pipe[1], posix.STDOUT_FILENO);
                posix.close(pipe[0]);
                posix.close(pipe[1]);
            }

            const result = std.posix.execvpeZ(commands.argv.items[0].?, @ptrCast(commands.argv.items), cenv);
            switch (result) {
                std.posix.ExecveError.FileNotFound => {
                    std.debug.print("zell: {s}: command not found\n", .{commands.argv.items[0].?});
                },
                else => {
                    std.debug.print("Result: {any}\n", .{result});
                },
            }
            std.process.exit(0);
        }

        try pids.append(arena, fork_pid);


        if (notStart) {
            posix.close(prev_read);
        }

        if (notLast) {
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
        return error.ExitingShell;
    }
}
