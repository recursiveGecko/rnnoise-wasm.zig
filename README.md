# Work In Progress: Zig+RNNoise+WASM

This is an experiment that aims to port [RNNoise](https://github.com/xiph/rnnoise) to WASM using custom Zig wrappers.

# Demo

https://recursivegecko.github.io/rnnoise-wasm.zig

Current version is functional, but leaking memory from buffers that transport data between JS and WASM.

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

* `bin/rnnoise-zig` - **CLI utility for converting a file**

* `lib/rnnoise-zig.wasm` - **WASM application library**

# CLI

Prepare audio (mp3/wav/etc.) for denoising:

`ffmpeg -i <input file> -f f32le -acodec pcm_f32le -ac 1 -ar 48000 <output file>`


Denoise:

`./zig-out/bin/rnnoise-zig <input file> <output file>`


Play denoised audio:

`ffplay -f f32le -ar 48000 -ac 1 <file>`


Convert denoised audio to a conventional format (mp3/wav/etc.):

`ffmpeg -f f32le -ar 48000 -ac 1 -i <input file> <output file>`

# License

This project is licensed under the Mozilla Public License, Version 2.0, except for:

* Source files contained in `lib/rnnoise` directory which are licensed under the 
BSD 3-Clause License by the [RNNoise project](https://github.com/xiph/rnnoise).
You can find a copy of their license in `lib/rnnoise/COPYING`

# Copyright notice

---

[rnnoise-wasm.zig](https://github.com/recursiveGecko/rnnoise-wasm.zig)

Copyright (c) 2023, recursiveGecko

---

[RNNoise](https://github.com/xiph/rnnoise)

Copyright (c) 2017, Mozilla

Copyright (c) 2007-2017, Jean-Marc Valin

Copyright (c) 2005-2017, Xiph.Org Foundation

Copyright (c) 2003-2004, Mark Borgerding

---

