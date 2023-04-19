const std = @import("std");
const buildOpts = @import("build_options");
const MinLibC = @import("minimal-libc.zig");
const denoiser = @import("denoiser.zig");
const Denoiser = denoiser.Denoiser;

const allocator = std.heap.wasm_allocator;
var state: ?Denoiser = null;

// Callable from JS
export fn getFrameSize() usize {
    return denoiser.getFrameSize();
}

// Callable from JS
export fn initialize() bool {
    if (state != null) return false;

    state = Denoiser.init(allocator) catch return false;
    return true;
}

// Callable from JS
// export fn pushPCM(samples: [*]f32) f32 {
//     if (state == null) return -1;

//     const vad = state.?.pushPCM(samples) catch {
//         return -2;
//     };

//     return vad;
// }

// Callable from JS
export fn destroy() bool {
    if (state == null) return false;

    state.?.deinit();
    state = null;
    
    return true;
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

        @export(minLibC.free, .{ .name = "free", .linkage = .Strong });
        @export(minLibC.malloc, .{ .name = "malloc", .linkage = .Strong });
        @export(minLibC.calloc, .{ .name = "calloc", .linkage = .Strong });
    }
}
