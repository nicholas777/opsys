const std = @import("std");

const acpi = @import("acpi.zig");
const opcode = @import("aml-opcodes.zig");
const panic = @import("../common.zig").panic;
const console = @import("../console.zig");

pub const NameSpace = struct {
    root_scope: *Scope = undefined,
};

pub const Scope = struct {
    name: []const u8,
    parent: ?*Scope = null,
    children: std.ArrayList(Scope),
    objects: std.ArrayList(Object),

    scope_bytes_left: usize,
    length: usize,
    empty: bool,
};

pub const ObjectData = union(enum) {
    op_reg: OperationRegion,
    device: Device,
    processor: Processor,
    id: ID,
};

pub const Object = struct {
    name: []const u8,
    data: ObjectData = undefined,
};

pub const Processor = struct {
    proc_id: u8,
    pblk_addr: u32,
    pblk_len: u8,

    objects: std.ArrayList(Object),

    bytes_left: usize = 0,
    decl_size: usize = 0,
};

pub const ID = union(enum) {
    int: usize,
    str: []const u8,
};

pub const Device = struct {
    uid: ?ID = null,
    prs: ?usize = null,
    hid: ?ID = null,
    cid: ?ID = null,

    bytes_left: usize = 0,
    decl_size: usize = 0,
};

pub const OperationRegion = struct {
    reg_space: opcode.RegionSpace,
    addr: usize,
    length: usize,
    fields: std.ArrayList(Field),
};

pub const Field = struct {
    name: []const u8,
    size: usize,
    mem: []u8,
};

const InterpreterState = struct {
    bc: [*]u8, // The bytecode
    i: usize, // Index into bytecode
    alloc: std.mem.Allocator,
    ns: *NameSpace,

    curr_scope: *Scope,
    curr_device: ?*Object,

    op_prefix: bool,
};

var state: *InterpreterState = undefined;

// See the ACPI spec, edition 1.0
pub fn parseDSDT(alloc: std.mem.Allocator, dsdt: *acpi.TableHeader) !*NameSpace {
    state = try alloc.create(InterpreterState);
    defer alloc.destroy(state);
    console.printf("Size: {}\n", .{dsdt.length - @sizeOf(acpi.TableHeader)});
    const total_size = dsdt.length - @sizeOf(acpi.TableHeader);

    state.ns = try alloc.create(NameSpace);
    errdefer alloc.destroy(state.ns);

    const blksize = dsdt.length - @sizeOf(@TypeOf(dsdt));
    state.bc = @ptrCast(dsdt);
    state.bc += @sizeOf(acpi.TableHeader);
    state.op_prefix = false;
    state.alloc = alloc;

    state.curr_device = null;

    state.i = 0;
    while (state.i < blksize) {
        if (state.op_prefix) {
            switch (state.bc[state.i]) {
                opcode.OpRegionOp => {
                    evalOpRegion();
                },
                opcode.FieldOp => {
                    evalField();
                },
                opcode.DeviceOp => {
                    evalDevice();
                },
                opcode.MutexOp => {
                    evalMutex();
                },
                opcode.ProcessorOp => {
                    evalProcessor();
                },
                else => {
                    console.printf("0x5b{x} at addr=0x{x} of addr=0x{x} = {}%: \n", .{
                        state.bc[state.i],
                        @intFromPtr(state.bc + state.i),
                        @intFromPtr(state.bc + total_size),
                        state.i * 100 / total_size,
                    });
                    dumpNamespace();
                    panic("Unimplemented operation");
                },
            }

            state.op_prefix = false;
        } else {
            switch (state.bc[state.i]) {
                opcode.OpPrefix => {
                    state.op_prefix = true;
                    state.i += 1;
                    if (state.curr_device != null) {
                        state.curr_device.?.data.device.bytes_left -= 1;
                    } else {
                        state.curr_scope.scope_bytes_left -= 1;
                    }
                },
                opcode.ScopeOp => {
                    evalScope();
                },
                opcode.NameOp => {
                    evalNamedDecl();
                },
                opcode.MethodOp => {
                    evalMethod();
                },
                opcode.BufferOp => {
                    const orig_i = state.i;
                    _ = getBuffer();
                    finishDecl(state.i - orig_i);
                },
                else => {
                    console.printf("0x{x} at addr=0x{x} of addr=0x{x} = {}%: \n", .{
                        state.bc[state.i],
                        @intFromPtr(state.bc + state.i),
                        @intFromPtr(state.bc + total_size),
                        state.i * 100 / total_size,
                    });
                    dumpNamespace();
                    panic("Unimplemented operation");
                },
            }
        }

        if (state.curr_device != null and state.curr_device.?.data.device.bytes_left == 0) {
            console.printf("END OF DEVICE\n", .{});
            state.curr_scope.scope_bytes_left -= state.curr_device.?.data.device.decl_size;
            state.curr_device = null;
        }

        if (state.curr_scope.scope_bytes_left == 0) {
            state.curr_scope.empty = true;
            console.printf("END OF SCOPE\n", .{});

            if (state.curr_scope.parent != null and state.curr_scope.parent.?.scope_bytes_left != 0) {
                console.printf("Switched to parent, from: {s}, to: {s}\n", .{
                    state.curr_scope.name,
                    state.curr_scope.parent.?.name,
                });
                const old_scope = state.curr_scope;

                state.curr_scope = state.curr_scope.parent.?;
                state.curr_scope.scope_bytes_left -= old_scope.length;
            }
        }
    }

    return state.ns;
}

fn dumpNamespace() void {
    dumpScope(0, state.ns.root_scope);
}

fn dumpScope(indent: usize, scope: *Scope) void {
    doIndent(indent);
    console.printf("Scope: {s}\n", .{scope.name});

    for (scope.children.items) |*item| {
        dumpScope(indent + 1, item);
    }
}

fn doIndent(indent: usize) void {
    var i: usize = 0;
    while (i < indent) : (i += 1) {
        console.puts("  ");
    }
}

fn getPkgLength() usize {
    const len_bytes = state.bc[state.i] >> 6;
    var decl_len: usize = undefined;
    if (len_bytes == 0) {
        decl_len = state.bc[state.i] & 0x3F;
    } else if (len_bytes == 1) {
        decl_len = @as(usize, state.bc[state.i] & 0xF);
        decl_len += @as(usize, state.bc[state.i + 1]) << 4;
    } else if (len_bytes == 2) {
        decl_len = @as(usize, state.bc[state.i] & 0xF);
        decl_len += @as(usize, state.bc[state.i + 1]) << 4;
        decl_len += @as(usize, state.bc[state.i + 2]) << 12;
    } else if (len_bytes == 3) {
        decl_len = @as(usize, state.bc[state.i] & 0xF);
        decl_len += @as(usize, state.bc[state.i + 1]) << 4;
        decl_len += @as(usize, state.bc[state.i + 2]) << 12;
        decl_len += @as(usize, state.bc[state.i + 3]) << 20;
    } else {
        return 0;
    }

    decl_len -= len_bytes + 1;
    state.i += len_bytes + 1;

    return decl_len;
}

fn getUIntValue() usize {
    var result: usize = 0;
    switch (state.bc[state.i]) {
        opcode.ByteOp => {
            result = state.bc[state.i + 1];
            state.i += 2;
        },
        opcode.WordOp => {
            result = std.mem.bytesAsValue(u16, state.bc[state.i + 1 .. state.i + 3]).*;
            state.i += 3;
        },
        opcode.DWordOp => {
            result = std.mem.bytesAsValue(u32, state.bc[state.i + 1 .. state.i + 5]).*;
            state.i += 5;
        },
        opcode.ZeroOp, opcode.OneOp, opcode.OnesOp => |value| {
            result = value;
            state.i += 1;
        },
        else => {
            panic("Invalid UINT value");
        },
    }

    return result;
}

const ScopedName = struct {
    name: []const u8,
    scope: ?*Scope,
};

fn getName() ScopedName {
    var root: bool = false;
    var parent: usize = 0;

    if (state.bc[state.i] == opcode.RootNamePrefix) root = true;
    while (state.bc[state.i] == opcode.ParentNamePrefix) : (state.i += 1) parent += 1;

    if (root) state.i += 1;

    if (state.bc[state.i] == opcode.MultiNamePrefix) {
        state.i += 2;
        const seg_count = state.bc[state.i - 1];

        const name = state.bc[state.i .. state.i + (seg_count * 4)];

        var pscope: *Scope = state.ns.root_scope;
        if (parent != 0) {
            pscope = state.curr_scope;
            while (parent != 0) : (parent -= 1) {
                if (pscope.parent == null) break;
                pscope = pscope.parent.?;
            }
        }

        var i: usize = 0;
        while (i < seg_count - 1) : (i += 1) {
            const n: []const u8 = name[i * 4 .. i * 4 + 4];
            for (pscope.children.items) |*item| {
                if (std.mem.eql(u8, item.name, n)) {
                    pscope = item;
                    break;
                }
            }
        }

        state.i += 4 * seg_count;
        return ScopedName{
            .scope = pscope,
            .name = state.bc[state.i - 4 .. state.i],
        };
    }

    if (state.bc[state.i] == opcode.DualNamePrefix) {
        state.i += 1;
        const name = state.bc[state.i .. state.i + 8];

        var pscope: ?*Scope = null;
        for (state.ns.root_scope.children.items) |*child| {
            if (std.mem.eql(u8, child.name, name[0..4])) {
                pscope = child;
            }
        }

        state.i += 8;
        return ScopedName{
            .name = name[4..],
            .scope = pscope,
        };
    }

    // Figure out what scope to use
    var scope: ?*Scope = null;
    if (root) {
        scope = state.ns.root_scope;
    } else if (parent != 0) {
        scope = state.curr_scope;
        while (parent != 0) : (parent -= 1) {
            if (scope.?.parent == null) break;
            scope = scope.?.parent.?;
        }
    }

    state.i += 4;

    return ScopedName{
        .name = state.bc[state.i - 4 .. state.i],
        .scope = scope,
    };
}

fn getString() []const u8 {
    state.i += 1;

    var len: usize = 0;
    while (state.bc[state.i + len] != 0) : (len += 1) {}

    state.i += len + 1;
    return state.bc[state.i - (len + 1) .. state.i - 1];
}

fn finishDecl(size: usize) void {
    if (state.curr_device != null) {
        state.curr_device.?.data.device.bytes_left -= size;
    } else {
        if (!state.curr_scope.empty)
            state.curr_scope.scope_bytes_left -= size;
    }
}

fn evalProcessor() void {
    const orig_i = state.i;
    state.i += 1;

    const pkg_len = getPkgLength();

    const name_start = state.i;
    const name = getName();
    const name_len = state.i - name_start;

    const proc_id: u8 = state.bc[state.i];
    const pblk_addr: u32 =
        std.mem.bytesAsValue(u32, state.bc[state.i + 1 .. state.i + 5]).*;
    const pblk_len: u8 = state.bc[state.i + 5];

    state.i += pkg_len - name_len;

    console.printf("Processor: {s}, {}, {}, {}\n", .{
        name.name,
        state.curr_scope.scope_bytes_left,
        state.i,
        pkg_len,
    });

    var parent: *Scope = undefined;
    if (name.scope) |s| {
        parent = s;
    } else {
        parent = state.curr_scope;
    }

    var obj: *Object = parent.objects.addOne() catch panic("OOM");
    obj.name = name.name;
    obj.data.processor = .{
        .proc_id = proc_id,
        .pblk_addr = pblk_addr,
        .pblk_len = pblk_len,
        .objects = std.ArrayList(Object).init(state.alloc),
    };

    finishDecl(state.i - orig_i);
}

// Ignore mutices
fn evalMutex() void {
    const orig_i = state.i;
    state.i += 1;

    const name = getName();
    console.printf("Mutex: {s}\n", .{name.name});
    state.i += 1;

    finishDecl(state.i - orig_i);
}

fn evalDevice() void {
    state.i += 1;

    const pkg_len = getPkgLength();
    const orig_i = state.i;

    var pkg_len_bytes: usize = 0;
    if (pkg_len <= (0x3F - 1)) { // Correction for length of pkg_len itself // Correction for length of pkg_len itself
        pkg_len_bytes = 1;
    } else if (pkg_len <= (0xFFF - 2)) {
        pkg_len_bytes = 2;
    } else if (pkg_len <= (0xFFFFF - 3)) {
        pkg_len_bytes = 3;
    } else if (pkg_len <= (0xFFFFFFF - 4)) {
        pkg_len_bytes = 4;
    }

    const name = getName();

    console.printf("Device: {s}\n", .{name.name});

    var obj: *Object = undefined;
    if (name.scope) |s| {
        obj = s.objects.addOne() catch panic("OOM");
    } else {
        obj = state.curr_scope.objects.addOne() catch panic("OOM");
    }

    obj.name = name.name;
    obj.data.device = .{ .uid = null };

    state.curr_device = obj;
    obj.data.device.bytes_left = pkg_len - (state.i - orig_i);
    obj.data.device.decl_size = pkg_len + pkg_len_bytes + 1;
}

// For now we will simply skip methods
fn evalMethod() void {
    const orig_i = state.i;
    state.i += 1;

    const pkg_len = getPkgLength();

    const name_start = state.i;
    const name = getName();
    const name_len = state.i - name_start;

    state.i += pkg_len - name_len;
    console.printf("Method: {s}, i: {}, left: {}, size: {}\n", .{
        name.name,
        state.i,
        state.curr_scope.scope_bytes_left,
        state.i - orig_i,
    });

    finishDecl(state.i - orig_i);
}

fn evalField() void {
    const orig_i = state.i;
    state.i += 1;

    var pkg_len = getPkgLength();
    const name_start = state.i;

    var opreg_name = getName();
    if (opreg_name.scope == null) opreg_name.scope = state.curr_scope;
    const name_len = state.i - name_start;

    console.printf("OpReg Field: {s}\n", .{opreg_name.name});
    var opreg: ?*Object = null;

    var parent: *Scope = undefined;
    if (opreg_name.scope) |s| {
        parent = s;
    } else {
        parent = state.curr_scope;
    }

    for (parent.objects.items) |*item| {
        if (std.mem.eql(u8, item.name, opreg_name.name)) {
            opreg = item;
        }
    }

    if (opreg == null) panic("Cannot find OpReg");

    const flag = state.bc[state.i];
    _ = flag;
    state.i += 1;

    pkg_len -= name_len + 1; // opreg_name and flag
    while (pkg_len > 0) {
        const saved_i = state.i;
        var name: []const u8 = undefined;
        var size: usize = 0;

        // Fields can be named, reserved or access-type fields
        if (state.bc[state.i] == 0x0) {
            // Reserved
            state.i += 1;
            name = state.bc[state.i - 1 .. state.i];
            size = getPkgLength();
        } else if (state.bc[state.i] == 0x1) {
            // Access
            state.i += 3;
            name = state.bc[state.i - 3 .. state.i];
            size = 0;
        } else {
            // Named fields
            name = getName().name;
            size = getPkgLength();
        }

        var field = opreg.?.data.op_reg.fields.addOne() catch panic("OOM");
        field.name = name;
        field.size = size;
        if (size != 0)
            field.mem = state.alloc.alloc(u8, size) catch panic("OOM");

        pkg_len -= state.i - saved_i;
    }

    finishDecl(state.i - orig_i);
}

fn evalOpRegion() void {
    const orig_i = state.i;
    state.i += 1;

    const name = getName();
    const scope = name.scope orelse state.curr_scope;

    var region: *Object = scope.objects.addOne() catch panic("OOM");
    region.name = name.name;
    region.data = undefined;

    const reg_space: opcode.RegionSpace = @enumFromInt(state.bc[state.i]);
    state.i += 1;

    console.printf("OpReg: {s}\n", .{name.name});

    region.data.op_reg = .{
        .reg_space = reg_space,
        .addr = getUIntValue(),
        .length = getUIntValue(),
        .fields = std.ArrayList(Field).init(state.alloc),
    };
    console.printf("OpReg: {s}\n", .{name.name});

    finishDecl(state.i - orig_i);
}

fn evalNamedDecl() void {
    const orig_i = state.i;
    state.i += 1;

    const name = getName();

    console.printf("NamedDecl: ID_NAME={s}", .{name.name});
    if (state.curr_device != null) {
        var dev: *Device = &state.curr_device.?.data.device;
        if (std.mem.eql(u8, "_UID", name.name)) {
            console.printf(", DEV_NAME={s}", .{state.curr_device.?.name});

            if (state.bc[state.i] == opcode.StringOp) {
                dev.uid = .{ .str = getString() };
            } else {
                dev.uid = .{ .int = getUIntValue() };
            }
        } else if (std.mem.eql(u8, "_HID", name.name)) {
            console.printf(", DEV_NAME={s}", .{state.curr_device.?.name});

            if (state.bc[state.i] == opcode.StringOp) {
                dev.hid = .{ .str = getString() };
            } else {
                dev.hid = .{ .int = getUIntValue() };
            }
        } else if (std.mem.eql(u8, "_PRS", name.name)) {
            // Resources are packed into buffers
            if (state.bc[state.i] != opcode.BufferOp)
                panic("ACPI: No buffer around resource");

            console.printf(", DEV_NAME={s}", .{state.curr_device.?.name});
            evalResource(getBuffer());
        } else if (std.mem.eql(u8, "_CRS", name.name)) {
            // Resources are packed into buffers
            if (state.bc[state.i] != opcode.BufferOp)
                panic("ACPI: No buffer around resource");

            console.printf(", DEV_NAME={s}", .{state.curr_device.?.name});
            evalResource(getBuffer());
        } else if (std.mem.eql(u8, "_CID", name.name)) {
            console.printf(", DEV_NAME={s}", .{state.curr_device.?.name});

            if (state.bc[state.i] == opcode.StringOp) {
                dev.hid = .{ .str = getString() };
            } else {
                dev.hid = .{ .int = getUIntValue() };
            }
        } else if (std.mem.eql(u8, "_STA", name.name)) {
            console.printf(", DEV_NAME={s}", .{state.curr_device.?.name});
            if (state.bc[state.i] >= opcode.ByteOp and
                state.bc[state.i] <= opcode.DWordOp)
            {
                _ = getUIntValue();
            }
        } else {
            panic("\nACPI: NamedDecl unimplemented");
        }
    } else {
        if (std.mem.eql(u8, "_HID", name.name)) {
            var obj = state.curr_scope.objects.addOne() catch panic("OOM");
            obj.name = name.name;

            if (state.bc[state.i] == opcode.StringOp) {
                obj.data.id = .{ .str = getString() };
            } else {
                obj.data.id = .{ .int = getUIntValue() };
            }
        }
    }

    console.putChar('\n');

    finishDecl(state.i - orig_i);
}

fn getBuffer() []u8 {
    state.i += 1;
    _ = getPkgLength();

    // We assume that this is just a raw value
    // It can be anything that evaluates to an integer,
    // but that will be implemented later
    const buff_len = getUIntValue();
    state.i += buff_len;
    return state.bc[state.i - buff_len .. state.i];
}

fn evalResource(buffer: []const u8) void {
    var res_type: usize = 0;
    var name: usize = 0;
    var size: usize = 0;

    if (buffer[0] >> 7 == 0) {
        res_type = 0;
        name = (buffer[0] >> 3) & 0xF;
        size = buffer[0] & 0x7;
    } else {
        res_type = 1;
        size += buffer[1];
        size += @as(u16, @intCast(buffer[2])) << 8;
        name = buffer[0] & 0x7F;
    }
}

fn evalScope() void {
    state.i += 1;
    var pkg_len = getPkgLength();

    var scope: *Scope = undefined;
    var init: bool = true;

    if (state.bc[state.i] == '\\' and state.bc[state.i + 1] == 0) {
        scope = state.alloc.create(Scope) catch panic("OOM");

        scope.children = std.ArrayList(Scope).init(state.alloc);
        scope.objects = std.ArrayList(Object).init(state.alloc);
        scope.length = pkg_len + 1; // The opcode
        scope.name = "\\___"; // If the name is just '\\', '\x00' it means root
        console.printf("Root scope\n", .{});

        pkg_len -= 2;
        state.i += 2;

        state.ns.root_scope = scope;
        scope.parent = null;
    } else {
        const saved_i = state.i;

        const name = getName();

        console.printf("Scope: {s}, curr: {s}, left: 0x{x}, parent: {s}\n", .{
            name.name,
            state.curr_scope.name,
            state.curr_scope.scope_bytes_left,
            if (name.scope == null) "none" else name.scope.?.name,
        });

        var parent: *Scope = undefined;
        if (name.scope == null) {
            if (!state.curr_scope.empty) {
                parent = state.curr_scope;
            } else {
                parent = state.ns.root_scope;
            }
        } else {
            parent = name.scope.?;
        }

        for (parent.children.items) |*child| {
            if (std.mem.eql(u8, child.name, name.name)) {
                scope = child;
                init = false;
                break;
            }
        }

        if (init == true) {
            scope = parent.children.addOne() catch panic("OOM");

            scope.parent = parent;
        }

        if (init) {
            scope.children = std.ArrayList(Scope).init(state.alloc);
            scope.objects = std.ArrayList(Object).init(state.alloc);
        }

        var pkg_len_bytes: usize = 0;
        if (pkg_len <= (0x3F - 1)) { // Correction for length of pkg_len itself // Correction for length of pkg_len itself
            pkg_len_bytes = 1;
        } else if (pkg_len <= (0xFFF - 2)) {
            pkg_len_bytes = 2;
        } else if (pkg_len <= (0xFFFFF - 3)) {
            pkg_len_bytes = 3;
        } else if (pkg_len <= (0xFFFFFFF - 4)) {
            pkg_len_bytes = 4;
        }

        scope.length = pkg_len + pkg_len_bytes + 1; // The opcode
        scope.name = name.name;

        pkg_len -= state.i - saved_i;
    }

    scope.empty = false;

    scope.scope_bytes_left = pkg_len;
    state.curr_scope = scope;

    // Now we just let all the declarations fill up the scope
}
