const std = @import("std");
const CrossTarget = std.zig.CrossTarget;

const rnnoiseIncludePath = "vendor/rnnoise/include";

// Although this function looks imperative, note that its job is to
// declaratively construct a build graph that will be executed by an external
// runner.
pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const rnnSources = try makePrefixedPaths(b.allocator, &.{ "vendor", "rnnoise", "src" }, &.{
        "denoise.c",
        "celt_lpc.c",
        "kiss_fft.c",
        "pitch.c",
        "rnn_data.c",
        "rnn_reader.c",
        "rnn.c",
    });

    std.debug.print("rnnSources: {s}\n\n", .{rnnSources});

    try buildWeb(b, rnnSources, optimize);
    try buildDefault(b, rnnSources, target, optimize);
}

fn buildWeb(b: *std.Build, rnnSources: []const []const u8, optimize: std.builtin.Mode) !void {
    const wasmTarget = try CrossTarget.parse(.{ .arch_os_abi = "wasm32-freestanding" });

    const rnnoiseLib = b.addStaticLibrary(.{ .name = "rnnoise-wasm", .target = wasmTarget, .optimize = optimize });
    rnnoiseLib.addCSourceFiles(rnnSources, &.{});
    rnnoiseLib.linkLibC();
    rnnoiseLib.addIncludePath(rnnoiseIncludePath);
    rnnoiseLib.stack_protector = false;
    // rnnoiseLib.use_lld = false;
    // rnnoiseLib.use_llvm = false;
    b.installArtifact(rnnoiseLib);

    const options = b.addOptions();
    // FIXME: When true, it resolves issues with the WASM build (miscompilation?)
    options.addOption(bool, "rnnoise_use_extern", true);
    options.addOption(bool, "provide_minimal_libc", true);

    const appLib = b.addSharedLibrary(.{
        .name = "audio-toolkit-wasm",
        .root_source_file = .{ .path = "src/main-wasm.zig" },
        .target = wasmTarget,
        .optimize = optimize,
    });
    appLib.addIncludePath(rnnoiseIncludePath);
    appLib.linkLibrary(rnnoiseLib);
    appLib.linkLibC();
    appLib.addOptions("build_options", options);
    appLib.rdynamic = true;
    appLib.stack_protector = false;
    // appLib.use_lld = false;
    // appLib.use_llvm = false;
    b.installArtifact(appLib);
}

fn buildDefault(b: *std.Build, rnnSources: []const []const u8, target: CrossTarget, optimize: std.builtin.Mode) !void {
    const rnnoiseLib = b.addStaticLibrary(.{ .name = "rnnoise", .target = target, .optimize = optimize });
    rnnoiseLib.addCSourceFiles(rnnSources, &.{});
    rnnoiseLib.linkLibC();
    rnnoiseLib.addIncludePath("vendor/rnnoise/include");
    b.installArtifact(rnnoiseLib);

    const options = b.addOptions();
    options.addOption(bool, "rnnoise_use_extern", false);

    const exe = b.addExecutable(.{
        .name = "audio-toolkit",
        .root_source_file = .{ .path = "src/main.zig" },
        .target = target,
        .optimize = optimize,
    });
    exe.addIncludePath("vendor/rnnoise/include");
    exe.linkLibC();
    exe.linkLibrary(rnnoiseLib);
    exe.addOptions("build_options", options);

    b.installArtifact(exe);

    // This *creates* a RunStep in the build graph, to be executed when another
    // step is evaluated that depends on it. The next line below will establish
    // such a dependency.
    const run_cmd = b.addRunArtifact(exe);

    // By making the run step depend on the install step, it will be run from the
    // installation directory rather than directly from within the cache directory.
    // This is not necessary, however, if the application depends on other installed
    // files, this ensures they will be present and in the expected location.
    run_cmd.step.dependOn(b.getInstallStep());

    // This allows the user to pass arguments to the application in the build
    // command itself, like this: `zig build run -- arg1 arg2 etc`
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    // This creates a build step. It will be visible in the `zig build --help` menu,
    // and can be selected like this: `zig build run`
    // This will evaluate the `run` step rather than the default, which is "install".
    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    // Creates a step for unit testing. This only builds the test executable
    // but does not run it.
    const unit_tests = b.addTest(.{
        .root_source_file = .{ .path = "src/main.zig" },
        .target = target,
        .optimize = optimize,
    });

    const run_unit_tests = b.addRunArtifact(unit_tests);

    // Similar to creating the run step earlier, this exposes a `test` step to
    // the `zig build --help` menu, providing a way for the user to request
    // running the unit tests.
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_unit_tests.step);
}

fn makePrefixedPaths(allocator: std.mem.Allocator, prefix: []const []const u8, files: []const []const u8) ![]const [:0]const u8 {
    const paths: [][:0]const u8 = try allocator.alloc([:0]u8, files.len);

    const joinedPrefix = try std.fs.path.joinZ(allocator, prefix);
    defer allocator.free(joinedPrefix);

    for (files, 0..) |f, i| {
        paths[i] = try std.fs.path.joinZ(allocator, &.{ joinedPrefix, f });
    }

    return paths;
}
