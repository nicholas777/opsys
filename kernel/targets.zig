const std = @import("std");
const Target = std.Target;

pub const x86: Target.Query = .{
    .os_tag = .freestanding,
    .abi = .none,
    .ofmt = .elf,

    .cpu_arch = .x86,
    .cpu_model = .determined_by_cpu_arch,
    .cpu_features_sub = get_removed_features_x86_64(),
    .cpu_features_add = get_added_features_x86_64(),
};

fn get_added_features_x86_64() Target.Cpu.Feature.Set {
    const Feature = Target.x86.Feature;

    var result = Target.Cpu.Feature.Set.empty;
    result.addFeature(@intFromEnum(Feature.soft_float));
    return result;
}

fn get_removed_features_x86_64() Target.Cpu.Feature.Set {
    const Feature = Target.x86.Feature;

    var result = Target.Cpu.Feature.Set.empty;
    result.addFeature(@intFromEnum(Feature.mmx));
    result.addFeature(@intFromEnum(Feature.sse));
    result.addFeature(@intFromEnum(Feature.sse2));
    result.addFeature(@intFromEnum(Feature.avx));
    result.addFeature(@intFromEnum(Feature.avx2));
    return result;
}
