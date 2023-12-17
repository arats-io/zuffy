const std = @import("std");
const Buffer = @import("../../bytes/buffer.zig").Buffer;

const int = @import("../../int.zig");

pub const ExtraFieldHeaderID = enum(u16) {
    Zip64ExtendedInfo = 0x0001,
    AVInfo = 0x0007,
    Reserved01 = 0x0008,
    OS2ExtendedAttributes = 0x0009,
    NTFS = 0x000a,
    OpenVMS = 0x000c,
    UNIX = 0x000d,
    Reserved02 = 0x000e,
    PatchDescriptor = 0x000f,
    StoreForX509Certificates = 0x0014,
    X509CertificateIDAndSignatureForFile = 0x0015,
    X509CertificateIDForCentralDirectory = 0x0016,
    StrongEncryption = 0x0017,
    RecordManagementControls = 0x0018,
    EncryptionRecipientCertificateList = 0x0019,
    ReservedForTimestampRecord = 0x0020,
    PolicyDecryptionKeyRecord = 0x0021,
    SmartcryptKeyProviderRecord = 0x0022,
    SmartcryptPolicyKeyDataRecord = 0x0023,
    IBMSZ390AS400I400Attributes = 0x0065,
    ReservedIBMSZ390AS400I400Attributes = 0x0066,
    POSZIP4690 = 0x4690,
    InfoZIPMacintoshOld = 0x07c8,
    PixarUSD = 0x1986,
    ZipItMacintoshV1 = 0x2605,
    ZipItMacintoshV135 = 0x2705,
    ZipItMacintoshV135Plus = 0x2805,
    InfoZIPMacintoshNew = 0x334d,
    TandemNSK = 0x4154,
    AcornSparkFS = 0x4341,
    WindowsNTSecurityDescriptor = 0x4453,
    VMCMS = 0x4704,
    MVS = 0x470f,
    TheosOld = 0x4854,
    FWKCSMD5 = 0x4b46,
    OS2ACL = 0x4c41,
    InfoZIPOpenVMS = 0x4d49,
    MacintoshSmartZIP = 0x4d63,
    XceedOriginalLocation = 0x4f4c,
    AOSVS = 0x5356,
    ExtendedTimestamp = 0x5455,
    XceedUnicode = 0x554e,
    InfoZIPUNIX = 0x5855,
    InfoZIPUTF8Comment = 0x6375,
    BeOS = 0x6542,
    Theos = 0x6854,
    InfoZIPUTF8Name = 0x7075,
    AtheOS = 0x7441,
    ASiUNIX = 0x756e,
    ZIPUNIX16bitUIDGIDInfo = 0x7855,
    ZIPUNIX3rdGenerationGenericUIDGIDInfo = 0x7875,
    MicrosoftOpenPackagingGrowthHint = 0xa220,
    DataStreamAlignment = 0xa11e,
    JavaJAR = 0xcafe,
    AndroidZIPAlignment = 0xd935,
    KoreanZIPCodePageInfo = 0xe57a,
    SMSQDOS = 0xfd4a,
    AExEncryptionStructure = 0x9901,
    Unknown = 0x9902,

    const Self = @This();
    pub fn from(v: u16) Self {
        return @enumFromInt(v);
    }

    pub fn code(self: Self) u16 {
        return @as(u16, @intFromEnum(self));
    }
};

pub const ExtendedTimestamp = struct {
    pub const CODE = ExtraFieldHeaderID.ExtendedTimestamp.code();

    data_size: u16,
    flags: u8,
    tolm: u32,
};

pub const ZIPUNIX3rdGenerationGenericUIDGIDInfo = struct {
    pub const CODE = ExtraFieldHeaderID.ZIPUNIX3rdGenerationGenericUIDGIDInfo.code();

    data_size: u16,
    version: u8,

    uid_size: u8,
    uid: u32,
    gid_size: u8,
    gid: u32,
};

pub fn parseExtraFields(extra_field: ?Buffer, handler: anytype) !void {
    if (extra_field) |data| {
        var s = std.io.fixedBufferStream(@constCast(&data).bytes());
        var r = s.reader();

        while (true) {
            const header = r.readInt(u16, .little) catch {
                return;
            };
            const dataSize = try r.readInt(u16, .little);

            const headerId = ExtraFieldHeaderID.from(header);
            switch (headerId) {
                .ExtendedTimestamp => {
                    const flags = try r.readInt(u8, .little);
                    const tolm = try r.readInt(u32, .little);

                    try handler.exec(header, &ExtendedTimestamp{
                        .data_size = dataSize,
                        .flags = flags,
                        .tolm = tolm,
                    });
                },
                .ZIPUNIX3rdGenerationGenericUIDGIDInfo => {
                    const vers = try r.readInt(u8, .little);
                    switch (vers) {
                        1 => {
                            const uidSize = try r.readInt(u8, .little);
                            const uid = try r.readInt(u32, .little);

                            const gidSize = try r.readInt(u8, .little);
                            const gid = try r.readInt(u32, .little);

                            try handler.exec(header, &ZIPUNIX3rdGenerationGenericUIDGIDInfo{
                                .data_size = dataSize,
                                .version = vers,
                                .uid_size = uidSize,
                                .uid = uid,
                                .gid_size = gidSize,
                                .gid = gid,
                            });
                        },
                        else => {
                            std.debug.panic("header  {s} decoder not handled for version {!}\n", .{ int.toHexBytes(u16, .lower, header), vers });
                        },
                    }
                },
                else => {
                    std.debug.panic("header {s} decoder not handled\n", .{int.toHexBytes(u16, .lower, header)});
                },
            }
        }
    }
}
