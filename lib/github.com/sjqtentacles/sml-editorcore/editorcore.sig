(* editorcore.sig

   Piece-table text buffer with undo/redo history, a Unicode-aware cursor
   model, and stable named marks.

   Buffer
   ------
   The buffer is a *piece table*: an append-only `original` string, an
   append-only `add` string (a rope-like growth buffer), and a list of
   *pieces* referencing a substring of either buffer. Editing never mutates
   existing storage -- inserts and deletes only splice the piece list, and
   newly-typed text is appended to `add`. This makes undo/redo cheap (the
   history is a list of piece-list edits) and keeps the original text
   available for diffing.

   Positions are character offsets into the *logical* text (0..length).
   They are byte offsets into the UTF-8 encoding of the buffer: because the
   cursor module does grapheme segmentation via `sml-unicode`, callers that
   move by grapheme always land on a valid character boundary, but raw
   integer positions are bytes.

   History
   -------
   An inline list zipper: `past` is reverse-chronological (most-recent
   first), `future` holds redone edits. `push` clears `future` (a new edit
   after an undo discards the redo branch), exactly as a conventional
   editor does. `undo` pops `past` into `future`; `redo` pops `future`
   back into `past`.

   Cursor
   ------
   A cursor is `{pos}` -- a byte offset. Movement is *grapheme-aware*: it
   consults `Unicode.graphemes` to step by user-perceived characters, so a
   multi-byte or combining-mark sequence moves as one unit. `moveUp`/
   `moveDown` track visual lines (delimited by `\n`); when the target line
   is shorter than the cursor's column, the cursor clamps to the line end.

   Mark
   ----
   A mark is a named byte offset that *adjusts* on edit: inserting text
   before a mark pushes it right by the inserted length; deleting a range
   that starts before a mark pulls it left (or pins it at the deletion
   start if the mark falls inside the deleted range). This is the standard
   "sticky" anchor semantics used by editors for selections, fold ranges,
   and diagnostics.

   EditorState
   -----------
   A composite of `{buf, history, cursor, marks}`. The combined
   `insert`/`delete` operations apply the edit to the buffer, record it in
   the history, adjust every mark, and move the cursor -- so a caller can
   drive a whole editing session through `EditorState` without touching the
   sub-modules directly. *)

signature EDITORCORE =
sig
  (* ---- Buffer (piece table) ---- *)

  type buf

  exception Buffer of string

  val empty    : buf
  val fromString : string -> buf
  val insert   : buf * int * string -> buf      (* insert s at pos *)
  val delete   : buf * int * int -> buf          (* delete len chars at pos *)
  val slice    : buf * int * int -> string       (* substring [pos, pos+len) *)
  val length   : buf -> int                      (* logical character count *)
  val toString : buf -> string

  (* ---- History (inline list zipper) ---- *)

  datatype edit =
       InsertEdit of {pos : int, text : string}
     | DeleteEdit of {pos : int, len : int, text : string}  (* text = removed bytes *)

  type history
  val emptyHistory : history
  val push : history * edit -> history
  val undo  : history -> (edit * history) option
  val redo  : history -> (edit * history) option

  (* ---- Cursor ---- *)

  type cursor = {pos : int}

  exception Cursor of string

  val cursor : buf -> cursor                     (* cursor at position 0 *)
  val cursorAt : int -> cursor                   (* cursor at a byte offset *)
  val cursorPos : cursor -> int

  (* Move by one grapheme cluster. `moveLeft`/`moveRight` consult
     `Unicode.graphemes` on the current line so multi-byte and combining
     sequences step as a single unit. Clamps at 0 / buffer end. *)
  val moveLeft  : buf -> cursor -> cursor
  val moveRight : buf -> cursor -> cursor

  (* Move to the start/end of the current visual line. *)
  val moveToLineStart : buf -> cursor -> cursor
  val moveToLineEnd   : buf -> cursor -> cursor

  (* Move up/down one visual line, preserving the grapheme column. Clamps
     to the target line's end if it is shorter than the column. *)
  val moveUp   : buf -> cursor -> cursor
  val moveDown : buf -> cursor -> cursor

  (* ---- Mark ---- *)

  type marks

  val emptyMarks : marks
  val setMark   : marks * string * int -> marks    (* name -> byte offset *)
  val getMark   : marks * string -> int option
  val removeMark: marks * string -> marks

  (* Adjust marks for an insertion at `pos` of `len` bytes: marks at or
     after `pos` shift right by `len`. *)
  val adjustForInsert : marks * int * int -> marks
  (* Adjust marks for a deletion of `len` bytes at `pos`: marks before
     `pos` stay; marks inside `[pos, pos+len)` pin to `pos`; marks after
     shift left by `len`. *)
  val adjustForDelete : marks * int * int -> marks

  (* ---- EditorState ---- *)

  type state = {buf : buf, history : history, cursor : cursor, marks : marks}

  val newState : string -> state
  val stateInsert : state * int * string -> state
  val stateDelete : state * int * int -> state
  val stateUndo : state -> state
  val stateRedo : state -> state
  val stateBuffer : state -> buf
  val stateCursor : state -> cursor
  val stateText : state -> string
end
