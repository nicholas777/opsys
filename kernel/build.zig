const std = @import("std");
const Target = std.Target;

const targets = @import("targets.zig");

pub fn build(b: *std.Build) void {
    const optimize = b.standardOptimizeOption(.{});
    const default_target = b.resolveTargetQuery(targets.x86);

    var kernel = b.addExecutable(.{
        .name = "kernel.elf",
        .version = std.SemanticVersion.parse("0.0.1") catch unreachable,
        .root_source_file = b.path("src/bootstrap.zig"),

        .target = default_target,
        .optimize = optimize,
        .code_model = .kernel,
        .single_threaded = true,
    });

    kernel.setLinkerScript(b.path("linker.ld"));
    b.installArtifact(kernel);

    const kernel_path = b.getInstallPath(.bin, "kernel.elf");
    const iso_dir = b.fmt("{s}/iso_dir", .{b.cache_root.path.?});
    const iso_path = b.fmt("{s}/kernel.iso", .{iso_dir});
    const iso_cmd = &[_][]const u8{ "/bin/sh", "-c", std.mem.concat(
        b.allocator,
        u8,
        &[_][]const u8{ "rm -f ", iso_path, " && ", "mkdir -p ", iso_dir, " ", iso_dir, "/boot/grub", " &&", " cp ", kernel_path, " ", iso_dir, "/boot", " && ", " cp grub.cfg ", iso_dir, "/boot/grub", " && ", " grub-mkrescue -o ", iso_path, " ", iso_dir },
    ) catch unreachable };
    std.debug.print("{s}", .{iso_cmd});

    var iso_step = b.addSystemCommand(iso_cmd);
    b.getInstallStep().dependOn(&iso_step.step);

    const iso_lp = std.Build.LazyPath{ .cwd_relative = iso_path };
    b.getInstallStep().dependOn(&b.addInstallFileWithDir(iso_lp, .prefix, "bin/kernel.iso").step);

    const run = b.option(bool, "run", "Run the os using qemu") orelse false;
    if (run) {
        const out_path = std.mem.concat(b.allocator, u8, &[_][]const u8{
            b.install_prefix, "/bin/kernel.iso",
        }) catch unreachable;

        const run_cmd_str = &[_][]const u8{
            "qemu-system-x86_64",
            "-cdrom",
            out_path,
            "-debugcon",
            "stdio",
            "-vga",
            "virtio",
            "-m",
            "4G",
            "-machine",
            "q35,accel=kvm:whpx:tcg",
            "-no-reboot",
            "-no-shutdown",
        };

        b.getInstallStep().dependOn(&b.addSystemCommand(run_cmd_str).step);
    }
}
