//! Spec compliance tests: Wire-to-KeyEvent decomposition.
//!
//! Spec source: daemon-architecture integration-boundaries Wire-to-KeyEvent table.

const std = @import("std");
const input = @import("itshell3_input");
const core = @import("itshell3_core");
const KeyEvent = core.KeyEvent;

test "spec: wire decompose — bit 0 maps to shift" {
    const k = input.decomposeWireEvent(0x04, 0x01, .press);
    try std.testing.expect(k.shift);
    try std.testing.expect(!k.modifiers.ctrl);
}

test "spec: wire decompose — bit 1 maps to ctrl" {
    const k = input.decomposeWireEvent(0x04, 0x02, .press);
    try std.testing.expect(k.modifiers.ctrl);
    try std.testing.expect(!k.shift);
}

test "spec: wire decompose — bit 2 maps to alt" {
    const k = input.decomposeWireEvent(0x04, 0x04, .press);
    try std.testing.expect(k.modifiers.alt);
}

test "spec: wire decompose — bit 3 maps to super_key" {
    const k = input.decomposeWireEvent(0x04, 0x08, .press);
    try std.testing.expect(k.modifiers.super_key);
}

test "spec: wire decompose — bits 4-5 CapsLock NumLock not consumed" {
    const k = input.decomposeWireEvent(0x04, 0x30, .press);
    try std.testing.expect(!k.shift);
    try std.testing.expect(!k.modifiers.ctrl);
    try std.testing.expect(!k.modifiers.alt);
    try std.testing.expect(!k.modifiers.super_key);
}

test "spec: wire decompose — all modifier bits combined" {
    const k = input.decomposeWireEvent(0x15, 0x3F, .press);
    try std.testing.expect(k.shift);
    try std.testing.expect(k.modifiers.ctrl);
    try std.testing.expect(k.modifiers.alt);
    try std.testing.expect(k.modifiers.super_key);
    try std.testing.expectEqual(@as(u16, 0x15), k.hid_keycode);
}

test "spec: wire decompose — hid_keycode and action pass through" {
    const k = input.decomposeWireEvent(0x28, 0x00, .repeat);
    try std.testing.expectEqual(@as(u16, 0x28), k.hid_keycode);
    try std.testing.expect(k.action == .repeat);
}
