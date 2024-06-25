pub const VersionMadeBy = enum(u16) {
    const Self = @This();

    @"MSDOS_OS/2" = 0,
    Amiga = 1,
    OpenVMS = 2,
    Unix = 3,
    VM_CMS = 4,
    Atari_ST = 5,
    @"OS/2 H.P.F.S" = 6,
    Macintosh = 7,
    ZSystem = 8,
    @"CP/M" = 9,
    WindowsNTFS = 10,
    @"MVS (OS/390 - Z/OS)" = 11,
    VSE = 12,
    AcornRisc = 13,
    VFAT = 14,
    AlternateMVS = 15,
    BeOS = 16,
    Tandem = 17,
    @" OS/400" = 18,
    @"OS X (Darwin)" = 19,
    Unuused = 20,
};

pub const VersionExtractFile = enum(u16) {
    Default = 10,
    VolumeLabel = 11,
    Directory = 20,
    DeflateCompression = 20,
    PKWAREEncryption = 20,
    Deflate64Compression = 21,
    PKWAREDCLImplodeCompression = 25,
    PatchDataSet = 27,
    ZIP64Extensions = 45,
    BZIP2Compression = 46,
    DESEncryption = 50,
    @"3DESEncryption" = 50,
    RC2Encryption = 50,
    RC4Encryption = 50,
    AESEncryption = 51,
    CorrectedRC2Encryption = 51,
    CorrectedRC264Encryption = 52,
    NonOAEPEncryption = 61,
    DirectoryEncryption = 62,
    LZMACompression = 63,
    PPMdPLusCompression = 63,
    BlowfishEncryption = 63,
    TwofishEncryption = 63,
};

pub const CompressionMethod = enum(u16) {
    NoCompression = 0,
    Shrunk = 1,
    ReducedUsingSompressionFactor1 = 2,
    ReducedUsingSompressionFactor2 = 3,
    ReducedUsingSompressionFactor3 = 4,
    ReducedUsingSompressionFactor4 = 5,
    Imploded = 6,
    ReservedTokenizingCompressionAlgorithm = 7,
    Deflated = 8,
    EnhancedDeflate64 = 9,
    PKWareDCLImploded = 10,
    Reserved01 = 11,
    BZIP2 = 12,
    Reserved02 = 13,
    LZMA = 14,
    Reserved03 = 15,
    IBMCMPSCCompression = 16,
    Reserved04 = 17,
    IBMTerse = 18,
    IBMLZ77Architecture = 19,
    Deprecated = 20,
    ZStandard = 93,
    MP3Compression = 94,
    XZCompression = 95,
    JPEG = 96,
    WavPack = 97,
    PPMd = 98,
    AExEncryption = 99,

    const Self = @This();
    pub fn from(v: u16) Self {
        return @enumFromInt(v);
    }

    pub fn toInt(self: Self) u16 {
        return @as(u16, @intFromEnum(self));
    }
};

pub const AddOptions = struct {
    version_made_by: VersionMadeBy = VersionMadeBy.@"MSDOS_OS/2",
    version_extract_file: VersionExtractFile = VersionExtractFile.Default,
    compression_method: CompressionMethod = CompressionMethod.NoCompression,
};

pub const EncryptionMethod = enum(u3) {
    none = 0,
    password = 1,
    x509 = 2,
};

pub const Encryption = struct {
    method: EncryptionMethod = .none,
    secret: ?[]const u8 = null,
};

pub const ReadOptions = struct {
    encryption: Encryption = .{},
};
