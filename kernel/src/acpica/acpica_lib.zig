extern fn c_putline(line: [*]u8) void;
extern fn putChar(c: u8) void;

export fn _putchar(character: u8) void {
    putChar(character);
}

fn putline(str: []const u8) void {
    c_putline(@constCast(str.ptr));
}

extern fn alloc(size: u32, ptr_align: u32) ?[*]u8;

export fn c_alloc(size: u32, ptr_align: u32) [*c]u8 {
    const a = alloc(size, ptr_align);
    if (a) |result| {
        return result;
    } else {
        return @as([*c]u8, @ptrFromInt(0));
    }
}

extern fn free(ptr: [*]u8) void;

export fn c_free(ptr: *anyopaque) void {
    free(@ptrCast(ptr));
}

const PageTableType = enum(u8) {
    KernelRO = 0b00000001,
    KernelRW = 0b00000011,
    UserRO = 0b00000101,
    UserRW = 0b00000111,
};

extern fn mapPagesAt(pt_type: PageTableType, addr: usize, n: usize) usize;
extern fn freePage(addr: usize, free_physical: bool) void;

export fn c_mapPageN(addr: usize, n: usize) usize {
    return mapPagesAt(.KernelRO, addr, n);
}

export fn c_freePage(addr: usize) void {
    freePage(addr, false);
}

extern fn c_installInterruptHandler(h: ?*anyopaque, n: usize, context: ?*anyopaque) void;
extern fn uninstallInterruptHandler(n: usize) void;

export fn installIntHandler(h: ?*anyopaque, n: usize, c: ?*anyopaque) void {
    if (h != null) {
        c_installInterruptHandler(@ptrCast(h.?), n, c);
    } else {
        uninstallInterruptHandler(n);
    }
}

export fn uninstallIntHandler(n: usize) void {
    uninstallInterruptHandler(n);
}
