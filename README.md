# Work In Progress: Zig+RNNoise+WASM

This is an experiment that aims to port [RNNoise](https://github.com/xiph/rnnoise) to WASM using custom Zig wrappers.

# Cloning

```shell
git clone --recurse-submodules git@github.com:recursiveGecko/rnnoise-wasm.zig.git
```

# Requirements

* Zig master (0.11.x)

# Building

```shell
zig build -Doptimize=ReleaseFast
```

Produces the following artifacts in `zig-out`:

* `bin/audio-toolkit` - **CLI utility for converting a file**

* `lib/audio-toolkit-wasm.wasm` - **WASM application library**

* `lib/librnnoise.a` - Static native library of original RNNoise project

* `lib/librnnoise-wasm.a` - Static WASM library of original RNNoise project

# CLI

Prepare audio (mp3/wav/etc.) for denoising:

`ffmpeg -i <input file> -f f32le -acodec pcm_f32le -ac 1 -ar 48000 <output file>`


Denoise:

`./zig-out/bin/audio-toolkit <input file> <output file>`


Play denoised audio:

`ffplay -f f32le -ar 48000 -ac 1 <file>`


Convert denoised audio to a conventional format (mp3/wav/etc.):

`ffmpeg -f f32le -ar 48000 -ac 1 -i <input file> <output file>`

