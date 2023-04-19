const std = @import("std");
const ArrayList = std.ArrayList;
const buildOpts = @import("build_options");
const SliceChunker = @import("slice_chunker.zig").SliceChunker;

// FIXME: When true, it resolves issues with the WASM build
const useExternInsteadOfCImport = buildOpts.rnnoise_use_extern;
const rnnoise = val: {
    if (useExternInsteadOfCImport) {
        break :val struct {
            const RNNModel = opaque {};
            const DenoiseState = opaque {};
            extern fn rnnoise_get_frame_size() c_int;
            extern fn rnnoise_create(model: ?*RNNModel) *DenoiseState;
            extern fn rnnoise_destroy(state: *DenoiseState) void;
            extern fn rnnoise_process_frame(state: *DenoiseState, out: [*]f32, in: [*]f32) void;
        };
    } else {
        break :val @cImport({
            @cInclude("rnnoise.h");
        });
    }
};

pub const DenoiserResult = struct {
    samples: ?[]const f32 = null,
    vad: f32,
    vadIsCached: bool,
};

pub const Denoiser = struct {
    allocator: std.mem.Allocator,
    denoiseState: ?*rnnoise.DenoiseState = null,
    frameChunker: ?SliceChunker(f32) = null,
    lastVad: f32 = 0.0,

    pub fn init(allocator: std.mem.Allocator) !@This() {
        var frameChunker = try SliceChunker(f32).init(allocator, getFrameSize());
        var denoiseState = rnnoise.rnnoise_create(null);

        return @This(){
            .denoiseState = denoiseState,
            .frameChunker = frameChunker,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *@This()) void {
        if (self.denoiseState != null) {
            rnnoise.rnnoise_destroy(self.denoiseState.?);
            self.denoiseState = null;
        }

        if (self.frameChunker != null) {
            self.frameChunker.?.deinit();
            self.frameChunker = null;
        }
    }

    /// Push an arbitrary number of samples to the denoiser
    /// Samples must be mono, ** 48kHz **, f32 values
    /// Returns a result containing the VAD (voice activity detection) value for the last frame,
    /// possibly cached, and an optional slice of denoised samples
    /// Memory allocated for the denoised samples must be freed with destroyResult()
    pub fn pushPCM(self: *@This(), samples: []const f32) !DenoiserResult {
        if (self.frameChunker == null) return error.NotInitialized;
        if (self.denoiseState == null) return error.NotInitialized;

        // Push samples to the chunker, possibly getting back a slice of chunks
        const result = try self.frameChunker.?.pushMany(samples);
        if (result.chunks == null) {
            return DenoiserResult{
                .samples = null,
                .vad = self.lastVad,
                .vadIsCached = true,
            };
        }
        defer self.frameChunker.?.destroyResult(result);

        // Calculate the total number of samples we'll be expecting
        var sampleCount: usize = 0;
        for (result.chunks.?) |chunk| sampleCount += chunk.len;

        // Allocate a buffer for the output samples
        var outSamples: []f32 = try self.allocator.alloc(f32, sampleCount);
        errdefer self.allocator.free(outSamples);

        // Pass each chunk to the RNNoise library and store the result in the output buffer
        var outIdx: usize = 0;
        for (result.chunks.?) |chunk| {
            var outSlice = outSamples[outIdx .. outIdx + chunk.len];
            self.lastVad = rnnoise.rnnoise_process_frame(self.denoiseState.?, outSlice.ptr, chunk.ptr);
            outIdx += chunk.len;
        }

        return DenoiserResult{
            .samples = outSamples,
            .vad = self.lastVad,
            .vadIsCached = false,
        };
    }

    /// Frees the memory allocated for the result of a pushPCM call
    pub fn destroyResult(self: *@This(), result: DenoiserResult) void {
        if (result.samples != null) {
            self.allocator.free(result.samples.?);
        }
    }
};

pub fn getFrameSize() usize {
    return @intCast(usize, rnnoise.rnnoise_get_frame_size());
}
