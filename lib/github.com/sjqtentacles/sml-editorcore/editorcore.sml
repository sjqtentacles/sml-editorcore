(* editorcore.sml

   Piece-table buffer with undo/redo history, Unicode-aware cursor, and
   stable named marks. Pure Standard ML on the Basis library plus the
   vendored sml-unicode for grapheme segmentation. *)

structure EditorCore :> EDITORCORE =
struct
  (* ======================================================================
   * Buffer (piece table)
   * ====================================================================== *)

  datatype source = ORIGINAL | ADD

  (* A piece references [start, start+len) in one of the two buffers. *)
  type piece = {src : source, start : int, len : int}

  datatype buf =
      Buf of {original : string, add : string ref, pieces : piece list}

  exception Buffer of string

  val empty = Buf {original = "", add = ref "", pieces = []}

  fun fromString s =
      let
        val n = String.size s
      in
        if n = 0
        then Buf {original = "", add = ref "", pieces = []}
        else Buf {original = s, add = ref "",
                  pieces = [{src = ORIGINAL, start = 0, len = n}]}
      end

  fun length (Buf {pieces, ...}) =
      List.foldl (fn ({len, ...}, n) => n + len) 0 pieces

  (* Look up the text of a single piece given the buffer's backing stores. *)
  fun pieceTextRaw (original, add) {src, start, len} =
      let
        val base = case src of ORIGINAL => original | ADD => !add
      in
        String.substring (base, start, len)
      end

  fun toString (Buf {original, add, pieces, ...}) =
      String.concat (List.map (pieceTextRaw (original, add)) pieces)

  (* slice: extract [pos, pos+len) from the logical text by walking pieces. *)
  fun slice (Buf {original, add, pieces}, pos, len) =
      let
        fun walk ([], _, _) = []
          | walk ({src, start, len = plen} :: rest, p0, acc0) =
              let
                val pEnd = p0 + plen
                val aEnd = acc0 + plen
                (* overlap of [p0, pEnd) and [pos, pos+len) *)
                val lo = Int.max (p0, pos)
                val hi = Int.min (pEnd, pos + len)
              in
                if hi > lo
                then pieceTextRaw (original, add)
                       {src = src, start = start + (lo - p0), len = hi - lo}
                     :: walk (rest, pEnd, aEnd)
                else walk (rest, pEnd, aEnd)
              end
      in
        String.concat (walk (pieces, 0, 0))
      end

  (* insert: split the piece list at `pos`, splice a new piece referencing
     the appended text in `add`. *)
  fun insert (b, pos, s) =
      let
        val _ = if pos < 0 orelse pos > length b
                then raise Buffer ("insert: position out of range: " ^
                                     Int.toString pos)
                else ()
        val sLen = String.size s
      in
        if sLen = 0
        then b  (* inserting empty text is a no-op *)
        else
          let
            val Buf {original, add, pieces} = b
            val addLen = String.size (!add)
            val _ = add := !add ^ s
            val newPiece = {src = ADD, start = addLen, len = sLen}
            val newPieces = splitPiecesAt (pieces, pos, newPiece)
          in
            Buf {original = original, add = add, pieces = newPieces}
          end
      end

  (* Split the piece list at logical position `pos` and insert `newPiece`
     between the two halves. A piece that straddles `pos` is split into
     two pieces. *)
  and splitPiecesAt (pieces, pos, newPiece) =
      let
        fun walk ([], p0) =
              if pos = p0 then [newPiece]
              else raise Buffer "splitPiecesAt: internal"
          | walk ({src, start, len = plen} :: rest, p0) =
              let val pEnd = p0 + plen in
                if pos <= p0 then
                  newPiece :: {src = src, start = start, len = plen} :: rest
                else if pos >= pEnd then
                  {src = src, start = start, len = plen} :: walk (rest, pEnd)
                else
                  (* split this piece *)
                  let
                    val leftLen = pos - p0
                    val rightStart = start + leftLen
                    val left = {src = src, start = start, len = leftLen}
                    val right = {src = src, start = rightStart,
                                 len = plen - leftLen}
                  in
                    left :: newPiece :: right :: rest
                  end
              end
      in
        walk (pieces, 0)
      end

  (* delete: remove [pos, pos+len) by splitting pieces around the range
     and dropping the overlap. *)
  fun delete (b, pos, len) =
      let
        val _ = if pos < 0 orelse pos > length b
                then raise Buffer ("delete: position out of range: " ^
                                     Int.toString pos)
                else ()
        val bufLen = length b
        val len = Int.min (len, bufLen - pos)
        val _ = if len < 0 then raise Buffer "delete: negative effective len"
                else ()
      in
        if len = 0
        then b
        else
          let
            val Buf {original, add, pieces} = b
            val newPieces = deleteRange (pieces, pos, len)
          in
            Buf {original = original, add = add, pieces = newPieces}
          end
      end

  (* Walk pieces, dropping/clipping the [pos, pos+len) range. *)
  and deleteRange (pieces, pos, delLen) =
      let
        val delEnd = pos + delLen
        fun walk ([], _) = []
          | walk ({src, start, len = plen} :: rest, p0) =
              let val pEnd = p0 + plen in
                if pEnd <= pos then
                  (* entirely before deletion -- keep whole *)
                  {src = src, start = start, len = plen} :: walk (rest, pEnd)
                else if p0 >= delEnd then
                  (* entirely after -- keep whole *)
                  {src = src, start = start, len = plen} :: walk (rest, pEnd)
                else
                  let
                    (* clip this piece to [p0, pEnd) minus [pos, delEnd) *)
                    val keepBeforeLen = Int.max (0, pos - p0)
                    val keepAfterLen = Int.max (0, pEnd - delEnd)
                    val beforePiece =
                        if keepBeforeLen <= 0 then []
                        else [{src = src, start = start, len = keepBeforeLen}]
                    val afterPiece =
                        if keepAfterLen <= 0 then []
                        else [{src = src,
                               start = start + (plen - keepAfterLen),
                               len = keepAfterLen}]
                  in
                    beforePiece @ afterPiece @ walk (rest, pEnd)
                  end
              end
      in
        walk (pieces, 0)
      end

  (* ======================================================================
   * History (inline list zipper)
   * ====================================================================== *)

  datatype edit =
       InsertEdit of {pos : int, text : string}
     | DeleteEdit of {pos : int, len : int, text : string}

  datatype history =
      History of {past : edit list, future : edit list}

  val emptyHistory = History {past = [], future = []}

  fun push (History {past, future = _}, e) =
      History {past = e :: past, future = []}

  fun undo (History {past = [], ...}) = NONE
    | undo (History {past = e :: rest, future}) =
      SOME (e, History {past = rest, future = e :: future})

  fun redo (History {past, future = []}) = NONE
    | redo (History {past, future = e :: rest}) =
      SOME (e, History {past = e :: past, future = rest})

  (* ======================================================================
   * Cursor
   * ====================================================================== *)

  type cursor = {pos : int}

  exception Cursor of string

  fun cursor _ = {pos = 0}
  fun cursorAt i = {pos = i}
  fun cursorPos {pos} = pos

  fun clampPos (bufLen, p) =
      if p < 0 then 0
      else if p > bufLen then bufLen
      else p

  (* Grapheme boundaries on the whole buffer text. Returns a sorted list
     of byte offsets at which a grapheme starts (plus the final length). *)
  fun graphemeBreaks b =
      let
        val text = toString b
        val gs = Unicode.graphemes text
        fun walk ([], _) = []
          | walk (g :: rest, acc) =
              acc :: walk (rest, acc + String.size g)
        val breaks = walk (gs, 0)
        val total = String.size text
      in
        (breaks, total)
      end

  (* Find the largest break <= p (the start of the grapheme containing p,
     or p itself if p is a break). *)
  fun floorBreak (breaks, p) =
      let
        fun walk ([], last) = last
          | walk (b :: rest, last) =
              if b > p then last
              else walk (rest, b)
      in
        walk (breaks, 0)
      end

  (* Find the smallest break > p (the start of the next grapheme), or
     total if p is at/past the end. *)
  fun ceilBreak (breaks, p, total) =
      let
        fun walk ([], acc) = acc
          | walk (b :: rest, acc) =
              if b > p then b   (* found the smallest break > p *)
              else walk (rest, acc)
      in
        walk (breaks, total)
      end

  fun moveLeft b c =
      let
        val {pos} = c
        val (breaks, total) = graphemeBreaks b
        val p = clampPos (total, pos)
      in
        if p = 0 then {pos = 0}
        else
          (* find the largest break strictly less than p *)
          let
            fun walk ([], last) = last
              | walk (b :: rest, last) =
                  if b >= p then last
                  else walk (rest, b)
          in
            {pos = walk (breaks, 0)}
          end
      end

  fun moveRight b c =
      let
        val {pos} = c
        val (breaks, total) = graphemeBreaks b
        val p = clampPos (total, pos)
      in
        if p >= total then {pos = total}
        else {pos = ceilBreak (breaks, p, total)}
      end

  (* Line helpers. Lines are delimited by #"\n". Returns (lineStart, lineEnd)
     for the line containing position p, where lineEnd is the position of the
     newline (or total if the last line has no trailing newline). *)
  fun lineBounds (text, p) =
      let
        val total = String.size text
        val p = clampPos (total, p)
        fun scanBack i =
            if i <= 0 then 0
            else if String.sub (text, i - 1) = #"\n" then i
            else scanBack (i - 1)
        val lineStart = scanBack p
        fun scanFwd i =
            if i >= total then total
            else if String.sub (text, i) = #"\n" then i
            else scanFwd (i + 1)
        val lineEnd = scanFwd p
      in
        (lineStart, lineEnd)
      end

  fun moveToLineStart b c =
      let
        val text = toString b
        val {pos} = c
        val (start, _) = lineBounds (text, pos)
      in
        {pos = start}
      end

  fun moveToLineEnd b c =
      let
        val text = toString b
        val {pos} = c
        val (_, endPos) = lineBounds (text, pos)
      in
        {pos = endPos}
      end

  (* Compute the grapheme column of position p on its line. *)
  fun graphemeColumn (breaks, lineStart, p) =
      let
        fun walk ([], n) = n
          | walk (b :: rest, n) =
              if b >= p then n
              else if b >= lineStart then walk (rest, n + 1)
              else walk (rest, n)
      in
        walk (breaks, 0)
      end

  (* Nth grapheme-column position on the line [lineStart, lineEnd]. *)
  fun columnToPos (breaks, lineStart, lineEnd, col) =
      let
        val lineBreaks =
            List.filter (fn b => b >= lineStart andalso b < lineEnd) breaks
      in
        if col >= List.length lineBreaks then lineEnd
        else List.nth (lineBreaks, col)
      end

  fun moveUp b c =
      let
        val text = toString b
        val {pos} = c
        val (breaks, total) = graphemeBreaks b
        val (lineStart, lineEnd) = lineBounds (text, pos)
        val col = graphemeColumn (breaks, lineStart, pos)
      in
        if lineStart = 0 then
          {pos = 0}
        else
          let
            val prevEnd = lineStart - 1   (* position of the newline char *)
            val (prevStart, prevLineEnd) = lineBounds (text, prevEnd)
            val newPos = columnToPos (breaks, prevStart, prevLineEnd, col)
          in
            {pos = newPos}
          end
      end

  fun moveDown b c =
      let
        val text = toString b
        val {pos} = c
        val (breaks, total) = graphemeBreaks b
        val (lineStart, lineEnd) = lineBounds (text, pos)
        val col = graphemeColumn (breaks, lineStart, pos)
      in
        if lineEnd >= total then
          {pos = total}
        else
          let
            val nextStart = lineEnd + 1
            val (nextLineStart, nextLineEnd) = lineBounds (text, nextStart)
            val newPos = columnToPos (breaks, nextLineStart, nextLineEnd, col)
          in
            {pos = newPos}
          end
      end

  (* ======================================================================
   * Mark
   * ====================================================================== *)

  datatype marks = Marks of (string * int) list

  val emptyMarks = Marks []

  fun setMark (Marks ms, name, pos) =
      Marks ((name, pos) :: List.filter (fn (n, _) => n <> name) ms)

  fun getMark (Marks ms, name) =
      case List.find (fn (n, _) => n = name) ms of
          SOME (_, p) => SOME p
        | NONE => NONE

  fun removeMark (Marks ms, name) =
      Marks (List.filter (fn (n, _) => n <> name) ms)

  fun adjustForInsert (Marks ms, pos, len) =
      Marks (List.map (fn (n, p) =>
                        (n, if p >= pos then p + len else p)) ms)

  fun adjustForDelete (Marks ms, pos, delLen) =
      let
        val delEnd = pos + delLen
        fun adj p =
            if p <= pos then p
            else if p >= delEnd then p - delLen
            else pos
      in
        Marks (List.map (fn (n, p) => (n, adj p)) ms)
      end

  (* ======================================================================
   * EditorState
   * ====================================================================== *)

  type state = {buf : buf, history : history, cursor : cursor, marks : marks}

  fun newState s =
      let val b = fromString s
      in {buf = b, history = emptyHistory, cursor = cursor b,
          marks = emptyMarks}
      end

  fun stateInsert (st : state, pos, text) =
      let
        val {buf = b, history = h, cursor = _, marks = m} = st
        val newBuf = insert (b, pos, text)
        val edit = InsertEdit {pos = pos, text = text}
        val newHist = push (h, edit)
        val newMarks = adjustForInsert (m, pos, String.size text)
        val newCursor = {pos = pos + String.size text}
      in
        {buf = newBuf, history = newHist, cursor = newCursor, marks = newMarks}
      end

  fun stateDelete (st : state, pos, len) =
      let
        val {buf = b, history = h, cursor = _, marks = m} = st
        val bufLen = length b
        val effLen = Int.min (len, bufLen - pos)
        val effLen = if effLen < 0 then 0 else effLen
        val removed = slice (b, pos, effLen)
        val newBuf = delete (b, pos, effLen)
        val edit = DeleteEdit {pos = pos, len = effLen, text = removed}
        val newHist = push (h, edit)
        val newMarks = adjustForDelete (m, pos, effLen)
        val newCursor = {pos = pos}
      in
        {buf = newBuf, history = newHist, cursor = newCursor, marks = newMarks}
      end

  (* Apply an edit's inverse to the buffer. *)
  fun applyInverse (b, edit) =
      case edit of
          InsertEdit {pos, text} =>
            delete (b, pos, String.size text)
        | DeleteEdit {pos, text, ...} =>
            insert (b, pos, text)

  (* Reapply an edit (for redo). *)
  fun applyEdit (b, edit) =
      case edit of
          InsertEdit {pos, text} => insert (b, pos, text)
        | DeleteEdit {pos, len, ...} => delete (b, pos, len)

  fun stateUndo (st : state) =
      let
        val {buf = b, history = h, cursor = _, marks = m} = st
      in
        (case undo h of
             NONE => st
           | SOME (edit, h') =>
               let
                 val newBuf = applyInverse (b, edit)
                 val newMarks =
                     case edit of
                         InsertEdit {pos, text} =>
                           adjustForDelete (m, pos, String.size text)
                       | DeleteEdit {pos, text, ...} =>
                           adjustForInsert (m, pos, String.size text)
                 val newCursor =
                     case edit of
                         InsertEdit {pos, ...} => {pos = pos}
                       | DeleteEdit {pos, ...} => {pos = pos}
               in
                 {buf = newBuf, history = h', cursor = newCursor,
                  marks = newMarks}
               end)
      end

  fun stateRedo (st : state) =
      let
        val {buf = b, history = h, cursor = _, marks = m} = st
      in
        (case redo h of
             NONE => st
           | SOME (edit, h') =>
               let
                 val newBuf = applyEdit (b, edit)
                 val newMarks =
                     case edit of
                         InsertEdit {pos, text} =>
                           adjustForInsert (m, pos, String.size text)
                       | DeleteEdit {pos, len, ...} =>
                           adjustForDelete (m, pos, len)
                 val newCursor =
                     case edit of
                         InsertEdit {pos, text} =>
                           {pos = pos + String.size text}
                       | DeleteEdit {pos, ...} => {pos = pos}
               in
                 {buf = newBuf, history = h', cursor = newCursor,
                  marks = newMarks}
               end)
      end

  fun stateBuffer (st : state) = #buf st
  fun stateCursor (st : state) = #cursor st
  fun stateText (st : state) = toString (#buf st)
end
