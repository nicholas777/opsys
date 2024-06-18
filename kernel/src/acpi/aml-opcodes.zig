pub fn isNull(b: u8) bool {
    return (b >= 0x2 and b <= 0x5) or
        (b == 0x9 or b == 0xE or b == 0xF or b == 0x13) or
        (b >= 0x15 and b <= 0x2D) or
        (b >= 0x30 and b <= 0x5A) or
        (b == 0x5D or b == 0x5F or b == 0x6F) or
        (b >= 0x83 and b >= 0x85) or
        (b == 0x8F) or
        (b >= 0x96 and b <= 0x9F) or
        (b >= 0xA6 and b <= 0xCB) or
        (b >= 0xCD and b <= 0xFE);
}

pub const ZeroOp = 0x00;
pub const OneOp = 0x01;

pub const AliasOp = 0x06;
pub const NameOp = 0x08;
pub const ByteOp = 0x0A;
pub const WordOp = 0x0B;
pub const DWordOp = 0x0C;
pub const StringOp = 0x0D;
pub const ScopeOp = 0x10;
pub const BufferOp = 0x11;
pub const PackageOp = 0x12;
pub const MethodOp = 0x14;

pub const DualNamePrefix = 0x2E;
pub const MultiNamePrefix = 0x2F;
pub const ExtendedOperatorPrefix = 0x5B;

pub const OpPrefix = 0x5B;

// THE FOLLOWING ARE PREFIXED BY OP_PREFIX

pub const MutexOp = 0x01;
pub const EventOp = 0x02;

pub const ShiftRightBitOp = 0x10;
pub const ShiftBitLeftOp = 0x11;
pub const CondRefOfOp = 0x12;
pub const CreateFieldOp = 0x13;

pub const LoadOp = 0x20;
pub const StallOp = 0x21;
pub const SleepOp = 0x22;
pub const AcquireOp = 0x23;
pub const SignalOp = 0x24;
pub const WaitOp = 0x25;
pub const ResetOp = 0x26;
pub const ReleaseOp = 0x27;
pub const FromBCDOp = 0x28;
pub const ToBCD = 0x29;
pub const UnloadOp = 0x2A;
pub const DegubOp = 0x31;
pub const FatalOp = 0x32;

pub const OpRegionOp = 0x80;

pub const RegionSpace = enum(u8) {
    sys_mem = 0,
    sys_io = 1,
    pci = 2,
    embedded = 3,
    smbus = 4,
};

pub const FieldOp = 0x81;
pub const DeviceOp = 0x82;
pub const ProcessorOp = 0x83;
pub const PowerResOp = 0x84;
pub const ThermalZoneOp = 0x85;
pub const IndexFieldOp = 0x86;
pub const BankFieldOp = 0x87;

// NOT PREFIXED BY OP_PREFIX ANYMORE

pub const RootNamePrefix = 0x5C;
pub const ParentNamePrefix = 0x5E;

pub const Local0 = 0x60;
pub const Local1 = 0x61;
pub const Local2 = 0x62;
pub const Local3 = 0x63;
pub const Local4 = 0x64;
pub const Local5 = 0x65;
pub const Local6 = 0x66;
pub const Local7 = 0x67;
pub const Arg0 = 0x68;
pub const Arg1 = 0x69;
pub const Arg2 = 0x6A;
pub const Arg3 = 0x6B;
pub const Arg4 = 0x6C;
pub const Arg5 = 0x6D;
pub const Arg6 = 0x6E;

pub const StoreOp = 0x70;
pub const RefOfOp = 0x71;
pub const AddOp = 0x72;
pub const ConcatOp = 0x73;
pub const SubtractOp = 0x74;
pub const IncrementOp = 0x75;
pub const DecrementOp = 0x76;
pub const MultiplyOp = 0x77;
pub const DivideOp = 0x78;
pub const SHLOp = 0x79;
pub const SHROp = 0x7A;
pub const AndOp = 0x7B;
pub const NandOp = 0x7C;
pub const OrOp = 0x7D;
pub const NorOp = 0x7E;
pub const XorOp = 0x7F;
pub const NotOp = 0x80;
pub const FindSetLeftBitOp = 0x81;
pub const FindSetRightBitOp = 0x82;

pub const NotifyOp = 0x86;
pub const SizeOfOp = 0x87;
pub const IndexOp = 0x88;
pub const MatchOp = 0x89;
pub const DWordFieldOp = 0x8A;
pub const WordFieldOp = 0x8B;
pub const ByteFieldOp = 0x8C;
pub const BitFieldOp = 0x8D;
pub const ObjectTypeOp = 0x8E;

pub const LAndOp = 0x90;
pub const LOrOp = 0x91;
pub const LNotOp = 0x92;
pub const LEqOp = 0x93;
pub const LNeqOp = 0x9392;
pub const LGOp = 0x94; // Greater than
pub const LLEQOp = 0x9492; // Less than or equals
pub const LLOp = 0x95;
pub const LGEQOp = 0x9592;

pub const IfOp = 0xA0;
pub const ElseOp = 0xA1;
pub const WhileOp = 0xA2;
pub const NoOp = 0xA3;
pub const ReturnOp = 0xA4;
pub const BreakOp = 0xA5;

pub const BreakPointOp = 0xCC;
pub const OnesOp = 0xFF;
