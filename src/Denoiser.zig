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
            extern fn rnnoise_process_frame(state: *DenoiseState, out: [*]f32, in: [*]f32) f32;
        };
    } else {
        break :val @cImport({
            @cInclude("rnnoise.h");
        });
    }
};

pub const Result = struct {
    samples: ?[]f32 = null,
    vad: f32,
    vadIsCached: bool,
};

// Denoiser struct fields
allocator: std.mem.Allocator,
denoise_state: ?*rnnoise.DenoiseState = null,
frame_chunker: ?SliceChunker(f32) = null,
last_vad: f32 = 0.0,

pub fn init(allocator: std.mem.Allocator) !@This() {
    var frame_chunker = try SliceChunker(f32).init(allocator, getFrameSize());
    var denoise_state = rnnoise.rnnoise_create(null);

    return @This(){
        .denoise_state = denoise_state,
        .frame_chunker = frame_chunker,
        .allocator = allocator,
    };
}

pub fn deinit(self: *@This()) void {
    if (self.denoise_state != null) {
        rnnoise.rnnoise_destroy(self.denoise_state.?);
        self.denoise_state = null;
    }

    if (self.frame_chunker != null) {
        self.frame_chunker.?.deinit();
        self.frame_chunker = null;
    }
}

/// Push an arbitrary number of samples to the denoiser
/// Samples must be mono, *48kHz*, f32 values, normalized [-1, 1].
/// Returns a result containing the VAD (voice activity detection) value for the last frame,
/// possibly cached, and an optional slice of denoised samples
/// Memory allocated for the denoised samples must be freed with destroyResult()
pub fn pushPCM(self: *@This(), samples: []const f32) !Result {
    if (self.frame_chunker == null) return error.NotInitialized;
    if (self.denoise_state == null) return error.NotInitialized;

    // Push samples to the chunker, possibly getting back a slice of chunks
    const result = try self.frame_chunker.?.pushMany(samples);
    defer self.frame_chunker.?.destroyResult(result);

    if (result.chunks == null) {
        return Result{
            .samples = null,
            .vad = self.last_vad,
            .vadIsCached = true,
        };
    }

    // Calculate the total number of samples we'll be expecting
    var sampleCount: usize = result.chunks.?.len * getFrameSize();

    // Allocate a buffer for the output samples
    var out_samples: []f32 = try self.allocator.alloc(f32, sampleCount);
    errdefer self.allocator.free(out_samples);

    // Pass each chunk to the RNNoise library and store the result in the output buffer
    var out_idx: usize = 0;
    for (result.chunks.?) |chunk| {
        // This should never happen if our chunker is working correctly
        if (chunk.len != getFrameSize()) unreachable;

        // RNNoise expects an odd format, `s16` values represented as floats,
        // and we're working with normalized float PCM samples (`f32le` in `ffmpeg` terms)
        normalizedPcmToRnnoise(chunk);

        var out_slice = out_samples[out_idx .. out_idx + chunk.len];
        self.last_vad = rnnoise.rnnoise_process_frame(self.denoise_state.?, out_slice.ptr, chunk.ptr);
        out_idx += chunk.len;
    }

    // Convert the output samples back to normalized float PCM
    rnnoiseToNormalizedPcm(out_samples);

    return Result{
        .samples = out_samples,
        .vad = self.last_vad,
        .vadIsCached = false,
    };
}

/// Frees the memory allocated for the result of a pushPCM call
pub fn destroyResult(self: *@This(), result: Result) void {
    if (result.samples != null) {
        self.allocator.free(result.samples.?);
    }
}

pub fn getFrameSize() usize {
    return @intCast(usize, rnnoise.rnnoise_get_frame_size());
}

const RNNOISE_NORM_SCALAR = @as(f32, std.math.maxInt(i16));

/// Converts normalized [-1, 1] float PCM samples to the format
/// expected by RNNoise, `s16` values represented as floats
pub fn normalizedPcmToRnnoise(samples: []f32) void {
    for (samples) |*sample| {
        sample.* *= RNNOISE_NORM_SCALAR;
    }
}

/// Converts RNNoise PCM format (`s16` as floats) format back to
/// normalized [-1, 1] float PCM samples
pub fn rnnoiseToNormalizedPcm(samples: []f32) void {
    for (samples) |*sample| {
        sample.* /= RNNOISE_NORM_SCALAR;
    }
}

