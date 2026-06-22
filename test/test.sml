(* Tests for sml-editorcore.

   Exercises the piece-table buffer (insert in the middle, delete spanning
   a piece boundary, slice across pieces), the history zipper (undo,
   redo, and branching after undo), the Unicode-aware cursor (multi-byte
   UTF-8, up/down across lines of differing length), mark stability
   under insert/delete, and a 20-edit round-trip. *)

structure EditorCoreTests =
struct
  open Harness
  open EditorCore

  (* Build a UTF-8 byte string from a list of code points, to avoid MLton's
     "extended text constants" restriction on byte escapes > 127 in source. *)
  fun utf8 cps =
      String.implode (List.map Char.chr cps)

  (* ---- Buffer (piece table) ---- *)
  fun runBufferTests () =
    let
      val () = section "piece table"

      val () = checkString "empty toString" ("", toString empty)
      val () = checkInt "empty length" (0, length empty)

      val b0 = fromString "Hello, World!"
      val () = checkString "fromString round-trips"
                   ("Hello, World!", toString b0)
      val () = checkInt "fromString length" (13, length b0)

      (* insert in the middle *)
      val b1 = insert (b0, 7, "beautiful ")
      val () = checkString "insert in middle"
                   ("Hello, beautiful World!", toString b1)

      (* insert at start *)
      val b2 = insert (b0, 0, ">> ")
      val () = checkString "insert at start"
                   (">> Hello, World!", toString b2)

      (* insert at end *)
      val b3 = insert (b0, 13, "!!")
      val () = checkString "insert at end"
                   ("Hello, World!!!", toString b3)

      (* delete spanning a piece boundary: b1 has pieces because we
         inserted in the middle; deleting across that seam exercises
         the multi-piece delete. b1 = "Hello, beautiful World!"
         (23 chars). delete 15 chars at pos 5 removes ", beautiful Wor"
         leaving "Hello" + "ld!" = "Hellold!". *)
      val b4 = delete (b1, 5, 15)
      val () = checkString "delete spanning piece boundary"
                   ("Hellold!", toString b4)

      (* slice across pieces: b1 = "Hello, beautiful World!", slice 14
         chars starting at pos 5 = ", beautiful Wo". *)
      val () = checkString "slice across pieces"
                   (", beautiful Wo", slice (b1, 5, 14))
      val () = checkString "slice at start"
                   ("Hello", slice (b1, 0, 5))
      val () = checkString "slice empty range"
                   ("", slice (b1, 5, 0))

      (* out-of-range insert raises *)
      val () = checkRaises "insert out of range" (fn () => insert (b0, 100, "x"))
      val () = checkRaises "delete out of range" (fn () => delete (b0, 100, 1))
    in
      ()
    end

  (* ---- History (inline list zipper) ---- *)
  fun runHistoryTests () =
    let
      val () = section "history"

      val e1 = InsertEdit {pos = 3, text = "def"}
      val e2 = InsertEdit {pos = 0, text = "xyz"}
      val h0 = push (push (emptyHistory, e1), e2)

      (* undo reverses the last insert *)
      val (u1, h1) = valOf (undo h0)
      val () = checkString "undo returns last edit text"
                   ("xyz", case u1 of InsertEdit {text, ...} => text
                                   | _ => "<wrong>")
      (* redo reapplies *)
      val (_, h2) = valOf (redo h1)
      (* undo again to get back to state after e1 only *)
      val (u2, _) = valOf (undo h2)
      val () = checkString "undo after redo returns same edit"
                   ("xyz", case u2 of InsertEdit {text, ...} => text
                                   | _ => "<wrong>")

      (* branch: new edit after undo clears the redo stack *)
      val (_, h4) = valOf (undo h0)    (* undo e2, future = [e2] *)
      val e3 = InsertEdit {pos = 6, text = "GHI"}
      val h5 = push (h4, e3)             (* should clear future *)
      val () = checkBool "redo after branch is NONE"
                   (true, not (Option.isSome (redo h5)))

      (* undo on empty history *)
      val () = checkBool "undo empty history is NONE"
                   (true, not (Option.isSome (undo emptyHistory)))
      val () = checkBool "redo empty history is NONE"
                   (true, not (Option.isSome (redo emptyHistory)))
    in
      ()
    end

  (* ---- Cursor ---- *)
  fun runCursorTests () =
    let
      val () = section "cursor (grapheme-aware)"

      val b = fromString "abc"
      val c0 = cursor b
      val () = checkInt "cursor starts at 0" (0, cursorPos c0)

      val c1 = moveRight b c0
      val () = checkInt "moveRight by one grapheme" (1, cursorPos c1)
      val c2 = moveRight b c1
      val () = checkInt "moveRight again" (2, cursorPos c2)
      val c3 = moveRight b c2
      val () = checkInt "moveRight to end" (3, cursorPos c3)
      val c4 = moveRight b c3
      val () = checkInt "moveRight past end clamps" (3, cursorPos c4)

      val c5 = moveLeft b c3
      val () = checkInt "moveLeft by one" (2, cursorPos c5)
      val c6 = moveLeft b (moveLeft b c5)
      val () = checkInt "moveLeft to 0" (0, cursorPos c6)
      val c7 = moveLeft b c6
      val () = checkInt "moveLeft at 0 clamps" (0, cursorPos c7)

      val () = section "cursor (multi-byte UTF-8)"

      (* "a<U+00E9>b" where U+00E9 = 0xC3 0xA9 (2 bytes in UTF-8) *)
      val bmb = fromString (utf8 [97, 195, 169, 98])  (* a, 0xC3, 0xA9, b *)
      val cm0 = cursor bmb
      val cm1 = moveRight bmb cm0       (* past 'a' -> 1 *)
      val () = checkInt "right past ASCII 'a'" (1, cursorPos cm1)
      val cm2 = moveRight bmb cm1       (* past U+00E9 -> 3 (skips 2 bytes) *)
      val () = checkInt "right past 2-byte U+00E9" (3, cursorPos cm2)
      val cm3 = moveRight bmb cm2       (* past 'b' -> 4 *)
      val () = checkInt "right past 'b' to end" (4, cursorPos cm3)
      (* move back left should reverse: 3 -> 1 -> 0 *)
      val cm4 = moveLeft bmb cm3
      val () = checkInt "left from end past 'b'" (3, cursorPos cm4)
      val cm5 = moveLeft bmb cm4
      val () = checkInt "left past 2-byte U+00E9" (1, cursorPos cm5)
      val cm6 = moveLeft bmb cm5
      val () = checkInt "left past 'a' to 0" (0, cursorPos cm6)

      val () = section "cursor (up/down across lines)"

      (* Two lines of different length:
         "12345\nabcdefg\n"  -> line 0: "12345" (len 5), line 1: "abcdefg" (len 7)
         Positions: 0..5 on line 0 (5 is the newline), 6..12 on line 1. *)
      val bm = fromString "12345\nabcdefg\n"
      val cdown0 = cursorAt 2    (* column 2 on line 0 *)
      val cdown1 = moveDown bm cdown0
      val () = checkInt "moveDown preserves column 2"
                   (8, cursorPos cdown1)  (* 6 (line1 start) + 2 = 8 *)
      (* down again -- line 2 is empty (past trailing newline) *)
      val cdown2 = moveDown bm cdown1
      val () = checkInt "moveDown to last line clamps to end"
                   (14, cursorPos cdown2)
      (* up from line 1 col 2 back to line 0 col 2 *)
      val cup0 = cursorAt 8
      val cup1 = moveUp bm cup0
      val () = checkInt "moveUp preserves column 2"
                   (2, cursorPos cup1)
      (* moveDown with column beyond target line length clamps to line end.
         From end of line 1 (col 7) up to line 0 (length 5) clamps to 5. *)
      val cline1end = cursorAt 13   (* 6 + 7 = 13, end of "abcdefg" *)
      val cup2 = moveUp bm cline1end
      val () = checkInt "moveUp clamps to shorter line end"
                   (5, cursorPos cup2)

      val () = section "cursor (line start/end)"

      val clstart = cursorAt 8   (* col 2 on line 1 *)
      val clstart0 = moveToLineStart bm clstart
      val () = checkInt "moveToLineStart" (6, cursorPos clstart0)
      val clend0 = moveToLineEnd bm clstart
      val () = checkInt "moveToLineEnd" (13, cursorPos clend0)
    in
      ()
    end

  (* ---- Mark stability ---- *)
  fun runMarkTests () =
    let
      val () = section "mark stability"

      val m0 = setMark (emptyMarks, "a", 5)
      val () = checkBool "getMark returns set position"
                   (true, getMark (m0, "a") = SOME 5)
      val () = checkBool "getMark missing returns NONE"
                   (true, getMark (m0, "z") = NONE)

      (* insert before mark shifts it right *)
      val m1 = adjustForInsert (m0, 2, 3)
      val () = checkInt "mark shifts right on insert before"
                   (8, valOf (getMark (m1, "a")))
      (* insert at the mark position shifts it right too (>= semantics) *)
      val m1b = adjustForInsert (m0, 5, 2)
      val () = checkInt "mark shifts right when insert at mark"
                   (7, valOf (getMark (m1b, "a")))
      (* insert after mark leaves it alone *)
      val m2 = adjustForInsert (m0, 7, 4)
      val () = checkInt "mark unchanged on insert after"
                   (5, valOf (getMark (m2, "a")))

      (* delete entirely before mark: shifts left *)
      val m3 = adjustForDelete (m0, 2, 3)
      val () = checkInt "mark shifts left on delete before"
                   (2, valOf (getMark (m3, "a")))
      (* delete entirely after mark: unchanged *)
      val m4 = adjustForDelete (m0, 6, 3)
      val () = checkInt "mark unchanged on delete after"
                   (5, valOf (getMark (m4, "a")))
      (* delete spanning the mark: mark pins to deletion start *)
      val m5 = adjustForDelete (m0, 3, 5)   (* covers position 5 *)
      val () = checkInt "mark pins to delete start when spanned"
                   (3, valOf (getMark (m5, "a")))

      (* removeMark *)
      val m6 = removeMark (m0, "a")
      val () = checkBool "removeMark clears the mark"
                   (true, getMark (m6, "a") = NONE)
    in
      ()
    end

  (* ---- EditorState round-trip ---- *)
  fun runStateTests () =
    let
      val () = section "editor state round-trip"

      val s0 = newState "Hello"
      val () = checkString "newState text" ("Hello", stateText s0)

      (* Apply a sequence of 20 mixed edits, then fully undo and check the
         buffer equals the original. *)
      fun applyN (s, 0) = s
        | applyN (s, n) =
            let
              val s =
                  if n mod 2 = 0
                  then stateInsert (s, n mod (length (stateBuffer s) + 1),
                                    Int.toString n)
                  else
                    let val bl = length (stateBuffer s)
                        val pos = n mod (bl + 1)
                        val delLen = Int.min (1, bl - pos)
                    in
                      if delLen > 0
                      then stateDelete (s, pos, delLen)
                      else stateInsert (s, pos, "X")
                    end
            in
              applyN (s, n - 1)
            end

      val s20 = applyN (s0, 20)
      (* fully undo all 20 edits. Track whether state changed by comparing
         buffer text (the state type is opaque so we can't use =). *)
      fun undoAll s =
          let
            val prevText = stateText s
            val s' = stateUndo s
          in
            if stateText s' = prevText then s
            else undoAll s'
          end
      val sBack = undoAll s20
      val () = checkString "20-edit round-trip restores original"
                   ("Hello", stateText sBack)

      val () = section "editor state undo/redo with marks"

      val sm0 = newState "abcdef"
      val sm1 = {buf = #buf sm0, history = #history sm0,
                 cursor = #cursor sm0,
                 marks = setMark (emptyMarks, "m", 3)} : state
      val sm2 = stateInsert (sm1, 1, "XY")
      (* mark should have shifted from 3 to 5 *)
      val () = checkInt "mark shifts under stateInsert"
                   (5, valOf (getMark (#marks sm2, "m")))
      val () = checkString "stateInsert text"
                   ("aXYbcdef", stateText sm2)
      (* undo should restore mark to 3 and text to "abcdef" *)
      val sm3 = stateUndo sm2
      val () = checkString "stateUndo restores text"
                   ("abcdef", stateText sm3)
      val () = checkInt "stateUndo restores mark"
                   (3, valOf (getMark (#marks sm3, "m")))
      (* redo re-applies *)
      val sm4 = stateRedo sm3
      val () = checkString "stateRedo re-applies edit"
                   ("aXYbcdef", stateText sm4)
      val () = checkInt "stateRedo re-shifts mark"
                   (5, valOf (getMark (#marks sm4, "m")))
    in
      ()
    end

  fun run () =
    ( runBufferTests ()
    ; runHistoryTests ()
    ; runCursorTests ()
    ; runMarkTests ()
    ; runStateTests () )
end
