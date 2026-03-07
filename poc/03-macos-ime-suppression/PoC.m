// PoC.m — macOS IME Suppression Proof-of-Concept
//
// Validates that a macOS NSView can:
//   1. Capture raw keycodes directly via keyDown: (bypassing interpretKeyEvents:)
//   2. Still allow system shortcuts via performKeyEquivalent:
//   3. Implement NSTextInputClient for clipboard/services/accessibility
//      WITHOUT having it interfere with keyboard input
//   4. Receive correct raw HID keycodes regardless of macOS input source
//
// This is critical for the it-shell3 project which uses a native Zig IME engine
// (libitshell3-ime) instead of the macOS OS IME system.
//
// Build:
//   cc -fobjc-arc PoC.m -framework Foundation -framework AppKit -framework Carbon -o poc-ime-suppression

#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>
#import <Carbon/Carbon.h>

// ===================================================================
// HID Keycode constants (USB HID Usage Table, Section 10)
// These are the keycodes the IME contract uses (u8, 0x00-0xE7)
// ===================================================================

static const char* hidKeycodeName(uint16_t keyCode) {
    // macOS virtual keycodes (from <Carbon/HIToolbox/Events.h>) to human-readable names.
    // Note: macOS keyCode != HID keycode. macOS uses its own virtual keycode space.
    // The actual HID-to-macOS mapping is done by IOKit/HIDManager.
    // For this PoC, we log the macOS virtual keycode and show the mapping.
    switch (keyCode) {
        case kVK_ANSI_A: return "A (0x00)";
        case kVK_ANSI_S: return "S (0x01)";
        case kVK_ANSI_D: return "D (0x02)";
        case kVK_ANSI_F: return "F (0x03)";
        case kVK_ANSI_H: return "H (0x04)";
        case kVK_ANSI_G: return "G (0x05)";
        case kVK_ANSI_Z: return "Z (0x06)";
        case kVK_ANSI_X: return "X (0x07)";
        case kVK_ANSI_C: return "C (0x08)";
        case kVK_ANSI_V: return "V (0x09)";
        case kVK_ANSI_B: return "B (0x0B)";
        case kVK_ANSI_Q: return "Q (0x0C)";
        case kVK_ANSI_W: return "W (0x0D)";
        case kVK_ANSI_E: return "E (0x0E)";
        case kVK_ANSI_R: return "R (0x0F)";
        case kVK_ANSI_Y: return "Y (0x10)";
        case kVK_ANSI_T: return "T (0x11)";
        case kVK_ANSI_1: return "1 (0x12)";
        case kVK_ANSI_2: return "2 (0x13)";
        case kVK_ANSI_3: return "3 (0x14)";
        case kVK_ANSI_4: return "4 (0x15)";
        case kVK_ANSI_6: return "6 (0x16)";
        case kVK_ANSI_5: return "5 (0x17)";
        case kVK_ANSI_Equal: return "= (0x18)";
        case kVK_ANSI_9: return "9 (0x19)";
        case kVK_ANSI_7: return "7 (0x1A)";
        case kVK_ANSI_Minus: return "- (0x1B)";
        case kVK_ANSI_8: return "8 (0x1C)";
        case kVK_ANSI_0: return "0 (0x1D)";
        case kVK_ANSI_RightBracket: return "] (0x1E)";
        case kVK_ANSI_O: return "O (0x1F)";
        case kVK_ANSI_U: return "U (0x20)";
        case kVK_ANSI_LeftBracket: return "[ (0x21)";
        case kVK_ANSI_I: return "I (0x22)";
        case kVK_ANSI_P: return "P (0x23)";
        case kVK_Return: return "Return (0x24)";
        case kVK_ANSI_L: return "L (0x25)";
        case kVK_ANSI_J: return "J (0x26)";
        case kVK_ANSI_Quote: return "' (0x27)";
        case kVK_ANSI_K: return "K (0x28)";
        case kVK_ANSI_Semicolon: return "; (0x29)";
        case kVK_ANSI_Backslash: return "\\ (0x2A)";
        case kVK_ANSI_Comma: return ", (0x2B)";
        case kVK_ANSI_Slash: return "/ (0x2C)";
        case kVK_ANSI_N: return "N (0x2D)";
        case kVK_ANSI_M: return "M (0x2E)";
        case kVK_ANSI_Period: return ". (0x2F)";
        case kVK_Tab: return "Tab (0x30)";
        case kVK_Space: return "Space (0x31)";
        case kVK_ANSI_Grave: return "` (0x32)";
        case kVK_Delete: return "Delete/Backspace (0x33)";
        case kVK_Escape: return "Escape (0x35)";
        case kVK_RightCommand: return "RightCmd (0x36)";
        case kVK_Command: return "LeftCmd (0x37)";
        case kVK_Shift: return "LeftShift (0x38)";
        case kVK_CapsLock: return "CapsLock (0x39)";
        case kVK_Option: return "LeftOption (0x3A)";
        case kVK_Control: return "LeftControl (0x3B)";
        case kVK_RightShift: return "RightShift (0x3C)";
        case kVK_RightOption: return "RightOption (0x3D)";
        case kVK_RightControl: return "RightControl (0x3E)";
        case kVK_Function: return "Fn (0x3F)";
        case kVK_F17: return "F17 (0x40)";
        case kVK_ANSI_KeypadDecimal: return "Keypad. (0x41)";
        case kVK_ANSI_KeypadMultiply: return "Keypad* (0x43)";
        case kVK_ANSI_KeypadPlus: return "Keypad+ (0x45)";
        case kVK_ANSI_KeypadClear: return "KeypadClear (0x47)";
        case kVK_VolumeUp: return "VolumeUp (0x48)";
        case kVK_VolumeDown: return "VolumeDown (0x49)";
        case kVK_Mute: return "Mute (0x4A)";
        case kVK_ANSI_KeypadDivide: return "Keypad/ (0x4B)";
        case kVK_ANSI_KeypadEnter: return "KeypadEnter (0x4C)";
        case kVK_ANSI_KeypadMinus: return "Keypad- (0x4E)";
        case kVK_F5: return "F5 (0x60)";
        case kVK_F6: return "F6 (0x61)";
        case kVK_F7: return "F7 (0x62)";
        case kVK_F3: return "F3 (0x63)";
        case kVK_F8: return "F8 (0x64)";
        case kVK_F9: return "F9 (0x65)";
        case kVK_F11: return "F11 (0x67)";
        case kVK_F13: return "F13 (0x69)";
        case kVK_F16: return "F16 (0x6A)";
        case kVK_F14: return "F14 (0x6B)";
        case kVK_F10: return "F10 (0x6D)";
        case kVK_F12: return "F12 (0x6F)";
        case kVK_F15: return "F15 (0x71)";
        case kVK_Help: return "Help (0x72)";
        case kVK_Home: return "Home (0x73)";
        case kVK_PageUp: return "PageUp (0x74)";
        case kVK_ForwardDelete: return "ForwardDelete (0x75)";
        case kVK_F4: return "F4 (0x76)";
        case kVK_End: return "End (0x77)";
        case kVK_F2: return "F2 (0x78)";
        case kVK_PageDown: return "PageDown (0x79)";
        case kVK_F1: return "F1 (0x7A)";
        case kVK_LeftArrow: return "LeftArrow (0x7B)";
        case kVK_RightArrow: return "RightArrow (0x7C)";
        case kVK_DownArrow: return "DownArrow (0x7D)";
        case kVK_UpArrow: return "UpArrow (0x7E)";
        default: return "Unknown";
    }
}

// ===================================================================
// Modifier flags to human-readable string
// ===================================================================

static NSString* modifierString(NSEventModifierFlags flags) {
    NSMutableArray *parts = [NSMutableArray array];
    if (flags & NSEventModifierFlagShift)   [parts addObject:@"Shift"];
    if (flags & NSEventModifierFlagControl) [parts addObject:@"Ctrl"];
    if (flags & NSEventModifierFlagOption)  [parts addObject:@"Alt/Opt"];
    if (flags & NSEventModifierFlagCommand) [parts addObject:@"Cmd"];
    if (flags & NSEventModifierFlagCapsLock) [parts addObject:@"CapsLock"];
    if (flags & NSEventModifierFlagFunction) [parts addObject:@"Fn"];
    if ([parts count] == 0) return @"(none)";
    return [parts componentsJoinedByString:@"+"];
}

// ===================================================================
// macOS virtual keycode to HID keycode mapping
// ===================================================================

// macOS virtual keycodes are NOT the same as USB HID keycodes.
// This table maps macOS keyCode (from NSEvent) to USB HID Usage ID.
// This is the mapping that libitshell3-ime will need to perform.

static uint8_t macVKToHID(uint16_t vk) {
    // Mapping table: macOS virtual keycode -> USB HID keycode
    // Source: Apple TN2450 (Remapping Keys in macOS 10.12 Sierra)
    static const uint8_t map[128] = {
        // 0x00-0x0F
        [kVK_ANSI_A] = 0x04,        // 0x00 -> HID A
        [kVK_ANSI_S] = 0x16,        // 0x01 -> HID S
        [kVK_ANSI_D] = 0x07,        // 0x02 -> HID D
        [kVK_ANSI_F] = 0x09,        // 0x03 -> HID F
        [kVK_ANSI_H] = 0x0B,        // 0x04 -> HID H
        [kVK_ANSI_G] = 0x0A,        // 0x05 -> HID G
        [kVK_ANSI_Z] = 0x1D,        // 0x06 -> HID Z
        [kVK_ANSI_X] = 0x1B,        // 0x07 -> HID X
        [kVK_ANSI_C] = 0x06,        // 0x08 -> HID C
        [kVK_ANSI_V] = 0x19,        // 0x09 -> HID V
        // 0x0A is kVK_ISO_Section (international)
        [kVK_ANSI_B] = 0x05,        // 0x0B -> HID B
        [kVK_ANSI_Q] = 0x14,        // 0x0C -> HID Q
        [kVK_ANSI_W] = 0x1A,        // 0x0D -> HID W
        [kVK_ANSI_E] = 0x08,        // 0x0E -> HID E
        [kVK_ANSI_R] = 0x15,        // 0x0F -> HID R

        // 0x10-0x1F
        [kVK_ANSI_Y] = 0x1C,        // 0x10 -> HID Y
        [kVK_ANSI_T] = 0x17,        // 0x11 -> HID T
        [kVK_ANSI_1] = 0x1E,        // 0x12 -> HID 1
        [kVK_ANSI_2] = 0x1F,        // 0x13 -> HID 2
        [kVK_ANSI_3] = 0x20,        // 0x14 -> HID 3
        [kVK_ANSI_4] = 0x21,        // 0x15 -> HID 4
        [kVK_ANSI_6] = 0x23,        // 0x16 -> HID 6
        [kVK_ANSI_5] = 0x22,        // 0x17 -> HID 5
        [kVK_ANSI_Equal] = 0x2E,    // 0x18 -> HID =
        [kVK_ANSI_9] = 0x26,        // 0x19 -> HID 9
        [kVK_ANSI_7] = 0x24,        // 0x1A -> HID 7
        [kVK_ANSI_Minus] = 0x2D,    // 0x1B -> HID -
        [kVK_ANSI_8] = 0x25,        // 0x1C -> HID 8
        [kVK_ANSI_0] = 0x27,        // 0x1D -> HID 0
        [kVK_ANSI_RightBracket] = 0x30, // 0x1E -> HID ]
        [kVK_ANSI_O] = 0x12,        // 0x1F -> HID O

        // 0x20-0x2F
        [kVK_ANSI_U] = 0x18,        // 0x20 -> HID U
        [kVK_ANSI_LeftBracket] = 0x2F, // 0x21 -> HID [
        [kVK_ANSI_I] = 0x0C,        // 0x22 -> HID I
        [kVK_ANSI_P] = 0x13,        // 0x23 -> HID P
        [kVK_Return] = 0x28,        // 0x24 -> HID Enter
        [kVK_ANSI_L] = 0x0F,        // 0x25 -> HID L
        [kVK_ANSI_J] = 0x0D,        // 0x26 -> HID J
        [kVK_ANSI_Quote] = 0x34,    // 0x27 -> HID '
        [kVK_ANSI_K] = 0x0E,        // 0x28 -> HID K
        [kVK_ANSI_Semicolon] = 0x33, // 0x29 -> HID ;
        [kVK_ANSI_Backslash] = 0x31, // 0x2A -> HID backslash
        [kVK_ANSI_Comma] = 0x36,    // 0x2B -> HID ,
        [kVK_ANSI_Slash] = 0x38,    // 0x2C -> HID /
        [kVK_ANSI_N] = 0x11,        // 0x2D -> HID N
        [kVK_ANSI_M] = 0x10,        // 0x2E -> HID M
        [kVK_ANSI_Period] = 0x37,   // 0x2F -> HID .

        // 0x30-0x3F
        [kVK_Tab] = 0x2B,           // 0x30 -> HID Tab
        [kVK_Space] = 0x2C,         // 0x31 -> HID Space
        [kVK_ANSI_Grave] = 0x35,    // 0x32 -> HID `
        [kVK_Delete] = 0x2A,        // 0x33 -> HID Backspace
        // 0x34 unused
        [kVK_Escape] = 0x29,        // 0x35 -> HID Escape

        // Modifier keys (0x36-0x3F) - mapped for completeness but
        // typically handled via flagsChanged:, not keyDown:
        [kVK_RightCommand] = 0xE7,  // 0x36
        [kVK_Command] = 0xE3,       // 0x37 -> HID Left GUI
        [kVK_Shift] = 0xE1,         // 0x38 -> HID Left Shift
        [kVK_CapsLock] = 0x39,      // 0x39 -> HID Caps Lock
        [kVK_Option] = 0xE2,        // 0x3A -> HID Left Alt
        [kVK_Control] = 0xE0,       // 0x3B -> HID Left Control
        [kVK_RightShift] = 0xE5,    // 0x3C -> HID Right Shift
        [kVK_RightOption] = 0xE6,   // 0x3D -> HID Right Alt
        [kVK_RightControl] = 0xE4,  // 0x3E -> HID Right Control
        [kVK_Function] = 0x00,      // 0x3F -> no HID equivalent
    };

    if (vk < 128) {
        return map[vk];
    }

    // Extended keycodes (arrow keys, function keys, etc.)
    // These are above 0x60 in macOS virtual keycode space
    switch (vk) {
        case kVK_F5:            return 0x3E;
        case kVK_F6:            return 0x3F;
        case kVK_F7:            return 0x40;
        case kVK_F3:            return 0x3C;
        case kVK_F8:            return 0x41;
        case kVK_F9:            return 0x42;
        case kVK_F11:           return 0x44;
        case kVK_F13:           return 0x68;
        case kVK_F16:           return 0x6B;
        case kVK_F14:           return 0x69;
        case kVK_F10:           return 0x43;
        case kVK_F12:           return 0x45;
        case kVK_F15:           return 0x6A;
        case kVK_Home:          return 0x4A;
        case kVK_PageUp:        return 0x4B;
        case kVK_ForwardDelete: return 0x4C;
        case kVK_F4:            return 0x3D;
        case kVK_End:           return 0x4D;
        case kVK_F2:            return 0x3B;
        case kVK_PageDown:      return 0x4E;
        case kVK_F1:            return 0x3A;
        case kVK_LeftArrow:     return 0x50;
        case kVK_RightArrow:    return 0x4F;
        case kVK_DownArrow:     return 0x51;
        case kVK_UpArrow:       return 0x52;
        default:                return 0x00;
    }
}

// ===================================================================
// Get current macOS input source name
// ===================================================================

static NSString* currentInputSourceName(void) {
    TISInputSourceRef src = TISCopyCurrentKeyboardInputSource();
    if (!src) return @"(unknown)";
    // TISGetInputSourceProperty returns unowned CF references -- use __bridge (NOT __bridge_transfer)
    NSString *name = (__bridge NSString *)TISGetInputSourceProperty(src, kTISPropertyLocalizedName);
    NSString *sourceId = (__bridge NSString *)TISGetInputSourceProperty(src, kTISPropertyInputSourceID);
    NSString *result = [NSString stringWithFormat:@"%@ [%@]", name ?: @"?", sourceId ?: @"?"];
    CFRelease(src);
    return result;
}

// ===================================================================
// Log entry structure for the in-window display
// ===================================================================

@interface LogEntry : NSObject
@property (nonatomic, copy) NSString *text;
@property (nonatomic, strong) NSColor *color;
+ (instancetype)entryWithText:(NSString *)text color:(NSColor *)color;
@end

@implementation LogEntry
+ (instancetype)entryWithText:(NSString *)text color:(NSColor *)color {
    LogEntry *e = [[LogEntry alloc] init];
    e.text = text;
    e.color = color;
    return e;
}
@end

// ===================================================================
// KeyCaptureView — The main test view
//
// Key design:
//   - Overrides keyDown: directly (does NOT call interpretKeyEvents:)
//   - Overrides performKeyEquivalent: for system shortcuts
//   - Implements NSTextInputClient for clipboard/services/accessibility
//   - Overrides flagsChanged: for modifier-only key events
// ===================================================================

@interface KeyCaptureView : NSView <NSTextInputClient>
@property (nonatomic, strong) NSMutableArray<LogEntry *> *logEntries;
@property (nonatomic) NSUInteger maxLogEntries;

// Tracks how many times each NSTextInputClient method was called
// to verify that keyboard input does NOT route through them
@property (nonatomic) NSUInteger insertTextCallCount;
@property (nonatomic) NSUInteger setMarkedTextCallCount;
@property (nonatomic) NSUInteger hasMarkedTextCallCount;

// Track the last few raw keyDown events for verification
@property (nonatomic, strong) NSMutableArray<NSDictionary *> *recentKeyEvents;
@end

@implementation KeyCaptureView

- (instancetype)initWithFrame:(NSRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        _logEntries = [NSMutableArray array];
        _maxLogEntries = 40;
        _recentKeyEvents = [NSMutableArray array];
        _insertTextCallCount = 0;
        _setMarkedTextCallCount = 0;
        _hasMarkedTextCallCount = 0;
    }
    return self;
}

// -----------------------------------------------------------------
// Accept first responder so we receive key events
// -----------------------------------------------------------------

- (BOOL)acceptsFirstResponder {
    return YES;
}

- (BOOL)canBecomeKeyView {
    return YES;
}

// -----------------------------------------------------------------
// Logging helpers
// -----------------------------------------------------------------

- (void)addLogEntry:(NSString *)text color:(NSColor *)color {
    [self.logEntries addObject:[LogEntry entryWithText:text color:color]];
    while (self.logEntries.count > self.maxLogEntries) {
        [self.logEntries removeObjectAtIndex:0];
    }
    [self setNeedsDisplay:YES];
}

- (void)logInfo:(NSString *)text {
    NSLog(@"%@", text);
    [self addLogEntry:text color:[NSColor labelColor]];
}

- (void)logKey:(NSString *)text {
    NSLog(@"[KEY] %@", text);
    [self addLogEntry:text color:[NSColor systemGreenColor]];
}

- (void)logModifier:(NSString *)text {
    NSLog(@"[MOD] %@", text);
    [self addLogEntry:text color:[NSColor systemOrangeColor]];
}

- (void)logEquivalent:(NSString *)text {
    NSLog(@"[EQV] %@", text);
    [self addLogEntry:text color:[NSColor systemBlueColor]];
}

- (void)logNSTextInput:(NSString *)text {
    NSLog(@"[TIC] %@", text);
    [self addLogEntry:text color:[NSColor systemRedColor]];
}

// -----------------------------------------------------------------
// Drawing — Display the log entries in the view
// -----------------------------------------------------------------

- (void)drawRect:(NSRect)dirtyRect {
    [[NSColor colorWithWhite:0.1 alpha:1.0] setFill];
    NSRectFill(dirtyRect);

    // Draw header
    NSString *header = @"=== macOS IME Suppression PoC ===";
    NSString *subheader = [NSString stringWithFormat:@"Input Source: %@", currentInputSourceName()];
    NSString *instructions = @"Type keys to test. Cmd+Q to quit. Green=keyDown, Orange=modifier, Blue=performKeyEquivalent, Red=NSTextInputClient";

    NSDictionary *headerAttrs = @{
        NSFontAttributeName: [NSFont boldSystemFontOfSize:14],
        NSForegroundColorAttributeName: [NSColor whiteColor]
    };
    NSDictionary *subAttrs = @{
        NSFontAttributeName: [NSFont systemFontOfSize:11],
        NSForegroundColorAttributeName: [NSColor systemYellowColor]
    };
    NSDictionary *instrAttrs = @{
        NSFontAttributeName: [NSFont systemFontOfSize:10],
        NSForegroundColorAttributeName: [NSColor systemGrayColor]
    };

    CGFloat y = self.bounds.size.height - 20;
    [header drawAtPoint:NSMakePoint(10, y) withAttributes:headerAttrs];
    y -= 16;
    [subheader drawAtPoint:NSMakePoint(10, y) withAttributes:subAttrs];
    y -= 14;
    [instructions drawAtPoint:NSMakePoint(10, y) withAttributes:instrAttrs];
    y -= 8;

    // Draw stats line
    NSString *stats = [NSString stringWithFormat:
        @"NSTextInputClient calls - insertText: %lu, setMarkedText: %lu, hasMarkedText: %lu",
        (unsigned long)self.insertTextCallCount,
        (unsigned long)self.setMarkedTextCallCount,
        (unsigned long)self.hasMarkedTextCallCount];
    NSDictionary *statsAttrs = @{
        NSFontAttributeName: [NSFont monospacedSystemFontOfSize:10 weight:NSFontWeightRegular],
        NSForegroundColorAttributeName: (self.insertTextCallCount == 0 && self.setMarkedTextCallCount == 0)
            ? [NSColor systemGreenColor]
            : [NSColor systemRedColor]
    };
    y -= 14;
    [stats drawAtPoint:NSMakePoint(10, y) withAttributes:statsAttrs];
    y -= 6;

    // Draw separator
    y -= 4;
    [[NSColor grayColor] setStroke];
    NSBezierPath *sep = [NSBezierPath bezierPath];
    [sep moveToPoint:NSMakePoint(10, y)];
    [sep lineToPoint:NSMakePoint(self.bounds.size.width - 10, y)];
    [sep stroke];
    y -= 8;

    // Draw log entries (newest at top)
    NSDictionary *defaultAttrs = @{
        NSFontAttributeName: [NSFont monospacedSystemFontOfSize:11 weight:NSFontWeightRegular]
    };

    for (NSInteger i = self.logEntries.count - 1; i >= 0 && y > 10; i--) {
        LogEntry *entry = self.logEntries[i];
        NSMutableDictionary *attrs = [defaultAttrs mutableCopy];
        attrs[NSForegroundColorAttributeName] = entry.color;
        [entry.text drawAtPoint:NSMakePoint(10, y) withAttributes:attrs];
        y -= 15;
    }
}

// =================================================================
// TEST 1: Raw keycode capture via keyDown:
//
// CRITICAL: We do NOT call [self interpretKeyEvents:@[event]]
// This means macOS will NOT route the key through the OS IME system.
// The raw keycode and characters are captured directly.
// =================================================================

- (void)keyDown:(NSEvent *)event {
    // Do NOT call: [self interpretKeyEvents:@[event]];
    // This is the entire point of the PoC.

    uint16_t keyCode = event.keyCode;
    uint8_t hidCode = macVKToHID(keyCode);
    NSString *chars = event.characters ?: @"(nil)";
    NSString *charsNoMod = event.charactersIgnoringModifiers ?: @"(nil)";
    NSEventModifierFlags mods = event.modifierFlags;
    BOOL isRepeat = event.isARepeat;

    // Log the event
    NSString *logMsg = [NSString stringWithFormat:
        @"keyDown: vk=0x%02X hid=0x%02X '%s' chars='%@' nomod='%@' mods=%@ %@",
        keyCode, hidCode, hidKeycodeName(keyCode),
        chars, charsNoMod,
        modifierString(mods),
        isRepeat ? @"[REPEAT]" : @""];

    [self logKey:logMsg];

    // Also log Unicode codepoints for CJK verification
    if (chars.length > 0 && ![chars isEqualToString:@"(nil)"]) {
        NSMutableString *codepoints = [NSMutableString stringWithString:@"  codepoints:"];
        for (NSUInteger i = 0; i < chars.length; i++) {
            unichar ch = [chars characterAtIndex:i];
            [codepoints appendFormat:@" U+%04X", ch];
        }
        [self logKey:codepoints];
    }

    // Store for verification
    NSDictionary *keyInfo = @{
        @"keyCode": @(keyCode),
        @"hidCode": @(hidCode),
        @"characters": chars,
        @"charactersIgnoringModifiers": charsNoMod,
        @"modifiers": @(mods),
        @"isRepeat": @(isRepeat),
        @"timestamp": @(event.timestamp)
    };
    [self.recentKeyEvents addObject:keyInfo];
    if (self.recentKeyEvents.count > 20) {
        [self.recentKeyEvents removeObjectAtIndex:0];
    }
}

// =================================================================
// TEST 1b: keyUp: — Log for completeness
// =================================================================

- (void)keyUp:(NSEvent *)event {
    uint16_t keyCode = event.keyCode;
    NSLog(@"keyUp: vk=0x%02X '%s'", keyCode, hidKeycodeName(keyCode));
    // Not displayed in window to reduce noise, but logged for debugging
}

// =================================================================
// TEST 1c: flagsChanged: — Modifier-only key events
//
// When the user presses/releases Shift, Ctrl, Alt, Cmd without
// any other key, macOS sends flagsChanged: instead of keyDown:.
// This is important for the IME contract's modifier flush policy.
// =================================================================

- (void)flagsChanged:(NSEvent *)event {
    uint16_t keyCode = event.keyCode;
    uint8_t hidCode = macVKToHID(keyCode);
    NSEventModifierFlags mods = event.modifierFlags;

    NSString *logMsg = [NSString stringWithFormat:
        @"flagsChanged: vk=0x%02X hid=0x%02X '%s' mods=%@",
        keyCode, hidCode, hidKeycodeName(keyCode),
        modifierString(mods)];

    [self logModifier:logMsg];
}

// =================================================================
// TEST 2: System shortcuts via performKeyEquivalent:
//
// performKeyEquivalent: is called BEFORE keyDown: for key events
// with Cmd modifier. We return YES for system shortcuts to let
// AppKit handle them (Cmd+Q, Cmd+H, etc.), NO for others so
// they fall through to keyDown:.
// =================================================================

- (BOOL)performKeyEquivalent:(NSEvent *)event {
    // Only handle keyDown events
    if (event.type != NSEventTypeKeyDown) return NO;

    uint16_t keyCode = event.keyCode;
    NSEventModifierFlags mods = event.modifierFlags;

    // Log all performKeyEquivalent calls
    NSString *logMsg = [NSString stringWithFormat:
        @"performKeyEquivalent: vk=0x%02X '%s' chars='%@' mods=%@",
        keyCode, hidKeycodeName(keyCode),
        event.charactersIgnoringModifiers ?: @"(nil)",
        modifierString(mods)];

    [self logEquivalent:logMsg];

    // For system shortcuts with Cmd, let AppKit handle them
    if (mods & NSEventModifierFlagCommand) {
        NSString *chars = event.charactersIgnoringModifiers;

        // Cmd+Q — Quit
        if ([chars isEqualToString:@"q"]) {
            [self logEquivalent:@"  -> System shortcut Cmd+Q (quit) — passing to AppKit"];
            return NO; // Let AppKit handle Cmd+Q
        }
        // Cmd+H — Hide
        if ([chars isEqualToString:@"h"]) {
            [self logEquivalent:@"  -> System shortcut Cmd+H (hide) — passing to AppKit"];
            return NO;
        }
        // Cmd+W — Close window
        if ([chars isEqualToString:@"w"]) {
            [self logEquivalent:@"  -> System shortcut Cmd+W (close) — passing to AppKit"];
            return NO;
        }
        // Cmd+M — Minimize
        if ([chars isEqualToString:@"m"]) {
            [self logEquivalent:@"  -> System shortcut Cmd+M (minimize) — passing to AppKit"];
            return NO;
        }
        // Cmd+C — Copy
        if ([chars isEqualToString:@"c"]) {
            [self logEquivalent:@"  -> System shortcut Cmd+C (copy) — passing to AppKit"];
            return NO;
        }
        // Cmd+V — Paste
        if ([chars isEqualToString:@"v"]) {
            [self logEquivalent:@"  -> System shortcut Cmd+V (paste) — passing to AppKit"];
            return NO;
        }
        // Cmd+X — Cut
        if ([chars isEqualToString:@"x"]) {
            [self logEquivalent:@"  -> System shortcut Cmd+X (cut) — passing to AppKit"];
            return NO;
        }
        // Cmd+A — Select All
        if ([chars isEqualToString:@"a"]) {
            [self logEquivalent:@"  -> System shortcut Cmd+A (select all) — passing to AppKit"];
            return NO;
        }

        // All other Cmd+key combos: we consume them (return YES)
        // and they will NOT go to keyDown
        [self logEquivalent:@"  -> Consumed by PoC (would go to IME engine in production)"];
        return YES;
    }

    // Non-Cmd key equivalents: let them fall through to keyDown:
    return NO;
}

// =================================================================
// TEST 3: NSTextInputClient protocol implementation
//
// These methods exist ONLY for clipboard/services/accessibility.
// If interpretKeyEvents: is never called, macOS should NOT invoke
// insertText: or setMarkedText: during keyboard input.
//
// We track call counts to verify this invariant.
// =================================================================

// --- Required NSTextInputClient methods ---

- (void)insertText:(id)string replacementRange:(NSRange)replacementRange {
    self.insertTextCallCount++;

    NSString *text = nil;
    if ([string isKindOfClass:[NSAttributedString class]]) {
        text = [(NSAttributedString *)string string];
    } else if ([string isKindOfClass:[NSString class]]) {
        text = (NSString *)string;
    } else {
        text = [NSString stringWithFormat:@"(unknown type: %@)", [string class]];
    }

    [self logNSTextInput:[NSString stringWithFormat:
        @"insertText: '%@' range={%lu,%lu} [call #%lu]",
        text,
        (unsigned long)replacementRange.location,
        (unsigned long)replacementRange.length,
        (unsigned long)self.insertTextCallCount]];
}

- (void)setMarkedText:(id)string selectedRange:(NSRange)selectedRange replacementRange:(NSRange)replacementRange {
    self.setMarkedTextCallCount++;

    NSString *text = nil;
    if ([string isKindOfClass:[NSAttributedString class]]) {
        text = [(NSAttributedString *)string string];
    } else if ([string isKindOfClass:[NSString class]]) {
        text = (NSString *)string;
    } else {
        text = [NSString stringWithFormat:@"(unknown type: %@)", [string class]];
    }

    [self logNSTextInput:[NSString stringWithFormat:
        @"setMarkedText: '%@' sel={%lu,%lu} repl={%lu,%lu} [call #%lu]",
        text,
        (unsigned long)selectedRange.location,
        (unsigned long)selectedRange.length,
        (unsigned long)replacementRange.location,
        (unsigned long)replacementRange.length,
        (unsigned long)self.setMarkedTextCallCount]];
}

- (void)unmarkText {
    [self logNSTextInput:@"unmarkText called"];
}

- (BOOL)hasMarkedText {
    self.hasMarkedTextCallCount++;
    // Always return NO — we never have OS-managed marked text
    // because we handle composition ourselves via libitshell3-ime
    return NO;
}

- (NSRange)selectedRange {
    // Return empty range — no selection in our context
    return NSMakeRange(NSNotFound, 0);
}

- (NSRange)markedRange {
    // Return empty range — no OS-managed marked text
    return NSMakeRange(NSNotFound, 0);
}

- (NSAttributedString *)attributedSubstringForProposedRange:(NSRange)range actualRange:(NSRangePointer)actualRange {
    // Return nil — we don't expose terminal content to NSTextInputClient.
    // Accessibility is handled separately via NSAccessibility protocol.
    return nil;
}

- (NSArray<NSAttributedStringKey> *)validAttributesForMarkedText {
    return @[];
}

- (NSRect)firstRectForCharacterRange:(NSRange)range actualRange:(NSRangePointer)actualRange {
    // Return a rect near the cursor for Services menu positioning.
    // In production, this would return the cursor position in screen coordinates.
    NSRect windowFrame = self.window.frame;
    NSRect viewFrame = [self convertRect:self.bounds toView:nil];
    NSRect screenRect = [self.window convertRectToScreen:viewFrame];
    return NSMakeRect(screenRect.origin.x + 20, screenRect.origin.y + 20, 10, 15);
}

- (NSUInteger)characterIndexForPoint:(NSPoint)point {
    return 0;
}

// =================================================================
// TEST 4: Verify no interference
//
// This is validated by the call count tracking above.
// If insertTextCallCount and setMarkedTextCallCount remain 0
// during keyboard input, it proves that NOT calling
// interpretKeyEvents: successfully prevents macOS from routing
// keyboard events through NSTextInputClient.
// =================================================================

// Additional: Override inputContext to return nil, ensuring no input method
// context is associated. This is an extra safety measure.
// NOTE: We intentionally DO return an input context so that Services menu
// and accessibility still work. The key insight is that NOT calling
// interpretKeyEvents: is sufficient — we don't need to disable the
// input context entirely.

// (Uncomment the following to test the nuclear option of no input context:)
// - (NSTextInputContext *)inputContext {
//     return nil;
// }

@end

// ===================================================================
// Application delegate
// ===================================================================

@interface AppDelegate : NSObject <NSApplicationDelegate>
@property (nonatomic, strong) NSWindow *window;
@property (nonatomic, strong) KeyCaptureView *captureView;
@end

@implementation AppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    // Create window
    NSRect frame = NSMakeRect(200, 200, 900, 700);
    self.window = [[NSWindow alloc]
        initWithContentRect:frame
                  styleMask:(NSWindowStyleMaskTitled |
                             NSWindowStyleMaskClosable |
                             NSWindowStyleMaskMiniaturizable |
                             NSWindowStyleMaskResizable)
                    backing:NSBackingStoreBuffered
                      defer:NO];
    [self.window setTitle:@"macOS IME Suppression PoC"];

    // Create the key capture view
    self.captureView = [[KeyCaptureView alloc] initWithFrame:frame];
    [self.window setContentView:self.captureView];

    // Make the view the first responder
    [self.window makeFirstResponder:self.captureView];
    [self.window makeKeyAndOrderFront:nil];

    // Activate the app
    [NSApp activateIgnoringOtherApps:YES];

    // Log startup info
    NSLog(@"=== macOS IME Suppression PoC ===");
    NSLog(@"Current input source: %@", currentInputSourceName());
    NSLog(@"");
    NSLog(@"Test plan:");
    NSLog(@"  1. Type regular letters (a-z) — verify keyDown receives raw keycodes");
    NSLog(@"  2. Type with Shift (A-Z) — verify shift state is captured");
    NSLog(@"  3. Switch to Korean input source and type — verify raw keycodes are same");
    NSLog(@"     (macOS should NOT compose hangul since interpretKeyEvents is not called)");
    NSLog(@"  4. Press Cmd+Q — verify performKeyEquivalent fires");
    NSLog(@"  5. Press Ctrl+C — verify keyDown receives with Ctrl modifier");
    NSLog(@"  6. Check that NSTextInputClient call counts remain 0");
    NSLog(@"");

    [self.captureView logInfo:@"--- App started ---"];
    [self.captureView logInfo:[NSString stringWithFormat:@"Input source: %@", currentInputSourceName()]];
    [self.captureView logInfo:@"Type keys to test. See Terminal for full logs."];
    [self.captureView logInfo:@""];

    // Set up a timer to periodically update the input source display
    [NSTimer scheduledTimerWithTimeInterval:2.0
                                    target:self
                                  selector:@selector(checkInputSource:)
                                  userInfo:nil
                                   repeats:YES];
}

- (void)checkInputSource:(NSTimer *)timer {
    // Refresh the display in case the input source changed
    [self.captureView setNeedsDisplay:YES];
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)app {
    return YES;
}

@end

// ===================================================================
// Main
// ===================================================================

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        NSApplication *app = [NSApplication sharedApplication];
        [app setActivationPolicy:NSApplicationActivationPolicyRegular];

        // Set up a basic menu with Cmd+Q
        NSMenu *mainMenu = [[NSMenu alloc] init];
        NSMenuItem *appMenuItem = [[NSMenuItem alloc] init];
        [mainMenu addItem:appMenuItem];

        NSMenu *appMenu = [[NSMenu alloc] initWithTitle:@"PoC"];
        NSMenuItem *quitItem = [[NSMenuItem alloc]
            initWithTitle:@"Quit"
                   action:@selector(terminate:)
            keyEquivalent:@"q"];
        [appMenu addItem:quitItem];
        [appMenuItem setSubmenu:appMenu];

        // Add Edit menu for clipboard operations (Cmd+C, Cmd+V, Cmd+X)
        NSMenuItem *editMenuItem = [[NSMenuItem alloc] init];
        [mainMenu addItem:editMenuItem];

        NSMenu *editMenu = [[NSMenu alloc] initWithTitle:@"Edit"];
        [editMenu addItemWithTitle:@"Cut" action:@selector(cut:) keyEquivalent:@"x"];
        [editMenu addItemWithTitle:@"Copy" action:@selector(copy:) keyEquivalent:@"c"];
        [editMenu addItemWithTitle:@"Paste" action:@selector(paste:) keyEquivalent:@"v"];
        [editMenu addItemWithTitle:@"Select All" action:@selector(selectAll:) keyEquivalent:@"a"];
        [editMenuItem setSubmenu:editMenu];

        [app setMainMenu:mainMenu];

        AppDelegate *delegate = [[AppDelegate alloc] init];
        [app setDelegate:delegate];

        [app run];
    }
    return 0;
}
