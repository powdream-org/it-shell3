//! libitshell3-protocol-v2: Wire protocol library for it-shell3.
//! Defines message types, header encoding, JSON/binary serialization,
//! and frame reader/writer.

test {
    @import("std").testing.refAllDecls(@This());
}
