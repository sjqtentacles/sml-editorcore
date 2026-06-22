# sml-unicode

Pure Standard ML Unicode utilities: UTF-8 / UTF-16 codecs, canonical
normalization (NFC / NFD), simple case folding, extended grapheme-cluster
segmentation (UAX #29), and East-Asian display width. No FFI, no threads, no
clock — every function is a deterministic transform of its input and a
*curated subset* of the Unicode Character Database vendored as plain SML
tables. Builds with both **MLton** and **Poly/ML**.

Codepoints are plain `int`s (Unicode scalar values); byte strings are ordinary
SML `string`s. The codecs map between the two.

## API

The public API (`signature UNICODE`):

```sml
exception Malformed of string

(* codecs *)
val decodeUtf8  : string -> int list
val encodeUtf8  : int list -> string
datatype endian = BE | LE
val decodeUtf16 : endian -> string -> int list
val encodeUtf16 : endian -> int list -> string

(* normalization *)
datatype form = NFC | NFD
val normalize   : form -> int list -> int list

(* case folding (simple, common-case) *)
val caseFold    : int list -> int list

(* segmentation: extended grapheme clusters as UTF-8 substrings *)
val graphemes   : string -> string list

(* monospace display width: 0 combining/zero-width, 2 wide/fullwidth, else 1 *)
val width       : int -> int
```

## Usage

```sml
(* UTF-8 round-trips through codepoint lists. *)
val cps = Unicode.decodeUtf8 "Caf\195\169"      (* => [0x43,0x61,0x66,0xE9] *)
val s   = Unicode.encodeUtf8 cps                (* => "Caf\195\169"          *)

(* UTF-16 with explicit byte order; supplementary planes use surrogate pairs. *)
val u16 = Unicode.encodeUtf16 Unicode.BE [0x1F600]   (* "\216\061\222\000" *)

(* NFC collapses base + combining mark into a precomposed codepoint. *)
val nfc = Unicode.normalize Unicode.NFC [0x0065, 0x0301]   (* => [0x00E9]   *)
val nfd = Unicode.normalize Unicode.NFD [0x00E9]           (* => [0x0065,0x0301] *)

(* Simple case folding for case-insensitive comparison. *)
val folded = Unicode.caseFold (Unicode.decodeUtf8 "STRASSE")  (* "strasse" *)

(* Extended grapheme clusters keep combining marks, flags, and ZWJ emoji
   sequences together. *)
val gs = Unicode.graphemes "a\204\129bc"   (* => ["a\204\129", "b", "c"]    *)

(* Display width. *)
val w  = Unicode.width 0x4E2D              (* CJK ideograph => 2            *)
```

Run [`examples/demo.sml`](examples/demo.sml) with `make example` for a full
tour (codepoints, an NFC/NFD example, and per-cluster width info).

## Behaviour notes

- **UTF-8 decoding** rejects lone continuation bytes, truncated multi-byte
  sequences, overlong encodings, and surrogate-range codepoints by raising
  `Malformed`. Encoding rejects non-scalar values (out of range or surrogate).
- **UTF-16** combines surrogate pairs on decode and emits them on encode;
  odd-length input and unpaired surrogates raise `Malformed`.
- **Normalization** does canonical decomposition with canonical ordering
  (NFD) and canonical composition (NFC). Compatibility forms (NFKC / NFKD) are
  out of scope.
- **caseFold** is *simple* (1:1) common-case folding; full folds that change
  length (e.g. `ß` → `ss`) are not performed.
- **graphemes** implements the common UAX #29 rules: CR×LF, control breaks,
  Hangul L/V/T sequences, Extend/ZWJ (GB9), emoji ZWJ sequences (GB11), and
  regional-indicator pairs (GB12/13). SpacingMark and Prepend classes are
  treated as `Other`.
- Codepoints outside the shipped data degrade gracefully: `normalize` and
  `caseFold` act as the identity, and `width` returns 1.

## Scope of Unicode data shipped

This library intentionally vendors a **curated subset** of the UCD rather than
the full database (which would be a multi-megabyte generated table). The
tables live in [`lib/.../sml-unicode/data.sml`](lib/github.com/sjqtentacles/sml-unicode/data.sml)
as small, auditable association lists, derived where possible (the NFC
composition table is computed at load time as the inverse of the canonical
decompositions, so the two cannot drift).

| Concern                     | Coverage shipped |
| --------------------------- | ---------------- |
| Canonical decomposition     | Latin-1 Supplement precomposed letters (U+00C0–U+00FF) + a sampling of Latin Extended-A (macron/tilde forms). |
| Canonical combining class   | Combining Diacritical Marks used above/below/attached (subset of U+0300–U+0345). |
| NFC composition             | Derived from the canonical decompositions above (none are composition-exclusions). |
| Simple case fold            | ASCII A–Z, Latin-1 (U+00C0–U+00DE), Greek (U+0391–U+03AB + final sigma), Cyrillic (U+0400–U+042F). |
| East-Asian / display width  | Range-based: combining & zero-width → 0; Hangul, Kana, CJK ideographs (incl. Ext A/B), fullwidth forms, and emoji/pictographs → 2; everything else → 1. |
| Grapheme break property     | Range-based classification covering CR/LF/Control, Extend (combining marks, ZWNJ, variation selectors, emoji modifiers, tags), ZWJ, Regional Indicators, Hangul L/V/T/LV/LVT, and Extended_Pictographic. |

The shipped data covers at least the BMP common ranges plus every codepoint
exercised by the test suite (`test/test.sml`). If your application needs a
wider range (e.g. full Latin Extended decomposition, Hebrew/Arabic combining
classes, or NFKC), extend `data.sml` — the algorithms are table-driven and
need no other changes.

## Installation

```
smlpkg add github.com/sjqtentacles/sml-unicode
smlpkg sync
```

The library is dependency-free and builds standalone.

## Testing

```
make test       # MLton
make test-poly  # Poly/ML
make all-tests  # both
```

Both compilers run the same strict-TDD suite (`test/test.sml`): UTF-8 round
trips for ASCII / 2- / 3- / 4-byte sequences and rejection of malformed input,
UTF-16 BE/LE round trips including a surrogate pair, canonical NFC/NFD cases
with combining-mark reordering and idempotence, simple case folding, grapheme
segmentation (combining marks, CRLF, regional-indicator flags, ZWJ emoji), and
display width.

## License

MIT
