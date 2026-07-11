# sml-editorcore

[![CI](https://github.com/sjqtentacles/sml-editorcore/actions/workflows/ci.yml/badge.svg)](https://github.com/sjqtentacles/sml-editorcore/actions/workflows/ci.yml)

Editor primitives for Standard ML: a piece-table text buffer with undo/redo
history, a Unicode-aware cursor model, and stable named marks. The building
blocks of a text editor without any rendering or I/O -- pure data structures
that compose into a full editing session.

Part of the `sjqtentacles` monorepo of SML libraries. It depends on
[`sml-unicode`](https://github.com/sjqtentacles/sml-unicode) (vendored) for
extended grapheme-cluster segmentation, so the cursor steps by
user-perceived characters rather than raw bytes.

## Features

- **Piece-table buffer** -- append-only original + add buffers and a list of
  pieces referencing substrings; edits never mutate existing storage, which
  keeps undo cheap and the original text available for diffing.
- **Inline-list-zipper history** -- `push`, `undo`, `redo`; a new edit after
  an undo clears the redo branch, matching conventional editor semantics.
- **Grapheme-aware cursor** -- `moveLeft`/`moveRight` step by extended
  grapheme clusters (multi-byte UTF-8 and combining marks move as one unit);
  `moveUp`/`moveDown` preserve the visual column and clamp on short lines.
- **Stable named marks** -- anchors that adjust on insert/delete: shifts on
  insert-before, pulls left on delete-before, pins to the deletion start when
  spanned by a delete. The standard "sticky anchor" semantics for selections,
  fold ranges, and diagnostics.
- **`EditorState` composite** -- `{buf, history, cursor, marks}` with
  combined `insert`/`delete`/`undo`/`redo` that apply the edit, record
  history, adjust marks, and move the cursor in one step.

## Status

Working and tested. The piece table, history zipper, cursor, marks, and
`EditorState` are all implemented and exercised by the test suite.

## Portability

Pure Standard ML using only the Basis library (plus the vendored
`sml-unicode`) -- no FFI, no threads. Verified on **MLton** and **Poly/ML**,
with identical, deterministic output across both.

## Building and testing

```sh
make test        # build + run the suite under MLton (default)
make test-poly   # run the suite under Poly/ML
make all-tests   # run under both
make clean
```

## Usage

```sml
(* Start an editing session. *)
val s = EditorCore.newState "Hello, World!"

(* Insert + delete through the composite state. *)
val s' = EditorCore.stateInsert (s, 7, "beautiful ")
(* "Hello, beautiful World!" *)

val s'' = EditorCore.stateDelete (s', 0, 7)
(* "beautiful World!" *)

(* Undo restores both the text and the cursor. *)
val s''' = EditorCore.stateUndo s''
(* "Hello, beautiful World!" *)

(* The cursor moves by grapheme, so multi-byte chars step as one unit. *)
val b = EditorCore.fromString "a\195\169b"   (* "aéb", é = 2 bytes *)
val c = EditorCore.moveRight b (EditorCore.cursor b)
(* cursorPos c = 1 (past 'a') *)
val c' = EditorCore.moveRight b c
(* cursorPos c' = 3 (past the 2-byte 'é') *)

(* Marks adjust on edit. *)
val m = EditorCore.setMark (EditorCore.emptyMarks, "sel", 5)
val m' = EditorCore.adjustForInsert (m, 2, 3)
(* getMark (m', "sel") = SOME 8 *)
```

## API summary

| Function | Description |
| --- | --- |
| `empty`, `fromString` | Construct a piece-table buffer. |
| `insert : buf * int * string -> buf` | Insert text at a byte offset. |
| `delete : buf * int * int -> buf` | Delete `len` chars at a byte offset. |
| `slice : buf * int * int -> string` | Extract `[pos, pos+len)`. |
| `length`, `toString` | Logical size / full text. |
| `emptyHistory`, `push`, `undo`, `redo` | Inline-list-zipper undo/redo. |
| `cursor`, `cursorAt`, `cursorPos` | Cursor construction/query. |
| `moveLeft`, `moveRight` | Grapheme-aware horizontal movement. |
| `moveToLineStart`, `moveToLineEnd` | Jump to line bounds. |
| `moveUp`, `moveDown` | Visual-line movement (column-preserving). |
| `emptyMarks`, `setMark`, `getMark`, `removeMark` | Named anchors. |
| `adjustForInsert`, `adjustForDelete` | Recompute marks after an edit. |
| `newState`, `stateInsert`, `stateDelete`, `stateUndo`, `stateRedo` | Composite `EditorState` operations. |

## Example

`make example` builds and runs [`examples/demo.sml`](examples/demo.sml), which
drives the piece-table buffer, cursor movement, sticky marks, and the
combined `EditorState` undo/redo through a short editing session (output is
byte-identical under MLton and Poly/ML):

```
EditorCore demo
buffer after insert   = Hello, there, world!
buffer after delete   = there, world!
slice [0,5)           = there
length                = 13
cursor pos after 2x moveRight = 2
cursor pos at line end        = 13
mark 'anchor' after inserting 5 chars before it = 8
state after insert = lineXXX one
line two
state after delete = lineXXX
line two
state after undo   = lineXXX one
line two
state after redo   = lineXXX
line two
state cursor pos   = 7
```

## Dependencies

- [`sml-unicode`](https://github.com/sjqtentacles/sml-unicode) (vendored) --
  extended grapheme-cluster segmentation for the cursor.

## Installing with smlpkg

```sh
smlpkg add github.com/sjqtentacles/sml-editorcore
smlpkg sync
```

Then reference the library basis from your own `.mlb`:

```
lib/github.com/sjqtentacles/sml-editorcore/sml-editorcore.mlb
```

For Poly/ML, `use` the sources listed in `sources.mlb` in order (the vendored
`sml-unicode` first, then `editorcore.sig` and `editorcore.sml`).

## License

MIT. See [LICENSE](LICENSE).
