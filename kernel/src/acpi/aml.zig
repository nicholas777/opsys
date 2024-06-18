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

pub const Object = struct { name: []const u8, data: union(enum) {
    op_reg: OperationRegion,
    device: Device,
} };

pub const Device = struct {
    id: usize,
    uid: ?usize = null,

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
                else => {
                    console.printf("0x5b{x}: ", .{state.bc[state.i]});
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
                else => {
                    console.printf("0x{x}: ", .{state.bc[state.i]});
                    panic("Unimplemented operation");
                },
            }
        }
        if (state.curr_device != null and state.curr_device.?.data.device.bytes_left == 0) {
            state.curr_scope.scope_bytes_left -= state.curr_device.?.data.device.decl_size;
            state.curr_device = null;
        }

        if (state.curr_scope.scope_bytes_left == 0) {
            state.curr_scope.empty = true;
        }
    }

    return state.ns;
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
        else => {
            // We simply treat the value as a byte,
            // There is nothing in the spec about this but it seems to work
            result = state.bc[state.i];
            state.i += 1;
        },
    }

    return result;
}

const ScopedName = struct {
    name: []const u8,
    scope: *Scope,
    is_dual: bool = false,
};

fn getName() ScopedName {
    var root: bool = false;
    var parent: usize = 0;

    if (state.bc[state.i] == opcode.RootNamePrefix) root = true;
    while (state.bc[state.i] == opcode.ParentNamePrefix) : (state.i += 1) parent += 1;

    if (root) state.i += 1;

    // Figure out what scope to use
    var scope: *Scope = undefined;
    if (root) {
        scope = state.ns.root_scope;
    } else {
        scope = state.curr_scope;
        while (parent != 0) : (parent -= 1) {
            if (scope.parent == null) break;
            scope = scope.parent.?;
        }
    }

    if (state.bc[state.i] == opcode.DualNamePrefix) {
        state.i += 9;

        return ScopedName{
            .is_dual = true,
            .scope = scope,
            .name = state.bc[state.i - 8 .. state.i],
        };
    } else {
        state.i += 4;

        return ScopedName{
            .name = state.bc[state.i - 4 .. state.i],
            .scope = scope,
        };
    }
}

fn finishDecl(size: usize) void {
    if (state.curr_device != null) {
        state.curr_device.?.data.device.bytes_left -= size;
    } else {
        state.curr_scope.scope_bytes_left -= size;
    }
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
    if (pkg_len < 0x3F) {
        pkg_len_bytes = 1;
    } else if (pkg_len < 0xFFF) {
        pkg_len_bytes = 2;
    } else if (pkg_len < 0xFFFFF) {
        pkg_len_bytes = 3;
    } else if (pkg_len < 0xFFFFFFF) {
        pkg_len_bytes = 4;
    }

    const name = getName();

    // Now comes a list of named declarations
    // The first one will be an ID
    if (state.bc[state.i] != opcode.NameOp) {
        panic("ACPI Device without ID");
    }

    console.printf("Device: {s}\n", .{name.name});

    state.i += 1;

    var obj: *Object = name.scope.objects.addOne() catch panic("OOM");
    obj.name = name.name;
    obj.data.device = .{ .id = 0 };

    const id_name = getName();
    if (std.mem.eql(u8, id_name.name, "_HID")) {
        if (state.bc[state.i] == opcode.StringOp) {
            panic("ACPI Device _HID of type string unimplemented");
        }

        obj.data.device.id = getUIntValue();
    } else {
        panic("ACPI Device ID type unimplemented");
    }

    state.curr_device = obj;
    obj.data.device.bytes_left = pkg_len - (state.i - orig_i);
    obj.data.device.decl_size = pkg_len + pkg_len_bytes + 1;
}

// For now we will simply skip methods
fn evalMethod() void {
    const orig_i = state.i;
    state.i += 1;

    const pkg_len = getPkgLength();
    console.printf("Method: {s}\n", .{
        state.bc[state.i .. state.i + 4],
    });
    state.i += pkg_len;

    finishDecl(state.i - orig_i);
}

fn evalField() void {
    const orig_i = state.i;
    state.i += 1;

    var pkg_len = getPkgLength();

    const opreg_name = getName();
    var opreg: ?*Object = null;

    for (opreg_name.scope.objects.items) |*item| {
        if (std.mem.eql(u8, item.name, opreg_name.name)) {
            opreg = item;
        }
    }

    if (opreg == null) panic("Cannot find OpReg");

    const flag = state.bc[state.i];
    _ = flag;
    state.i += 1;

    pkg_len -= 5; // opreg_name and flag
    while (pkg_len > 0) {
        const saved_i = state.i;
        const name = getName();
        const size = getPkgLength();

        var field = opreg.?.data.op_reg.fields.addOne() catch panic("OOM");
        field.name = name.name;
        field.size = size;
        field.mem = state.alloc.alloc(u8, size) catch panic("OOM");

        pkg_len -= state.i - saved_i;
    }

    finishDecl(state.i - orig_i);
}

fn evalOpRegion() void {
    const orig_i = state.i;
    state.i += 1;

    const name = getName();
    const scope = name.scope;

    var region: *Object = scope.objects.addOne() catch unreachable;
    region.name = name.name;

    const reg_space: opcode.RegionSpace = @enumFromInt(state.bc[state.i]);
    state.i += 1;

    region.data.op_reg = .{
        .reg_space = reg_space,
        .addr = getUIntValue(),
        .length = getUIntValue(),
        .fields = std.ArrayList(Field).init(state.alloc),
    };

    finishDecl(state.i - orig_i);
}

fn evalNamedDecl() void {
    const orig_i = state.i;
    state.i += 1;

    const name = getName();

    if (state.curr_device != null and std.mem.eql(u8, "_UID", name.name)) {
        if (state.bc[state.i] == opcode.StringOp)
            panic("Unimplemented: ACPI Device string IDs");

        state.curr_device.?.data.device.uid = getUIntValue();
    } else {
        panic("ACPI: NamedDecl unimplemented");
    }

    finishDecl(state.i - orig_i);
}

fn evalScope() void {
    state.i += 1;
    var pkg_len = getPkgLength();

    var scope: *Scope = undefined;

    if (state.bc[state.i] == '\\' and state.bc[state.i + 1] == 0) {
        scope = state.alloc.create(Scope) catch panic("OOM");

        scope.children = std.ArrayList(Scope).init(state.alloc);
        scope.objects = std.ArrayList(Object).init(state.alloc);
        scope.length = pkg_len + 1; // The opcode
        scope.name = "\\___"; // If the name is just '\\', '\x00' it means root

        pkg_len -= 2;
        state.i += 2;

        state.ns.root_scope = scope;
        scope.parent = null;
    } else {
        const saved_i = state.i;

        const name = getName();
        console.printf("Scope: {s}\n", .{name.name});
        if (name.is_dual == false) {
            scope = state.ns.root_scope.children.addOne() catch panic("OOM");
        } else {
            var parent: ?*Scope = null;
            for (state.ns.root_scope.children.items) |*child| {
                if (std.mem.eql(u8, child.name, name.name[0..4])) {
                    parent = child;
                }
            }

            if (parent == null) panic("ACPI AML: Invalid scope; nonexistent");
            scope = parent.?.children.addOne() catch panic("OOM");
        }

        scope.children = std.ArrayList(Scope).init(state.alloc);
        scope.objects = std.ArrayList(Object).init(state.alloc);
        scope.length = pkg_len + 1; // The opcode
        scope.name = name.name;

        pkg_len -= state.i - saved_i;
    }

    scope.empty = false;

    scope.scope_bytes_left = pkg_len;
    state.curr_scope = scope;

    // Now we just let all the declarations fill up the scope
}
