(* examples/demo.sml

   A small tour of `sml-unicode`. Built and run by `make example`. Prints the
   codepoints of a sample string, an NFC/NFD normalization example, and the
   grapheme clusters with their display widths. *)

fun hex cp =
  let
    val s = Int.fmt StringCvt.HEX cp
    val pad = if String.size s < 4 then CharVector.tabulate (4 - String.size s, fn _ => #"0") else ""
  in "U+" ^ pad ^ s end

fun intList xs = "[" ^ String.concatWith ", " (List.map hex xs) ^ "]"

fun line s = print (s ^ "\n")

val () = line "== sml-unicode demo =="
val () = line ""

(* The sample mixes ASCII, a precomposed accented letter, the euro sign,
   a CJK ideograph, and an emoji ZWJ family sequence. *)
val sample = "Cafe\204\129 \226\130\172 \228\184\173 \240\159\145\168\226\128\141\240\159\145\169"

val () = line ("sample bytes : " ^ Int.toString (String.size sample) ^ " bytes")

(* ---- codecs ---- *)
val cps = Unicode.decodeUtf8 sample
val () = line ("codepoints   : " ^ intList cps)
val () = line ("round-trips  : " ^ Bool.toString (Unicode.encodeUtf8 cps = sample))

val () = line ""

(* ---- normalization ---- *)
(* "Cafe" + combining acute (U+0065 U+0301) vs precomposed e-acute (U+00E9). *)
val composed   = [0x0043, 0x0061, 0x0066, 0x0065, 0x0301]   (* Cafe + combining *)
  val () = line "normalization of \"Cafe\204\129\" (Cafe + U+0301):"
val () = line ("  NFD : " ^ intList (Unicode.normalize Unicode.NFD composed))
val () = line ("  NFC : " ^ intList (Unicode.normalize Unicode.NFC composed))
val () = line ("  NFC collapses U+0065 U+0301 -> U+00E9: "
               ^ Bool.toString (Unicode.normalize Unicode.NFC composed
                                = [0x0043, 0x0061, 0x0066, 0x00E9]))

val () = line ""

(* ---- case folding ---- *)
val () = line ("caseFold(\"STRASSE\") -> "
               ^ Unicode.encodeUtf8 (Unicode.caseFold (Unicode.decodeUtf8 "STRASSE")))

val () = line ""

(* ---- grapheme clusters + width ---- *)
val () = line "grapheme clusters (cluster : codepoints : width):"
val clusters = Unicode.graphemes sample
fun clusterWidth g = List.foldl (fn (c, n) => n + Unicode.width c) 0 (Unicode.decodeUtf8 g)
val () =
  List.app
    (fn g =>
       line ("  " ^ g ^ "  : " ^ intList (Unicode.decodeUtf8 g)
             ^ " : w=" ^ Int.toString (clusterWidth g)))
    clusters
val () = line ("total clusters : " ^ Int.toString (List.length clusters))
