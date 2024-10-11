pub const Compression = enum(u3) {
    none = 0,
    gzip = 1,
    snappy = 2,
    lzw = 3,
};
