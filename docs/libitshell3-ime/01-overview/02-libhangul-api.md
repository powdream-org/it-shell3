# libhangul C API Reference

## Repository

- **Source**: https://github.com/libhangul/libhangul
- **Version**: 0.2.0 (May 2025)
- **License**: LGPL-2.1-or-later
- **Language**: C (91.6%)
- **Source files**: 4 files in `hangul/`: `hangulctype.c`, `hangulinputcontext.c`, `hangulkeyboard.c`, `hanja.c`

---

## Core Types

```c
typedef uint32_t ucschar;  // UCS-4/UTF-32 character

// All string returns are ucschar* (null-terminated UCS-4)
// All returned pointers are internal — do NOT free, copy before next API call

typedef struct _HangulKeyboard HangulKeyboard;
typedef struct _HangulCombination HangulCombination;
typedef struct _HangulBuffer HangulBuffer;
typedef struct _HangulInputContext HangulInputContext;
typedef struct _Hanja Hanja;
typedef struct _HanjaList HanjaList;
typedef struct _HanjaTable HanjaTable;
```

---

## Input Context API (Core)

### Lifecycle

```c
HangulInputContext* hangul_ic_new(const char* keyboard);
// Create context with keyboard layout ID (e.g., "2", "3f", "ro")
// Returns NULL on failure

void hangul_ic_delete(HangulInputContext* hic);
// Free context. Does NOT produce commit string — call flush() first
// to preserve pending composition.
```

### Key Processing

```c
bool hangul_ic_process(HangulInputContext* hic, int ascii);
// Feed an ASCII key to the composition engine.
//
// IMPORTANT: Clears preedit_string and commit_string at entry.
// Read them immediately after this call.
//
// Returns:
//   true  — key was consumed by Hangul engine (it's a jamo key)
//   false — key was NOT consumed (caller must forward to application)
//
// When returning true:
//   get_preedit_string() → current composition (may be updated)
//   get_commit_string()  → finalized syllable(s) (may be empty)
//
// When returning false:
//   preedit and commit strings are empty (cleared at entry)
//   The composition buffer is NOT modified
//   Caller is responsible for handling the key
//
// Special case: if the key maps to a non-jamo character in the
// keyboard table (e.g., punctuation in some modes), the current
// composition is committed AND the non-jamo character is appended
// to commit_string, and returns true.

bool hangul_ic_backspace(HangulInputContext* hic);
// Undo the last jamo addition.
//
// Returns:
//   true  — backspace was consumed (jamo removed from composition)
//   false — composition was already empty (caller should handle backspace)
//
// Uses a 12-entry stack for multi-step undo:
//   한 → 하 → ㅎ → empty
//   (each backspace pops one jamo from the stack)
```

### String Retrieval

```c
const ucschar* hangul_ic_get_preedit_string(HangulInputContext* hic);
// Get current composition display text (in-progress syllable).
// Returns internal pointer — valid until next process/flush/reset call.
// Returns empty string (not NULL) when no composition active.

const ucschar* hangul_ic_get_commit_string(HangulInputContext* hic);
// Get committed text from the last process() call.
// Returns internal pointer — valid until next process/flush/reset call.
// Returns empty string (not NULL) when nothing was committed.

const ucschar* hangul_ic_flush(HangulInputContext* hic);
// Commit whatever is in the composition buffer and clear it.
// Returns the committed text (internal pointer).
// Returns empty string if buffer was already empty.
//
// USE THIS when:
//   - User presses a non-Hangul key (arrow, Ctrl+C, Enter)
//   - Focus changes
//   - Switching input modes (Korean → English)
//   - Before hangul_ic_delete() if you want to preserve pending text
```

### State Management

```c
void hangul_ic_reset(HangulInputContext* hic);
// Clear all buffers WITHOUT producing output.
// Unlike flush(), the pending composition is DISCARDED.

bool hangul_ic_is_empty(HangulInputContext* hic);
// true when choseong == 0 && jungseong == 0 && jongseong == 0

bool hangul_ic_has_choseong(HangulInputContext* hic);
bool hangul_ic_has_jungseong(HangulInputContext* hic);
bool hangul_ic_has_jongseong(HangulInputContext* hic);
// Query individual jamo component presence.

bool hangul_ic_is_transliteration(HangulInputContext* hic);
// true when using Romaja keyboard type
```

### Configuration

```c
void hangul_ic_select_keyboard(HangulInputContext* hic, const char* id);
// Switch keyboard layout at runtime. Layout IDs: "2", "2y", "32",
// "39", "3f", "3s", "3y", "ro", "ahn"

void hangul_ic_set_keyboard(HangulInputContext* hic, const HangulKeyboard* keyboard);
// Set keyboard by pointer (for custom keyboards)

void hangul_ic_set_output_mode(HangulInputContext* hic, int mode);
// HANGUL_OUTPUT_SYLLABLE (default): output precomposed syllables (U+AC00-D7A3)
// HANGUL_OUTPUT_JAMO: output decomposed jamo (U+1100-11FF)

bool hangul_ic_get_option(HangulInputContext* hic, int option);
void hangul_ic_set_option(HangulInputContext* hic, int option, bool value);
// Options:
//   HANGUL_IC_OPTION_AUTO_REORDER (0)           — default: false
//     Allow out-of-order jamo input (vowel before consonant)
//   HANGUL_IC_OPTION_COMBI_ON_DOUBLE_STROKE (1) — default: false
//     ㄱ+ㄱ=ㄲ double consonant via repeated keystroke
//   HANGUL_IC_OPTION_NON_CHOSEONG_COMBI (2)     — default: true
//     Allow choseong combinations that produce jongseong
```

### Callbacks

```c
typedef void (*HangulOnTranslate)(HangulInputContext*, int ascii, ucschar* ch, void* data);
typedef bool (*HangulOnTransition)(HangulInputContext*, ucschar ch, const ucschar* str, void* data);

void hangul_ic_connect_callback(HangulInputContext* hic, const char* event,
                                void* callback, void* user_data);
// Events:
//   "translate"  — pre-processing callback, can remap key-to-jamo mapping
//   "transition" — state transition callback, return false to flush
```

---

## Keyboard API

```c
unsigned int          hangul_keyboard_list_get_count(void);
const char*           hangul_keyboard_list_get_keyboard_id(unsigned index_);
const char*           hangul_keyboard_list_get_keyboard_name(unsigned index_);
const HangulKeyboard* hangul_keyboard_list_get_keyboard(const char* id);
// Enumerate and look up built-in keyboards.

HangulKeyboard* hangul_keyboard_new(void);
HangulKeyboard* hangul_keyboard_new_from_file(const char* path);
void            hangul_keyboard_delete(HangulKeyboard* keyboard);
void            hangul_keyboard_set_type(HangulKeyboard* keyboard, int type);
// Custom keyboard creation. File-based loading requires ENABLE_EXTERNAL_KEYBOARDS.

const char* hangul_keyboard_list_register_keyboard(HangulKeyboard* keyboard);
HangulKeyboard* hangul_keyboard_list_unregister_keyboard(const char* id);
// Register/unregister custom keyboards in global list.
```

### Keyboard Types

```c
#define HANGUL_KEYBOARD_TYPE_JAMO      0  // 2-set (두벌식)
#define HANGUL_KEYBOARD_TYPE_JASO      1  // 3-set (세벌식)
#define HANGUL_KEYBOARD_TYPE_ROMAJA    2  // Latin transliteration
#define HANGUL_KEYBOARD_TYPE_JAMO_YET  3  // 2-set + historical jamo
#define HANGUL_KEYBOARD_TYPE_JASO_YET  4  // 3-set + historical jamo
```

### Built-in Keyboard Layouts (9)

| ID | Name | Type | Description |
|----|------|------|-------------|
| `"2"` | 두벌식 (Dubeolsik) | JAMO | Standard 2-set. Most common in Korea. Consonants left, vowels right. |
| `"2y"` | 두벌식 옛글 | JAMO_YET | 2-set with historical/archaic jamo |
| `"32"` | 세벌식 두벌 자판 | JASO | 3-set mapped to 2-set key positions |
| `"39"` | 세벌식 390 | JASO | 3-set with numeric entry via right hand + Shift |
| `"3f"` | 세벌식 최종 (Final) | JASO | 3-set "final" standard layout |
| `"3s"` | 세벌식 순아래 (Noshift) | JASO | 3-set without requiring Shift |
| `"3y"` | 세벌식 옛글 | JASO_YET | 3-set with historical jamo |
| `"ro"` | 로마자 (Romaja) | ROMAJA | Latin-to-Hangul transliteration |
| `"ahn"` | 안마태 (Ahnmatae) | JASO | Alternative ergonomic 3-set |

---

## Character Classification API

```c
bool hangul_is_choseong(ucschar c);               // U+1100-115F, U+A960-A97C
bool hangul_is_jungseong(ucschar c);              // U+1160-11A7, U+D7B0-D7C6
bool hangul_is_jongseong(ucschar c);              // U+11A8-11FF, U+D7CB-D7FB
bool hangul_is_choseong_conjoinable(ucschar c);   // U+1100-1112 (19 modern)
bool hangul_is_jungseong_conjoinable(ucschar c);  // U+1161-1175 (21 modern)
bool hangul_is_jongseong_conjoinable(ucschar c);  // U+11A8-11C2 (27 modern + filler)
bool hangul_is_syllable(ucschar c);               // U+AC00-D7A3 (precomposed)
bool hangul_is_jamo(ucschar c);                   // any jamo character
bool hangul_is_cjamo(ucschar c);                  // U+3131-318E (compatibility jamo)
```

## Jamo Conversion API

```c
ucschar hangul_jamo_to_cjamo(ucschar ch);
// Convert Hangul Jamo (U+1100-11FF) to Compatibility Jamo (U+3131-318E)

ucschar hangul_jamo_to_syllable(ucschar choseong, ucschar jungseong, ucschar jongseong);
// Compose three jamo into a precomposed syllable (U+AC00-D7A3)
// Pass 0 for jongseong if no final consonant

void hangul_syllable_to_jamo(ucschar syllable, ucschar* choseong, ucschar* jungseong, ucschar* jongseong);
// Decompose a precomposed syllable into three jamo

int hangul_jamos_to_syllables(ucschar* dest, int destlen, const ucschar* src, int srclen);
// Convert a jamo string to syllable string
```

## Syllable Iteration API

```c
int hangul_syllable_len(const ucschar* str, int max_len);
// Length of the first syllable in a jamo string

const ucschar* hangul_syllable_iterator_prev(const ucschar* str, const ucschar* begin);
const ucschar* hangul_syllable_iterator_next(const ucschar* str, const ucschar* end);
// Iterate over syllable boundaries in a jamo string
```

---

## Hanja API (Future Use)

```c
HanjaTable* hanja_table_load(const char* filename);
void        hanja_table_delete(HanjaTable* table);

HanjaList*  hanja_table_match_exact(const HanjaTable* table, const char* key);
HanjaList*  hanja_table_match_prefix(const HanjaTable* table, const char* key);
HanjaList*  hanja_table_match_suffix(const HanjaTable* table, const char* key);

int          hanja_list_get_size(const HanjaList* list);
const Hanja* hanja_list_get_nth(const HanjaList* list, unsigned int n);
const char*  hanja_list_get_nth_key(const HanjaList* list, unsigned int n);
const char*  hanja_list_get_nth_value(const HanjaList* list, unsigned int n);
const char*  hanja_list_get_nth_comment(const HanjaList* list, unsigned int n);
void         hanja_list_delete(HanjaList* list);
```

Not needed for Korean Hangul composition (v1). Will be useful when adding Hanja conversion support.

---

## Internal Data Structures (For Understanding)

### HangulBuffer

```c
struct _HangulBuffer {
    ucschar choseong;     // Current initial consonant (0 if none)
    ucschar jungseong;    // Current vowel (0 if none)
    ucschar jongseong;    // Current final consonant (0 if none)
    ucschar stack[12];    // History stack for backspace undo
    int     index;        // Stack pointer (-1 = empty)
};
```

### HangulInputContext

```c
struct _HangulInputContext {
    int type;
    const HangulKeyboard* keyboard;
    int tableid;
    HangulBuffer buffer;
    int output_mode;                          // SYLLABLE or JAMO
    ucschar preedit_string[64];               // Current composition display
    ucschar commit_string[64];                // Completed text for app
    ucschar flushed_string[64];               // Text from flush()
    HangulOnTranslate  on_translate;
    void*              on_translate_data;
    HangulOnTransition on_transition;
    void*              on_transition_data;
    unsigned int use_jamo_mode_only        : 1;
    unsigned int option_auto_reorder       : 1; // Default: false
    unsigned int option_combi_on_double_stroke : 1; // Default: false
    unsigned int option_non_choseong_combi : 1; // Default: true
};
```

Key observations:
- Fixed-size buffers (64 ucschar = 256 bytes each) — no heap allocation per operation
- 12-entry stack enables multi-step backspace undo
- Options are bitfield flags for memory efficiency
