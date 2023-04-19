const std = @import("std");
const denoiser = @import("denoiser.zig");
const SliceChunker = @import("slice_chunker.zig").SliceChunker;
const Denoiser = denoiser.Denoiser;

var gpa = std.heap.GeneralPurposeAllocator(.{ .verbose_log = false }){};
var arena = std.heap.ArenaAllocator.init(gpa.allocator());
var allocator = arena.allocator();
var state: ?Denoiser = null;

pub fn main() !u8 {
    defer arena.deinit();
    state = try Denoiser.init(allocator);
    defer state.?.deinit();

    std.debug.print("RNNoise Frame size is: {d}\n", .{denoiser.getFrameSize()});

    return 0;
}

// Run tests
comptime {
    _ = SliceChunker;
    _ = Denoiser;
}
