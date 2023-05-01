const std = @import("std");
const Denoiser = @import("denoiser.zig");
const SliceChunker = @import("slice_chunker.zig").SliceChunker;

var std_out = std.io.getStdOut().writer();

pub fn main() !u8 {
    var gpa = std.heap.GeneralPurposeAllocator(.{ .verbose_log = false }){};
    var arena = std.heap.ArenaAllocator.init(gpa.allocator());
    var alloc = arena.allocator();
    defer arena.deinit();

    // std.debug.print("RNNoise Frame size is: {d}\n", .{Denoiser.getFrameSize()});

    var args = try std.process.argsWithAllocator(alloc);
    defer args.deinit();

    const program = args.next();
    const in_path = args.next();
    const out_path = args.next();

    if (in_path == null or out_path == null) {
        const usage =
            \\Usage: {s} <input file> <output file>
            \\
            \\Input file must be RAW 32-bit float mono PCM file sampled at 48 kHz.
            \\
            \\
            \\Prepare audio (mp3/wav/etc.) for denoising:
            \\ffmpeg -i <input file> -f f32le -acodec pcm_f32le -ac 1 -ar 48000 <output file>
            \\
            \\Play denoised audio:
            \\ffplay -f f32le -ar 48000 -ac 1 <file>
            \\
            \\Convert denoised audio to a conventional format (mp3/wav/etc.):
            \\ffmpeg -f f32le -ar 48000 -ac 1 -i <input file> <output file>
            \\
        ;

        try std_out.print(usage, .{program.?});
        return 1;
    }

    try convertFile(alloc, in_path.?, out_path.?);

    return 0;
}

fn convertFile(alloc: std.mem.Allocator, in_path: []const u8, out_path: []const u8) !void {
    const cwd = std.fs.cwd();
    const in_file = try std.fs.Dir.openFile(cwd, in_path, .{});
    const out_file = try std.fs.Dir.createFile(cwd, out_path, .{});
    defer in_file.close();
    defer out_file.close();

    const in_buffer: []f32 = try alloc.alloc(f32, Denoiser.getFrameSize());
    const out_buffer: []f32 = try alloc.alloc(f32, Denoiser.getFrameSize());
    defer alloc.free(in_buffer);
    defer alloc.free(out_buffer);

    const in_stat = try in_file.stat();
    try std_out.print("File size: {d} bytes\n", .{in_stat.size});

    var denoiser = try Denoiser.init(alloc);
    defer denoiser.deinit();

    while (true) {
        const len = try in_file.read(std.mem.sliceAsBytes(in_buffer));

        if (len < Denoiser.getFrameSize()) {
            break;
        }

        const result = try denoiser.pushPCM(in_buffer);
        defer denoiser.destroyResult(result);

        if (result.samples) |samples| {
            // std.debug.print("VAD: {d}\n", .{result.vad});
            // std.debug.print("Samples: {d}\n", .{samples.len});
            try out_file.writeAll(std.mem.sliceAsBytes(samples));
        } else {
            // std.debug.print("No samples\n", .{});
        }
    }

    try std_out.print("Done!\n", .{});
}

// Run tests
comptime {
    _ = SliceChunker;
    _ = Denoiser;
}
