pub const FlagMeminfo = 1 << 0;
pub const FlagBootDevice = 1 << 1;
pub const FlagCmdline = 1 << 2;
pub const FlagMods = 1 << 3;
pub const FlagSymbols = (1 << 4) | (1 << 5);
pub const FlagMmap = 1 << 6;
pub const FlagDrives = 1 << 7;
pub const FlagConfigTable = 1 << 8;
pub const FlagBootloaderName = 1 << 9;

pub const Multiboot = packed struct {
    flags: u32,

    mem_lower: u32,
    mem_upper: u32,

    // Booted partition and disk
    boot_device: u32,

    // command line string
    cmd_line: [*]const u8,

    // Modules
    mod_count: u32,
    mod_addr: [*]u8,

    sym_table1: u32,
    sym_table2: u32,
    sym_table3: u32,
    sym_table4: u32,

    mmap_length: u32,
    mmap_addr: [*]MemoryMap,

    drives_length: u32,
    drives_addr: [*]u8,

    rom_config: u32,

    bootloader_name: [*]const u8,
    // There is more but we won't need that yet
};

pub const MemoryMap = packed struct {
    size: u32,
    addr: u64,
    length: u64,
    type: u32,
};

pub const MemoryAvailable = 1;
pub const ACPIData = 3;
