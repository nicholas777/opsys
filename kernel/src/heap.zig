// Translated from https://wiki.osdev.org/User:Pancakes/BitmapHeapImplementation

const std = @import("std");

pub const KernelAllocator = std.mem.Allocator{
    .ptr = undefined,
    .vtable = &alloc_vtable,
};

const alloc_vtable = std.mem.Allocator.VTable{
    .alloc = alloc_fn,
    .resize = std.mem.Allocator.noResize,
    .free = free_fn,
};

// We can probably ignore ptr_align since our block boorders are 16-byte aligned
fn alloc_fn(_: *anyopaque, len: usize, ptr_align: u8, ret_addr: usize) ?[*]u8 {
    _ = ptr_align;
    _ = ret_addr;

    return alloc(len);
}

fn free_fn(_: *anyopaque, buf: []u8, buf_align: u8, ret_addr: usize) void {
    _ = buf_align;
    _ = ret_addr;

    free(@ptrCast(buf.ptr));
}

pub const HeapBlock = extern struct {
    next: ?*HeapBlock = null,
    size: u32 = 0,
    used: u32 = 0,
    block_size: u32 = 0,
    lfb: u32 = 0,
};

pub const Heap = extern struct {
    fblock: ?*HeapBlock = null,
};

var heap: Heap = .{};

pub fn addBlock(addr: usize, size: u32, block_size: u32) void {
    var b: *HeapBlock = @ptrFromInt(addr);
    b.size = size - @sizeOf(HeapBlock);
    b.block_size = block_size;
    b.next = heap.fblock;
    heap.fblock = b;

    var block_count: u32 = b.size / b.block_size;
    if ((block_count / 8) < block_count) {
        block_count = block_count / 8 + 1;
    } else {
        block_count = block_count / 8;
    }

    var bitmap: [*]u8 = @as([*]u8, @ptrCast(b)) + @sizeOf(HeapBlock);
    var x: u32 = 0;
    while (x < block_count) : (x += 1) {
        bitmap[x] = 0;
    }

    if ((block_count / block_size) < block_count) {
        block_count = block_count / block_size + 1;
    } else {
        block_count = block_count / block_size;
    }

    x = 0;
    while (x < block_count) : (x += 1) {
        bitmap[x] = 5;
    }

    b.used = block_count;
}

fn getNID(a: u8, b: u8) u8 {
    var c: u8 = a + 1;
    while (c == b or c == 0) : (c += 1) {}

    return c;
}

const console = @import("console.zig");

pub fn alloc(size: u32) ?[*]u8 {
    if (heap.fblock == null) return null;

    var block: ?*HeapBlock = heap.fblock;
    while (block != null) : (block = block.?.next) {
        if ((block.?.size - (block.?.used * block.?.block_size)) >= size) {
            const block_count: u32 = block.?.size / block.?.block_size;

            const bneed: u32 = if (((size / block.?.block_size) * block.?.block_size) < size) (size / block.?.block_size) + 1 else size / block.?.block_size;
            var bitmap: [*]u8 = @as([*]u8, @ptrCast(block.?)) + @sizeOf(HeapBlock);

            var x: usize = 0;
            console.printf("Hello! {} {} {} {} {}\n", .{ x, block.?.lfb, block.?.block_size, block.?.size, block_count });
            while (x < block_count) : (x += 1) {
                if (x >= block_count) {
                    x = 0;
                }

                if (bitmap[x] == 0) {
                    var y: usize = 0;
                    while (bitmap[x + y] == 0 and (y < bneed) and (x + y) < block_count) : (y += 1) {}

                    if (y == bneed) {
                        const nid: u8 = getNID(bitmap[x - 1], bitmap[x + y]);

                        var z: u32 = 0;
                        while (z < y) : (z += 1) {
                            bitmap[x + z] = nid;
                        }

                        block.?.used += y;
                        return @ptrFromInt((x * block.?.block_size) +
                            @intFromPtr(block.?) + @sizeOf(HeapBlock));
                    }

                    x += y - 1;
                }
            }
        }
    }

    return null;
}

pub fn free(ptr: [*]u8) void {
    var b: ?*HeapBlock = heap.fblock;

    while (b != null) : (b = b.?.next) {
        if (@intFromPtr(ptr) > @intFromPtr(b.?) and @intFromPtr(ptr) < @intFromPtr(b.?) + @sizeOf(HeapBlock) + b.?.size) {
            const ptr_offset: usize = @as(usize, @intFromPtr(ptr)) - @as(usize, @intFromPtr(b.?) + @sizeOf(HeapBlock));
            const bi: usize = ptr_offset / b.?.block_size;

            var bm: [*]u8 = @as([*]u8, @ptrCast(b.?)) + @sizeOf(HeapBlock);
            const id: u8 = bm[bi];

            const max = b.?.size / b.?.block_size;

            var x: u32 = bi;
            while (bm[x] == id and x < max) : (x += 1) {
                bm[x] = 0;
            }

            b.?.used -= x - bi;
            return;
        }
    }
}
