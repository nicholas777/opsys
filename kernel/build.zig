const std = @import("std");
const Target = std.Target;

const targets = @import("targets.zig");

var kernel: *std.Build.Step.Compile = undefined;

const acpica_include = "deps/acpica/source/include";
const acpica_src = "deps/acpica/source/components";
const acpica_src_common = "deps/acpica/source/common";
const acpica_cflags = &.{
    "-Ideps/acpica/source/include",
    "-D_GNU_EFI",
    "-DACPI_USE_LOCAL_CACHE=1",
    "-DACPI_OS_NAME=\"Opsys 1.0\"",
    "-DPRINTF_DISABLE_SUPPORT_FLOAT",
    "-DPLATFORM_BITS=32",
};

pub fn build(b: *std.Build) void {
    const optimize = b.standardOptimizeOption(.{});
    const default_target = b.resolveTargetQuery(targets.x86);

    kernel = b.addExecutable(.{
        .name = "kernel.elf",
        .version = std.SemanticVersion.parse("0.0.1") catch unreachable,
        .root_source_file = b.path("src/bootstrap.zig"),

        .target = default_target,
        .optimize = optimize,
        //.code_model = .kernel,
        .single_threaded = true,
    });

    kernel.addAssemblyFile(b.path("src/arch/i386/isr.s"));

    addAcpica(b);

    kernel.setLinkerScript(b.path("linker.ld"));
    b.installArtifact(kernel);

    addIsoStep(b);

    const out_path = std.mem.concat(b.allocator, u8, &[_][]const u8{
        b.install_prefix, "/bin/kernel.iso",
    }) catch unreachable;

    const run_cmd_str = &[_][]const u8{
        "qemu-system-i386",
        "-cdrom",
        out_path,
        "-debugcon",
        "stdio",
        "-vga",
        "virtio",
        "-m",
        "4G",
        "--no-reboot",
        "--no-shutdown",
        "-machine",
        "q35,accel=kvm:whpx:tcg",
        "-d",
        "int,cpu_reset",
    };

    var run_cmd = &b.addSystemCommand(run_cmd_str).step;
    run_cmd.dependOn(b.getInstallStep());
    const run_step = b.step("run", "Run the kernel using qemu");
    run_step.dependOn(run_cmd);
}

fn addAcpica(b: *std.Build) void {
    var acpica = b.addStaticLibrary(.{
        .name = "acpica",
        .root_source_file = b.path("src/acpica/acpica_lib.zig"),

        .target = kernel.root_module.resolved_target orelse unreachable,
        .optimize = kernel.root_module.optimize orelse unreachable,
        //.code_model = .kernel,
        .single_threaded = true,
    });

    // Add the acpica source
    var acpica_dir = std.fs.cwd().openDir(acpica_src, .{ .iterate = true }) catch unreachable;
    defer acpica_dir.close();

    var walker = acpica_dir.walk(b.allocator) catch unreachable;
    defer walker.deinit();

    var entry = walker.next() catch unreachable;
    while (entry != null) : (entry = walker.next() catch unreachable) {
        if (std.mem.startsWith(u8, entry.?.path, "disassembler")) continue;
        if (std.mem.startsWith(u8, entry.?.path, "debugger")) continue;
        if (std.mem.eql(u8, entry.?.basename, "rsdump.c")) continue;
        if (entry.?.kind != .file) continue;

        acpica.addCSourceFile(.{
            .file = b.path(b.pathJoin(&.{
                acpica_src,
                b.allocator.dupe(u8, entry.?.path) catch unreachable,
            })),
            .flags = acpica_cflags,
        });
    }

    acpica.addIncludePath(b.path(acpica_include));

    kernel.addIncludePath(b.path(acpica_include));

    // Add the os-specific layer

    acpica.addCSourceFile(.{
        .file = b.path("src/acpica/os_specific.c"),
        .flags = acpica_cflags,
    });

    acpica.addCSourceFile(.{
        .file = b.path("src/acpica/printf/printf.c"),
        .flags = acpica_cflags,
    });

    acpica.addCSourceFile(.{
        .file = b.path("src/acpica/libc_base.c"),
    });
    kernel.linkLibrary(acpica);
}

fn addIsoStep(b: *std.Build) void {
    const kernel_path = b.getInstallPath(.bin, "kernel.elf");
    const iso_dir = b.fmt("{s}/iso_dir", .{b.cache_root.path.?});
    const iso_path = b.fmt("{s}/kernel.iso", .{iso_dir});
    const iso_cmd = &[_][]const u8{ "/bin/sh", "-c", std.mem.concat(
        b.allocator,
        u8,
        &[_][]const u8{ "rm -f ", iso_path, " && ", "mkdir -p ", iso_dir, " ", iso_dir, "/boot/grub", " &&", " cp ", kernel_path, " ", iso_dir, "/boot", " && ", " cp grub.cfg ", iso_dir, "/boot/grub", " && ", " grub-mkrescue -o ", iso_path, " ", iso_dir, " > /dev/null" },
    ) catch unreachable };

    var iso_step = b.addSystemCommand(iso_cmd);
    b.getInstallStep().dependOn(&iso_step.step);
    iso_step.step.dependOn(&kernel.step);

    const iso_lp = std.Build.LazyPath{ .cwd_relative = iso_path };
    const iso_install_step = &b.addInstallFileWithDir(iso_lp, .prefix, "bin/kernel.iso").step;
    iso_install_step.dependOn(&iso_step.step);
    b.getInstallStep().dependOn(iso_install_step);
}
