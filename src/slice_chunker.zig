const std = @import("std");
const assert = std.debug.assert;

/// SliceChunker generates fixed-length chunks from a stream of items.
pub fn SliceChunker(comptime T: type) type {
    return struct {
        const Result = struct { chunks: ?[]const []T = null, remaining: usize };
        const Type: type = T;

        allocator: std.mem.Allocator,
        // entirety of the current chunker buffer
        full_slice: []const T = undefined,
        // sub-slice of full_slice that is not yet filled
        write_slice: []T = undefined,
        chunk_size: usize,

        /// Initializes the chunker with a given chunk size
        /// Allocator is stored in the chunker and used for allocating chunks
        pub fn init(allocator: std.mem.Allocator, chunk_size: usize) !@This() {
            if (chunk_size < 1) return error.InvalidChunkSize;

            var self = @This(){
                .allocator = allocator,
                .chunk_size = chunk_size,
            };

            try self.allocNewBuffer();
            return self;
        }

        /// Deinitializes the chunker, freeing all memory.
        /// ChunkerResults must be freed separately by calling destroyResult()
        pub fn deinit(self: *@This()) void {
            self.allocator.free(self.full_slice);
        }

        /// Returns the number of items currently stored in the buffer
        pub fn len(self: *@This()) usize {
            return self.full_slice.len - self.write_slice.len;
        }

        /// Returns the number of items that are needed to complete the chunk
        pub fn lenUntilFull(self: *@This()) usize {
            return self.write_slice.len;
        }

        /// Pushes a single item into the chunker, emitting 0 or 1 chunks
        /// If the result contains chunks, it must be freed by calling destroyResult()
        pub fn pushOne(self: *@This(), item: T) !Result {
            return pushMany(self, &.{item});
        }

        /// Pushes an arbitrary number of items into the chunker, emitting 0 or more chunks
        /// If the result contains chunks, it must be freed by calling destroyResult()
        pub fn pushMany(self: *@This(), items: []const T) !Result {
            // Determine the number of chunks that will be emitted by this push operation
            const n_expected_chunks: usize = (self.len() + items.len) / self.chunk_size;
            var chunks: ?[][]T = null;

            // Allocate memory for the slice containing the chunks
            if (n_expected_chunks > 0) {
                chunks = try self.allocator.alloc([]T, n_expected_chunks);
            }

            // track the number of items processed
            var items_idx: usize = 0;
            // track the number of chunks allocated
            var chunk_idx: usize = 0;

            // In case of an error, free the memory allocated for the slice of chunks,
            // as well as the individual chunk slices
            errdefer {
                if (chunks) |c| {
                    for (0..chunk_idx) |i| {
                        self.allocator.free(c[i]);
                    }

                    self.allocator.free(c);
                }
            }

            // insert all items into the chunker, creating chunks as needed
            while (items_idx < items.len) {
                // number of items remaining in the input slice
                const remaining_items = items.len - items_idx;
                // current insertion index
                const from = items_idx;
                // ensure that we don't insert more items than we have
                // or more than we need to fill the buffer
                const to = from + @min(self.lenUntilFull(), remaining_items);
                // slice of input to copy into the buffer
                const copy_items = items[from..to];

                // copy the items into the buffer
                std.mem.copy(T, self.write_slice, copy_items);
                // advance the write slice
                self.write_slice = self.write_slice[copy_items.len..];

                // if the buffer is full, append the chunk to the slice of chunks
                if (self.lenUntilFull() == 0) {
                    assert(n_expected_chunks > chunk_idx);

                    chunks.?[chunk_idx] = try self.finalizeChunk();
                    chunk_idx += 1;
                }

                items_idx = to;
            }

            return Result{
                .chunks = chunks,
                .remaining = self.lenUntilFull(),
            };
        }

        /// Frees the result containing 1 or more chunks
        pub fn destroyResult(self: *@This(), result: Result) void {
            if (result.chunks) |chunks| {
                for (chunks) |chunk| {
                    self.allocator.free(chunk);
                }

                self.allocator.free(chunks);
            }
        }

        /// Returns the current full chunk and allocates a new one
        /// Verifies that the chunk is full, otherwise returns an error
        fn finalizeChunk(self: *@This()) ![]T {
            if (self.lenUntilFull() != 0) return error.IncompleteChunk;

            const prev_slice = self.full_slice;
            try self.allocNewBuffer();
            return @constCast(prev_slice);
        }

        fn allocNewBuffer(self: *@This()) !void {
            self.write_slice = try self.allocator.alloc(T, self.chunk_size);
            self.full_slice = self.write_slice;
        }
    };
}

const testing = std.testing;
test "SliceChunker(i32).pushOne" {
    const a = testing.allocator;

    const IntSliceChunker = SliceChunker(i32);
    var chunker = try IntSliceChunker.init(a, 3);
    defer chunker.deinit();

    var result: IntSliceChunker.Result = undefined;
    var expected_chunk: []const []const IntSliceChunker.Type = undefined;

    result = try chunker.pushOne(700);
    try testing.expectEqual(result.chunks, null);
    try testing.expectEqual(result.remaining, 2);
    try testing.expectEqual(chunker.len(), 1);
    try testing.expectEqual(chunker.lenUntilFull(), 2);
    chunker.destroyResult(result);

    result = try chunker.pushOne(-100);
    try testing.expectEqual(result.chunks, null);
    try testing.expectEqual(result.remaining, 1);
    try testing.expectEqual(chunker.len(), 2);
    try testing.expectEqual(chunker.lenUntilFull(), 1);
    chunker.destroyResult(result);

    result = try chunker.pushOne(200);
    expected_chunk = &.{&.{ 700, -100, 200 }};
    try testing.expectEqualDeep(expected_chunk, result.chunks.?);
    try testing.expectEqual(result.remaining, 3);
    try testing.expectEqual(chunker.len(), 0);
    try testing.expectEqual(chunker.lenUntilFull(), 3);
    chunker.destroyResult(result);

    result = try chunker.pushOne(500);
    try testing.expectEqual(result.chunks, null);
    try testing.expectEqual(result.remaining, 2);
    try testing.expectEqual(chunker.len(), 1);
    try testing.expectEqual(chunker.lenUntilFull(), 2);
    chunker.destroyResult(result);
}

test "SliceChunker(i32).pushMany" {
    const a = testing.allocator;

    const IntSliceChunker = SliceChunker(i32);
    var chunker = try IntSliceChunker.init(a, 3);
    defer chunker.deinit();

    var result: IntSliceChunker.Result = undefined;
    var expected_chunk: []const []const IntSliceChunker.Type = undefined;

    result = try chunker.pushMany(&.{ 700, 600, 500, 400, 300 });
    expected_chunk = &.{&.{ 700, 600, 500 }};
    try testing.expectEqualDeep(expected_chunk, result.chunks.?);
    try testing.expectEqual(result.remaining, 1);
    try testing.expectEqual(chunker.len(), 2);
    try testing.expectEqual(chunker.lenUntilFull(), 1);
    chunker.destroyResult(result);

    result = try chunker.pushMany(&.{ 10, 20, 30, 40, 50, 60, 70, 80 });
    expected_chunk = &.{ &.{ 400, 300, 10 }, &.{ 20, 30, 40 }, &.{ 50, 60, 70 } };
    try testing.expectEqualDeep(expected_chunk, result.chunks.?);
    try testing.expectEqual(result.remaining, 2);
    try testing.expectEqual(chunker.len(), 1);
    try testing.expectEqual(chunker.lenUntilFull(), 2);
    chunker.destroyResult(result);

    result = try chunker.pushMany(&.{ -10, -50 });
    expected_chunk = &.{&.{ 80, -10, -50 }};
    try testing.expectEqualDeep(expected_chunk, result.chunks.?);
    try testing.expectEqual(result.remaining, 3);
    try testing.expectEqual(chunker.len(), 0);
    try testing.expectEqual(chunker.lenUntilFull(), 3);
    chunker.destroyResult(result);
}
