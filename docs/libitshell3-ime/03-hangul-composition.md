# Korean Hangul Composition Rules

## Unicode Hangul Structure

Korean Hangul syllables are composed of up to three jamo (자모) components:

```
Syllable = Choseong (초성, initial consonant)
         + Jungseong (중성, medial vowel)
         + [Jongseong (종성, final consonant)]  ← optional
```

### Unicode Ranges

| Component | Standard Range | Count (Modern) | Description |
|-----------|---------------|----------------|-------------|
| Choseong | U+1100 – U+1112 | 19 | Initial consonants |
| Jungseong | U+1161 – U+1175 | 21 | Medial vowels |
| Jongseong | U+11A8 – U+11C2 | 27 | Final consonants |
| Syllable | U+AC00 – U+D7A3 | 11,172 | Precomposed syllables |

### Syllable Composition Formula

```
Syllable = SBase + (L × VCount + V) × TCount + T

Where:
  SBase  = 0xAC00  (first syllable: 가)
  LBase  = 0x1100  (first choseong: ㄱ)
  VBase  = 0x1161  (first jungseong: ㅏ)
  TBase  = 0x11A7  (jongseong base, one before first: 0x11A8 = ㄱ)
  LCount = 19      (number of modern choseong)
  VCount = 21      (number of modern jungseong)
  TCount = 28      (27 jongseong + 1 for "no jongseong")

  L = choseong  - LBase   (0–18)
  V = jungseong - VBase   (0–20)
  T = jongseong - TBase   (0–27, where 0 = no final consonant)
```

Example: 한 = 0xAC00 + (11×21 + 0)×28 + 4 = 0xD55C

---

## The 19 Modern Choseong (Initial Consonants)

| Index | Codepoint | Jamo | Name | 2-set Key |
|-------|-----------|------|------|-----------|
| 0 | U+1100 | ㄱ | Giyeok | r |
| 1 | U+1101 | ㄲ | Ssang-Giyeok | R (Shift+r) |
| 2 | U+1102 | ㄴ | Nieun | s |
| 3 | U+1103 | ㄷ | Digeut | e |
| 4 | U+1104 | ㄸ | Ssang-Digeut | E (Shift+e) |
| 5 | U+1105 | ㄹ | Rieul | f |
| 6 | U+1106 | ㅁ | Mieum | a |
| 7 | U+1107 | ㅂ | Bieup | q |
| 8 | U+1108 | ㅃ | Ssang-Bieup | Q (Shift+q) |
| 9 | U+1109 | ㅅ | Siot | t |
| 10 | U+110A | ㅆ | Ssang-Siot | T (Shift+t) |
| 11 | U+110B | ㅇ | Ieung | d |
| 12 | U+110C | ㅈ | Jieut | w |
| 13 | U+110D | ㅉ | Ssang-Jieut | W (Shift+w) |
| 14 | U+110E | ㅊ | Chieut | c |
| 15 | U+110F | ㅋ | Kieuk | z |
| 16 | U+1110 | ㅌ | Tieut | x |
| 17 | U+1111 | ㅍ | Pieup | v |
| 18 | U+1112 | ㅎ | Hieut | g |

## The 21 Modern Jungseong (Medial Vowels)

| Index | Codepoint | Jamo | Name | 2-set Key |
|-------|-----------|------|------|-----------|
| 0 | U+1161 | ㅏ | A | k |
| 1 | U+1162 | ㅐ | Ae | o |
| 2 | U+1163 | ㅑ | Ya | i |
| 3 | U+1164 | ㅒ | Yae | O (Shift+o) |
| 4 | U+1165 | ㅓ | Eo | j |
| 5 | U+1166 | ㅔ | E | p |
| 6 | U+1167 | ㅕ | Yeo | u |
| 7 | U+1168 | ㅖ | Ye | P (Shift+p) |
| 8 | U+1169 | ㅗ | O | h |
| 9 | U+116A | ㅘ | Wa | h + k |
| 10 | U+116B | ㅙ | Wae | h + o |
| 11 | U+116C | ㅚ | Oe | h + l |
| 12 | U+116D | ㅛ | Yo | y |
| 13 | U+116E | ㅜ | U | n |
| 14 | U+116F | ㅝ | Weo | n + j |
| 15 | U+1170 | ㅞ | We | n + p |
| 16 | U+1171 | ㅟ | Wi | n + l |
| 17 | U+1172 | ㅠ | Yu | b |
| 18 | U+1173 | ㅡ | Eu | m |
| 19 | U+1174 | ㅢ | Yi | m + l |
| 20 | U+1175 | ㅣ | I | l |

## The 27 Modern Jongseong (Final Consonants)

| Index | Codepoint | Jamo | Name | Compound? |
|-------|-----------|------|------|-----------|
| 1 | U+11A8 | ㄱ | Giyeok | No |
| 2 | U+11A9 | ㄲ | Ssang-Giyeok | ㄱ+ㄱ |
| 3 | U+11AA | ㄳ | Giyeok-Siot | ㄱ+ㅅ |
| 4 | U+11AB | ㄴ | Nieun | No |
| 5 | U+11AC | ㄵ | Nieun-Jieut | ㄴ+ㅈ |
| 6 | U+11AD | ㄶ | Nieun-Hieut | ㄴ+ㅎ |
| 7 | U+11AE | ㄷ | Digeut | No |
| 8 | U+11AF | ㄹ | Rieul | No |
| 9 | U+11B0 | ㄺ | Rieul-Giyeok | ㄹ+ㄱ |
| 10 | U+11B1 | ㄻ | Rieul-Mieum | ㄹ+ㅁ |
| 11 | U+11B2 | ㄼ | Rieul-Bieup | ㄹ+ㅂ |
| 12 | U+11B3 | ㄽ | Rieul-Siot | ㄹ+ㅅ |
| 13 | U+11B4 | ㄾ | Rieul-Tieut | ㄹ+ㅌ |
| 14 | U+11B5 | ㄿ | Rieul-Pieup | ㄹ+ㅍ |
| 15 | U+11B6 | ㅀ | Rieul-Hieut | ㄹ+ㅎ |
| 16 | U+11B7 | ㅁ | Mieum | No |
| 17 | U+11B8 | ㅂ | Bieup | No |
| 18 | U+11B9 | ㅄ | Bieup-Siot | ㅂ+ㅅ |
| 19 | U+11BA | ㅅ | Siot | No |
| 20 | U+11BB | ㅆ | Ssang-Siot | ㅅ+ㅅ |
| 21 | U+11BC | ㅇ | Ieung | No |
| 22 | U+11BD | ㅈ | Jieut | No |
| 23 | U+11BE | ㅊ | Chieut | No |
| 24 | U+11BF | ㅋ | Kieuk | No |
| 25 | U+11C0 | ㅌ | Tieut | No |
| 26 | U+11C1 | ㅍ | Pieup | No |
| 27 | U+11C2 | ㅎ | Hieut | No |

Note: Index 0 (U+11A7) is the "no jongseong" filler, never output.

---

## Composition State Machine (2-set / Dubeolsik)

The 2-set automata has 4 states based on buffer contents:

```
         consonant
  ┌──────────────────┐
  │                  │
  ▼    vowel         │    consonant        vowel
┌─────┐──────►┌──────┴──┐──────────►┌──────────────┐
│Empty│       │Cho+Jung │           │Cho+Jung+Jong │
│     │◄──────│ (가)    │◄──────────│ (간)         │
└──┬──┘  bs   └────┬────┘    bs     └──────┬───────┘
   │               │                       │
   │  consonant    │  vowel combo          │  vowel (jamo reassignment)
   ▼               ▼                       ▼
┌──────┐      combine if possible     commit(가) + new(나)
│Cho   │      (ㅗ+ㅏ=ㅘ)
│ (ㄱ) │
└──────┘
```

### State 0: Empty Buffer

| Input | Action | New State |
|-------|--------|-----------|
| Consonant (choseong) | Push to buffer | Choseong only |
| Vowel (jungseong) | Push to buffer (with filler choseong) | Cho+Jung |
| Non-jamo | Append to commit, return true | Empty |
| Unmapped key (return false) | — | Empty |

### State 1: Choseong Only (e.g., ㄱ)

| Input | Action | New State |
|-------|--------|-----------|
| Same consonant | Try combine (ㄱ+ㄱ=ㄲ). If fail: commit ㄱ, new ㄱ | Choseong only |
| Different consonant | Commit current, start new | Choseong only |
| Vowel | Add as jungseong (ㄱ+ㅏ=가) | Cho+Jung |
| Backspace | Pop stack (ㄱ→empty) | Empty |

### State 2: Choseong + Jungseong (e.g., 가)

| Input | Action | New State |
|-------|--------|-----------|
| Consonant | Convert cho→jong, add as jongseong (가+ㄴ=간). If no jong form (ㅃ,ㅉ): commit 가, new ㄲ | Cho+Jung+Jong or Cho |
| Same vowel | Try combine (ㅗ+ㅏ=ㅘ). If fail: commit, restart | Cho+Jung |
| Different vowel | Try combine. If fail: commit, restart | Cho+Jung |
| Backspace | Pop stack (가→ㄱ) | Choseong only |

### State 3: Choseong + Jungseong + Jongseong (e.g., 간)

| Input | Action | New State |
|-------|--------|-----------|
| Consonant | Try combine with jong (ㄴ+ㅈ=ㄵ). If fail: commit 간, new ㄴ | Cho+Jung+Jong or Cho |
| Vowel | **Jamo reassignment**: decompose jong, commit without last jong, start new syllable with popped jong + vowel. (간+ㅏ → commit 가, preedit 나) | Cho+Jung |
| Backspace | Pop stack (간→가) | Cho+Jung |

### Jamo Reassignment (Detailed)

This is the most important transition — when a vowel arrives after a complete syllable:

```
Buffer: 간 (ㄱ + ㅏ + ㄴ)
Input: ㅏ (vowel)

Step 1: Pop jongseong ㄴ from buffer
Step 2: Convert jongseong ㄴ (U+11AB) back to choseong ㄴ (U+1102)
Step 3: Commit buffer without jongseong → 가
Step 4: Start new buffer with choseong ㄴ + jungseong ㅏ → 나

Result: commit "가", preedit "나"
```

For compound jongseong:

```
Buffer: 갈 (ㄱ + ㅏ + ㄹ) then ㄱ added → 갈ㄱ compound jong ㄺ (U+11B0)
Input: ㅏ (vowel)

Step 1: Decompose compound jongseong ㄺ → ㄹ (remaining) + ㄱ (donated)
Step 2: Keep ㄹ as jongseong → 갈
Step 3: Convert donated ㄱ jongseong (U+11A8) to choseong ㄱ (U+1100)
Step 4: Commit 갈, start new buffer ㄱ + ㅏ → 가

Result: commit "갈", preedit "가"
```

---

## Combination Tables

### Choseong Combinations (Double Consonants)

In 2-set mode with `COMBI_ON_DOUBLE_STROKE` enabled:

| First | + Second | = Result |
|-------|----------|----------|
| ㄱ (U+1100) | ㄱ (U+1100) | ㄲ (U+1101) |
| ㄷ (U+1103) | ㄷ (U+1103) | ㄸ (U+1104) |
| ㅂ (U+1107) | ㅂ (U+1107) | ㅃ (U+1108) |
| ㅅ (U+1109) | ㅅ (U+1109) | ㅆ (U+110A) |
| ㅈ (U+110C) | ㅈ (U+110C) | ㅉ (U+110D) |

### Jungseong Combinations (Compound Vowels)

| First | + Second | = Result |
|-------|----------|----------|
| ㅗ (U+1169) | ㅏ (U+1161) | ㅘ (U+116A) |
| ㅗ (U+1169) | ㅐ (U+1162) | ㅙ (U+116B) |
| ㅗ (U+1169) | ㅣ (U+1175) | ㅚ (U+116C) |
| ㅜ (U+116E) | ㅓ (U+1165) | ㅝ (U+116F) |
| ㅜ (U+116E) | ㅔ (U+1166) | ㅞ (U+1170) |
| ㅜ (U+116E) | ㅣ (U+1175) | ㅟ (U+1171) |
| ㅡ (U+1173) | ㅣ (U+1175) | ㅢ (U+1174) |

### Jongseong Combinations (Compound Final Consonants)

| First | + Second | = Result |
|-------|----------|----------|
| ㄱ (U+11A8) | ㅅ (U+11BA) | ㄳ (U+11AA) |
| ㄴ (U+11AB) | ㅈ (U+11BD) | ㄵ (U+11AC) |
| ㄴ (U+11AB) | ㅎ (U+11C2) | ㄶ (U+11AD) |
| ㄹ (U+11AF) | ㄱ (U+11A8) | ㄺ (U+11B0) |
| ㄹ (U+11AF) | ㅁ (U+11B7) | ㄻ (U+11B1) |
| ㄹ (U+11AF) | ㅂ (U+11B8) | ㄼ (U+11B2) |
| ㄹ (U+11AF) | ㅅ (U+11BA) | ㄽ (U+11B3) |
| ㄹ (U+11AF) | ㅌ (U+11C0) | ㄾ (U+11B4) |
| ㄹ (U+11AF) | ㅍ (U+11C1) | ㄿ (U+11B5) |
| ㄹ (U+11AF) | ㅎ (U+11C2) | ㅀ (U+11B6) |
| ㅂ (U+11B8) | ㅅ (U+11BA) | ㅄ (U+11B9) |
| ㅅ (U+11BA) | ㅅ (U+11BA) | ㅆ (U+11BB) |

### Compound Jongseong Decomposition Table

Used during jamo reassignment (vowel after complete syllable):

| Compound | Remaining Jong | Donated Cho |
|----------|---------------|-------------|
| ㄲ (U+11A9) | ㄱ (U+11A8) | ㄱ (U+1100) |
| ㄳ (U+11AA) | ㄱ (U+11A8) | ㅅ (U+1109) |
| ㄵ (U+11AC) | ㄴ (U+11AB) | ㅈ (U+110C) |
| ㄶ (U+11AD) | ㄴ (U+11AB) | ㅎ (U+1112) |
| ㄺ (U+11B0) | ㄹ (U+11AF) | ㄱ (U+1100) |
| ㄻ (U+11B1) | ㄹ (U+11AF) | ㅁ (U+1106) |
| ㄼ (U+11B2) | ㄹ (U+11AF) | ㅂ (U+1107) |
| ㄽ (U+11B3) | ㄹ (U+11AF) | ㅅ (U+1109) |
| ㄾ (U+11B4) | ㄹ (U+11AF) | ㅌ (U+1110) |
| ㄿ (U+11B5) | ㄹ (U+11AF) | ㅍ (U+1111) |
| ㅀ (U+11B6) | ㄹ (U+11AF) | ㅎ (U+1112) |
| ㅄ (U+11B9) | ㅂ (U+11B8) | ㅅ (U+1109) |
| ㅆ (U+11BB) | ㅅ (U+11BA) | ㅅ (U+1109) |

### Choseong ↔ Jongseong Conversion

In 2-set mode, the same physical key can produce either a choseong or jongseong depending on context:

| Choseong | Jongseong | Name |
|----------|-----------|------|
| U+1100 | U+11A8 | ㄱ |
| U+1101 | U+11A9 | ㄲ |
| U+1102 | U+11AB | ㄴ |
| U+1103 | U+11AE | ㄷ |
| U+1105 | U+11AF | ㄹ |
| U+1106 | U+11B7 | ㅁ |
| U+1107 | U+11B8 | ㅂ |
| U+1108 | — | ㅃ (no jongseong form) |
| U+1109 | U+11BA | ㅅ |
| U+110A | U+11BB | ㅆ |
| U+110B | U+11BC | ㅇ |
| U+110C | U+11BD | ㅈ |
| U+110D | — | ㅉ (no jongseong form) |
| U+110E | U+11BE | ㅊ |
| U+110F | U+11BF | ㅋ |
| U+1110 | U+11C0 | ㅌ |
| U+1111 | U+11C1 | ㅍ |
| U+1112 | U+11C2 | ㅎ |

Note: ㅃ (U+1108) and ㅉ (U+110D) have no jongseong form — they cannot appear as final consonants in modern Korean.

---

## Backspace Behavior

libhangul uses a 12-entry stack for jamo-level undo. Each keystroke pushes an entry; backspace pops one.

### Example: Typing "한글" then backspacing

```
Key   Buffer State        Preedit   Stack
r     cho=ㄱ              ㄱ        [ㄱ]
k     cho=ㄱ jung=ㅏ      가        [ㄱ, ㅏ]
s     cho=ㄱ jung=ㅏ      간        [ㄱ, ㅏ, ㄴ→jong]
      jong=ㄴ
r     (commit 간)         ㄱ        [ㄱ]              commit="간"
m     cho=ㄱ jung=ㅡ      그        [ㄱ, ㅡ]
f     cho=ㄱ jung=ㅡ      글        [ㄱ, ㅡ, ㄹ→jong]
      jong=ㄹ

BS    cho=ㄱ jung=ㅡ      그        [ㄱ, ㅡ]           (pop ㄹ)
BS    cho=ㄱ              ㄱ        [ㄱ]                (pop ㅡ)
BS    empty               (empty)   []                   (pop ㄱ)
BS    returns false — caller handles backspace
```

### Edge Case: Compound Jongseong Backspace

```
Key   Buffer State        Preedit   Stack
r     cho=ㄱ              ㄱ        [ㄱ]
k     cho=ㄱ jung=ㅏ      가        [ㄱ, ㅏ]
f     cho=ㄱ jung=ㅏ      갈        [ㄱ, ㅏ, ㄹ→jong]
      jong=ㄹ
r     cho=ㄱ jung=ㅏ      갈ㄱ→갈   [ㄱ, ㅏ, ㄹ→jong, ㄱ→jong]
      jong=ㄺ (compound)   (display: 갈 with compound jong)

BS    cho=ㄱ jung=ㅏ      갈        [ㄱ, ㅏ, ㄹ→jong]  (pop compound ㄱ)
      jong=ㄹ
BS    cho=ㄱ jung=ㅏ      가        [ㄱ, ㅏ]            (pop ㄹ)
BS    cho=ㄱ              ㄱ        [ㄱ]                 (pop ㅏ)
```

---

## 3-set (Sebeolsik) Differences

In 3-set mode, choseong, jungseong, and jongseong have **dedicated keys**:

- Left hand: jongseong (final consonants)
- Right hand (bottom): choseong (initial consonants)
- Right hand (top): jungseong (vowels)

Key differences from 2-set:
1. No choseong↔jongseong conversion needed (separate keys)
2. Stricter ordering enforcement (unless `AUTO_REORDER` enabled)
3. Consonant that can't combine simply commits and starts new
4. The `JASO` processor is simpler than `JAMO` because key identity resolves ambiguity

---

## Romaja Mode

Latin-to-Hangul transliteration:

| Latin | Hangul | Notes |
|-------|--------|-------|
| g | ㄱ | |
| n | ㄴ | |
| d | ㄷ | |
| r, l | ㄹ | |
| m | ㅁ | |
| b | ㅂ | |
| s | ㅅ | |
| x, X | ㅇ | ieung |
| j | ㅈ | |
| ch | ㅊ | |
| k | ㅋ | |
| t | ㅌ | |
| p | ㅍ | |
| h | ㅎ | |
| a | ㅏ | |
| e | ㅓ | |
| i | ㅣ | |
| o | ㅗ | |
| u | ㅜ | |

Special rules:
- Uppercase triggers buffer flush (word boundary)
- Automatic ㅡ (eu) insertion for consonant-only sequences
- More permissive vowel combinations than standard jamo mode
