const std = @import("std");

const c = @cImport({
    @cInclude("mysql.h");
    @cInclude("stdio.h");
    @cInclude("stdlib.h");
    @cInclude("string.h");
});

const max_output: usize = 65_535; // enough???

fn openPipe(command: [*:0]const u8) ?*c.FILE {
    if (comptime @import("builtin").os.tag == .windows) {
        return c._popen(command, "r");
    } else {
        return c.popen(command, "r");
    }
}

fn closePipe(pipe: *c.FILE) c_int {
    if (comptime @import("builtin").os.tag == .windows) {
        return c._pclose(pipe);
    } else {
        return c.pclose(pipe);
    }
}

fn copyMessage(message: [*c]u8, text: [:0]const u8) void {
    if (message == null) return;
    _ = c.strncpy(message, text, 79);
    message[79] = 0;
}

fn setError(error_flag: [*c]u8) [*c]u8 {
    error_flag.* = 1;
    return null;
}

export fn sys_eval_init(
    initid: [*c]c.UDF_INIT,
    args: [*c]c.UDF_ARGS,
    message: [*c]u8,
) bool {
    if (initid == null or args == null) {
        copyMessage(message, "Invalid UDF initialization arguments.");
        return true;
    }

    if (args.*.arg_count != 1 or args.*.arg_type[0] != c.STRING_RESULT) {
        copyMessage(message, "Expected exactly one string argument.");
        return true;
    }

    const output = c.malloc(max_output + 1) orelse {
        copyMessage(message, "Could not allocate output buffer.");
        return true;
    };

    initid.*.ptr = @ptrCast(output);
    initid.*.maybe_null = true;
    initid.*.max_length = max_output;
    return false;
}

export fn sys_eval_deinit(initid: [*c]c.UDF_INIT) void {
    if (initid == null) return;

    if (initid.*.ptr != null) {
        c.free(initid.*.ptr);
        initid.*.ptr = null;
    }
}

export fn sys_eval(
    initid: [*c]c.UDF_INIT,
    args: [*c]c.UDF_ARGS,
    result: [*c]u8,
    length: [*c]c_ulong,
    is_null: [*c]u8,
    error_flag: [*c]u8,
) [*c]u8 {
    _ = result;

    length.* = 0;
    is_null.* = 0;
    error_flag.* = 0;

    if (initid == null or args == null or initid.*.ptr == null) {
        return setError(error_flag);
    }

    if (args.*.arg_count != 1 or args.*.args[0] == null) {
        is_null.* = 1;
        return null;
    }

    const command_ptr = args.*.args[0].?;
    const command_len: usize = @intCast(args.*.lengths[0]);
    const command = command_ptr[0..command_len];

    // The shell command API takes a NUL-terminated string. Reject embedded
    // NULs so the command cannot be silently truncated.......
    if (std.mem.indexOfScalar(u8, command, 0) != null) {
        return setError(error_flag);
    }

    const command_mem = c.malloc(command_len + 1) orelse
        return setError(error_flag);
    defer c.free(command_mem);

    const command_bytes: [*]u8 = @ptrCast(command_mem);
    @memcpy(command_bytes[0..command_len], command);
    command_bytes[command_len] = 0;

    const command_z: [*:0]const u8 = @ptrCast(command_mem);
    const pipe = openPipe(command_z) orelse
        return setError(error_flag);

    var pipe_open = true;
    defer {
        if (pipe_open) _ = closePipe(pipe);
    }

    const output: [*]u8 = @ptrCast(initid.*.ptr);

    var output_len: usize = 0;
    var overflow = false;
    var read_error = false;
    var read_buffer: [1024]u8 = undefined;

    while (true) {
        const count = c.fread(read_buffer[0..].ptr, 1, read_buffer.len, pipe);

        if (count == 0) {
            if (c.ferror(pipe) != 0) read_error = true;
            break;
        }

        const bytes_to_copy = @min(count, max_output - output_len);

        if (bytes_to_copy != count) overflow = true;

        if (bytes_to_copy > 0) {
            @memcpy(
                output[output_len .. output_len + bytes_to_copy],
                read_buffer[0..bytes_to_copy],
            );
            output_len += bytes_to_copy;
        }

        // Keep reading even after reaching the output limit so the child
        // cannot block because its stdout pipe is full.
    }

    const status = closePipe(pipe);
    pipe_open = false;

    if (read_error or overflow or status != 0) {
        return setError(error_flag);
    }

    if (output_len == 0) {
        is_null.* = 1;
        return null;
    }

    output[output_len] = 0;
    length.* = @intCast(output_len);

    return output;
}
