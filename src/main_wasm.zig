const std = @import("std");
const buildOpts = @import("build_options");
const MinLibC = @import("minimal-libc.zig");
const Denoiser = @import("denoiser.zig");

const allocator = std.heap.wasm_allocator;
var state: ?Denoiser = null;

// Callable from JS
export fn getFrameSize() usize {
    return Denoiser.getFrameSize();
}

// Callable from JS
export fn initialize() bool {
    if (state != null) {
        return false;
    } else {
        state = Denoiser.init(allocator) catch return false;
        return true;
    }
}

const PushPCMResult = extern struct {
    vad: f32,
    count: c_ulong,
    samples: [*c]f32,
};

// Callable from JS
export fn pushPCM(in_samples_ptr: [*]f32, count: c_ulong) [*c]PushPCMResult {
    //FIXME: Memory leaks
    var call_result = allocator.create(PushPCMResult) catch return null;
    call_result.* = std.mem.zeroInit(PushPCMResult, .{});

    if (state) |*s| {
        var in_samples: []f32 = in_samples_ptr[0..count];

        const result = s.pushPCM(in_samples) catch return null;

        if (result.samples) |out_samples| {
            call_result.* = .{
                .vad = result.vad,
                .samples = out_samples.ptr,
                .count = out_samples.len,
            };

            return call_result;
        }

        return null;
    } else {
        return null;
    }
}

// Callable from JS
export fn destroy() bool {
    if (state != null) {
        state.?.deinit();
        state = null;

        return true;
    } else {
        return false;
    }
}

// Disable logging for freestanding targets
// https://github.com/ziglang/zig/blob/2568da2f41d3403b2cd91bbb84862c86932b63e6/lib/std/std.zig#L106
pub const std_options = struct {
    pub fn logFn(
        comptime message_level: std.log.Level,
        comptime scope: @TypeOf(.enum_literal),
        comptime format: []const u8,
        args: anytype,
    ) void {
        _ = args;
        _ = format;
        _ = scope;
        _ = message_level;
    }
};

comptime {
    if (buildOpts.provide_minimal_libc) {
        const minLibC = MinLibC.init(allocator);

        @export(minLibC.abs, .{ .name = "abs", .linkage = .Strong });
        @export(minLibC.free, .{ .name = "free", .linkage = .Strong });
        @export(minLibC.malloc, .{ .name = "malloc", .linkage = .Strong });
        @export(minLibC.calloc, .{ .name = "calloc", .linkage = .Strong });
    }
}
