const std = @import("std");
const parser = @import("parser.zig");
const posix = std.posix;
const Allocator = std.mem.Allocator;

pub const evalResult = struct {
    exit_code: i32,
    output: []u8,
};

pub fn evaluatePipeline(allocator: Allocator, pipeline: *parser.Pipeline) !void {

    const n = pipeline.commands.items.len;
    if (n == 0) {
        return;
    }

    var pipes = try allocator.alloc([2]posix.fd_t, n);

    for (pipes, 0..) |_, i| {
        pipes[i] = try posix.pipe();
    }

    var procs = try allocator.alloc(std.process.Child, n);

    for (pipeline.commands.items, 0..) |cmd, i | {

        var proc = std.process.Child.init(@ptrCast(cmd.argv.items), allocator);

        const first = i == 0;
        const last = i == n - 1;

        if (!first) {
            proc.stdin = std.fs.File{ .handle = pipes[i-1][0] };
        }

        if (!last) {
            proc.stdout = std.fs.File{ .handle = pipes[i][1] };
        }else {
            proc.stdout_behavior = .Pipe;
        }

        try proc.spawn();
        procs[i] = proc;

    }

    for (pipes) |pipe| {
        posix.close(pipe[0]);
        posix.close(pipe[1]);
    }

    for (procs[0 .. n - 1]) |*p| {
        _ = try p.wait();
    }
    var last = &procs[n - 1];

    var buf: [100]u8 = undefined;

    if (last.stdout) |out_stream| {
        var reader = out_stream.reader(&buf);
        const reader_int = &reader.interface;
        const output = try reader_int.readAlloc(allocator, 100);
        std.debug.print("buf: {s}", .{output});
    }

    _ = try last.wait();

}

pub fn evaluate(allocator: Allocator, ast: *parser.AST) !void {
    for (ast.pipelines.items) |pipeline_ptr| {
        var pipeline = pipeline_ptr.*;
        try evaluatePipeline(allocator, &pipeline);
    }
}
