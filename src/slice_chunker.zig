const std = @import("std");
const assert = std.debug.assert;
const RingBuffer = std.RingBuffer;

/// SliceChunker generates fixed-length chunks from a stream of items.
pub fn SliceChunker(comptime T: type) type {
    return struct {
        const ChunkerResult = struct { chunks: ?[]const []const T = null, remaining: usize };
        const Type: type = T;

        allocator: std.mem.Allocator,
        ringBuffer: RingBuffer,
        chunkSize: usize,

        /// Initializes the chunker with a given chunk size
        /// Allocator is stored in the chunker and used for allocating chunks
        pub fn init(allocator: std.mem.Allocator, chunkSize: usize) !@This() {
            return @This(){
                .ringBuffer = try RingBuffer.init(allocator, @sizeOf(T) * chunkSize),
                .allocator = allocator,
                .chunkSize = chunkSize,
            };
        }

        /// Deinitializes the chunker, freeing all memory.
        /// ChunkerResults must be freed separately by calling destroyResult()
        pub fn deinit(self: *@This()) void {
            self.ringBuffer.deinit(self.allocator);
        }

        /// Returns the number of items currently stored in the buffer
        pub fn len(self: *@This()) usize {
            return self.ringBuffer.len() / @sizeOf(T);
        }

        /// Returns the number of items that are needed to complete the chunk
        pub fn lenUntilFull(self: *@This()) usize {
            return (self.ringBuffer.data.len / @sizeOf(T)) - self.len();
        }

        /// Pushes a single item into the chunker, emitting 0 or 1 chunks
        /// If the result contains chunks, it must be freed by calling destroyResult()
        pub fn pushOne(self: *@This(), item: T) !ChunkerResult {
            return pushMany(self, &.{item});
        }

        /// Pushes an arbitrary number of items into the chunker, emitting 0 or more chunks
        /// If the result contains chunks, it must be freed by calling destroyResult()
        pub fn pushMany(self: *@This(), items: []const T) !ChunkerResult {
            // Determine the number of chunks that will be emitted by this push operation
            const nExpectedChunks: usize = (self.len() + items.len) / self.chunkSize;
            var chunks: ?[][]const T = null;

            // Allocate memory for the slice containing the chunks
            if (nExpectedChunks > 0) {
                chunks = try self.allocator.alloc([]const T, nExpectedChunks);
            }

            var itemsIdx: usize = 0;
            var chunkIdx: usize = 0;

            // In case of an error, free the memory allocated for the slice of chunks,
            // as well as the individual chunk slices
            errdefer {
                if (chunks) |c| {
                    for (0..chunkIdx) |i| {
                        self.allocator.free(c[i]);
                    }

                    self.allocator.free(c);
                }
            }

            while (itemsIdx < items.len) {
                // Determine the slice range to insert, making sure we don't insert more items than we have
                // or more items than we need to fill the buffer
                const remainingItems = items.len - itemsIdx;
                const from = itemsIdx;
                const to = from + @min(self.lenUntilFull(), remainingItems);

                // RingBuffer operates on raw bytes
                const insertSlice: []const u8 = std.mem.sliceAsBytes(items[from..to]);

                // This will never return an error if our calculations are correct
                self.ringBuffer.writeSlice(insertSlice) catch unreachable;

                // Create a chunk if the buffer is full
                if (self.lenUntilFull() == 0) {
                    assert(nExpectedChunks > chunkIdx);

                    chunks.?[chunkIdx] = try self.consumeChunk();
                    chunkIdx += 1;
                }

                itemsIdx = to;
            }

            return ChunkerResult{
                .chunks = chunks,
                .remaining = self.lenUntilFull(),
            };
        }

        /// Frees the result containing 1 or more chunks
        pub fn destroyResult(self: *@This(), result: ChunkerResult) void {
            if (result.chunks) |chunks| {
                for (chunks) |chunk| {
                    self.allocator.free(chunk);
                }

                self.allocator.free(chunks);
            }
        }

        /// Creates a full chunk from the current buffer contents
        fn consumeChunk(self: *@This()) ![]T {
            if (self.lenUntilFull() != 0) {
                return error.NotEnoughData;
            }

            // Get the Slice struct containing 2 slices, one for each half of the ring buffer
            const ringSlice = self.ringBuffer.sliceLast(self.ringBuffer.data.len);

            // Allocate memory for the full chunk and its underlying byte slice
            const fullChunk: []T = try self.allocator.alloc(T, self.chunkSize);
            const rawBytes: []u8 = std.mem.sliceAsBytes(fullChunk);

            // Copy data from both halves of the ring buffer into the full chunk
            std.mem.copy(u8, rawBytes[0..ringSlice.first.len], ringSlice.first);
            std.mem.copy(u8, rawBytes[ringSlice.first.len..], ringSlice.second);

            // Manually reset the ring buffer indices
            self.ringBuffer.read_index = 0;
            self.ringBuffer.write_index = 0;

            return fullChunk;
        }
    };
}

const testing = std.testing;
test "SliceChunker(i32).pushOne" {
    const a = testing.allocator;

    const IntSliceChunker = SliceChunker(i32);
    var chunker = try IntSliceChunker.init(a, 3);
    defer chunker.deinit();

    var result: IntSliceChunker.ChunkerResult = undefined;

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
    try testing.expectEqualDeep(result.chunks.?, &.{&.{700, -100, 200}});
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

    var result: IntSliceChunker.ChunkerResult = undefined;

    result = try chunker.pushMany(&.{700, 600, 500, 400, 300});
    try testing.expectEqualDeep(result.chunks.?, &.{&.{700, 600, 500}});
    try testing.expectEqual(result.remaining, 1);
    try testing.expectEqual(chunker.len(), 2);
    try testing.expectEqual(chunker.lenUntilFull(), 1);
    chunker.destroyResult(result);


    result = try chunker.pushMany(&.{10, 20, 30, 40, 50, 60, 70, 80});
    try testing.expectEqualDeep(result.chunks.?, &.{&.{400, 300, 10}, &.{20, 30, 40}, &.{50, 60, 70}});
    try testing.expectEqual(result.remaining, 2);
    try testing.expectEqual(chunker.len(), 1);
    try testing.expectEqual(chunker.lenUntilFull(), 2);
    chunker.destroyResult(result);

    result = try chunker.pushMany(&.{-10, -50});
    try testing.expectEqualDeep(result.chunks.?, &.{&.{80, -10, -50}});
    try testing.expectEqual(result.remaining, 3);
    try testing.expectEqual(chunker.len(), 0);
    try testing.expectEqual(chunker.lenUntilFull(), 3);
    chunker.destroyResult(result);
}
