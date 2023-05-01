const std = @import("std");

const AllocationMeta = struct {
    size: usize,
};

pub fn init(comptime allocator: std.mem.Allocator) type {
    // Provide alternative libc function implementations for freestanding targets
    // Thanks @InKryption - https://discord.com/channels/605571803288698900/1082604403875401758/1082611900090679346

    return struct {
        pub fn malloc(size: usize) callconv(.C) ?[*]u8 {
            var allocation: []u8 = allocWithMetadata(size) catch return null;
            return allocation.ptr;
        }

        pub fn calloc(nitems: usize, size: usize) callconv(.C) ?[*]u8 {
            var totalSize = nitems * size;
            var allocation: []u8 = allocWithMetadata(totalSize) catch return null;
            std.mem.set(u8, allocation, 0);
            return allocation.ptr;
        }

        pub fn free(ptr: [*]u8) callconv(.C) void {
            freeWithMetadata(ptr);
        }

        pub fn abs(n: c_int) callconv(.C) c_int {
            return if (n >= 0) n else -n;
        }

        fn allocWithMetadata(size: usize) ![]u8 {
            var allocation: []u8 = try allocator.alloc(u8, size + @sizeOf(AllocationMeta));
            var allocationHeader = std.mem.bytesAsValue(AllocationMeta, allocation[0..@sizeOf(AllocationMeta)]);

            allocationHeader.* = .{
                .size = size,
            };

            return allocation[@sizeOf(AllocationMeta)..];
        }

        fn freeWithMetadata(ptr: [*]u8) void {
            var metadataPtr = ptr - @sizeOf(AllocationMeta);
            var metadata = std.mem.bytesToValue(AllocationMeta, metadataPtr[0..@sizeOf(AllocationMeta)]);

            allocator.free(metadataPtr[0 .. metadata.size + @sizeOf(AllocationMeta)]);
        }
    };
}
