//! Root module for the libitshell3 library. Re-exports all named sub-modules
//! for use by the daemon binary and test discovery.

pub const core = @import("itshell3_core");
pub const server = @import("itshell3_server");
pub const input = @import("itshell3_input");
pub const testing_mod = @import("itshell3_testing");
pub const ghostty_helpers = @import("itshell3_ghostty");
pub const protocol = @import("itshell3_protocol");
