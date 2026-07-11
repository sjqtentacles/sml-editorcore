(* demo.sml - piece-table buffer, grapheme-aware cursor, sticky marks, and the
   combined EditorState. Deterministic: identical output on every run and
   both compilers. *)

structure EC = EditorCore

val () = print "EditorCore demo\n"

(* ---- Buffer (piece table) ---- *)
val b0 = EC.fromString "Hello, world!"
val b1 = EC.insert (b0, 7, "there, ")
val () = print ("buffer after insert   = " ^ EC.toString b1 ^ "\n")
val b2 = EC.delete (b1, 0, 7)
val () = print ("buffer after delete   = " ^ EC.toString b2 ^ "\n")
val () = print ("slice [0,5)           = " ^ EC.slice (b2, 0, 5) ^ "\n")
val () = print ("length                = " ^ Int.toString (EC.length b2) ^ "\n")

(* ---- Cursor ---- *)
val cur0 = EC.cursor b2
val cur1 = EC.moveRight b2 cur0
val cur2 = EC.moveRight b2 cur1
val () = print ("cursor pos after 2x moveRight = " ^ Int.toString (EC.cursorPos cur2) ^ "\n")
val curEnd = EC.moveToLineEnd b2 cur2
val () = print ("cursor pos at line end        = " ^ Int.toString (EC.cursorPos curEnd) ^ "\n")

(* ---- Marks ---- *)
val marks0 = EC.emptyMarks
val marks1 = EC.setMark (marks0, "anchor", 3)
val marks2 = EC.adjustForInsert (marks1, 0, 5)
val () = print ("mark 'anchor' after inserting 5 chars before it = "
                ^ (case EC.getMark (marks2, "anchor") of SOME p => Int.toString p | NONE => "none")
                ^ "\n")

(* ---- EditorState (combined buffer + history + cursor + marks) ---- *)
val s0 = EC.newState "line one\nline two"
val s1 = EC.stateInsert (s0, 4, "XXX")
val () = print ("state after insert = " ^ EC.stateText s1 ^ "\n")
val s2 = EC.stateDelete (s1, 7, 4)
val () = print ("state after delete = " ^ EC.stateText s2 ^ "\n")
val s3 = EC.stateUndo s2
val () = print ("state after undo   = " ^ EC.stateText s3 ^ "\n")
val s4 = EC.stateRedo s3
val () = print ("state after redo   = " ^ EC.stateText s4 ^ "\n")
val () = print ("state cursor pos   = " ^ Int.toString (EC.cursorPos (EC.stateCursor s4)) ^ "\n")
