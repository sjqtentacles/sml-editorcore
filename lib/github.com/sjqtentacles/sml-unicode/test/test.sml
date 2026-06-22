structure Tests =
struct

  open Unicode

  (* UTF-8 byte strings for the test vectors (SML \ddd decimal escapes).
       eacute   U+00E9  -> C3 A9
       euro     U+20AC  -> E2 82 AC
       grin     U+1F600 -> F0 9F 98 80
       acute    U+0301  -> CC 81   (combining acute accent)
       riA      U+1F1FA -> F0 9F 87 BA  (regional indicator U)
       riB      U+1F1F8 -> F0 9F 87 B8  (regional indicator S)
       zwj      U+200D  -> E2 80 8D
       man      U+1F468 -> F0 9F 91 A8
       woman    U+1F469 -> F0 9F 91 A9 *)
  val eacuteU8 = "\195\169"
  val euroU8   = "\226\130\172"
  val grinU8   = "\240\159\152\128"
  val acuteU8  = "\204\129"
  val flagU8   = "\240\159\135\186\240\159\135\184"
  val zwjSeqU8 = "\240\159\145\168\226\128\141\240\159\145\169"

  fun runAll () =
    let
      (* ---- UTF-8 codec ---- *)
      val () = Harness.section "UTF-8"
      val () = Harness.checkIntList "decode ASCII"
                 ([72,101,108,108,111], decodeUtf8 "Hello")
      val () = Harness.checkString "encode ASCII"
                 ("Hello", encodeUtf8 [72,101,108,108,111])
      val () = Harness.checkIntList "decode 2-byte (e-acute U+00E9)"
                 ([0x00E9], decodeUtf8 eacuteU8)
      val () = Harness.checkString "encode 2-byte (e-acute U+00E9)"
                 (eacuteU8, encodeUtf8 [0x00E9])
      val () = Harness.checkIntList "decode 3-byte (euro U+20AC)"
                 ([0x20AC], decodeUtf8 euroU8)
      val () = Harness.checkString "encode 3-byte (euro U+20AC)"
                 (euroU8, encodeUtf8 [0x20AC])
      val () = Harness.checkIntList "decode 4-byte (grin U+1F600)"
                 ([0x1F600], decodeUtf8 grinU8)
      val () = Harness.checkString "encode 4-byte (grin U+1F600)"
                 (grinU8, encodeUtf8 [0x1F600])
      val () = Harness.checkString "round-trip mixed"
                 ("Hello, \195\169\226\130\172\240\159\152\128!",
                  encodeUtf8 (decodeUtf8 "Hello, \195\169\226\130\172\240\159\152\128!"))
      val () = Harness.checkRaises "reject lone continuation byte"
                 (fn () => decodeUtf8 "\128")
      val () = Harness.checkRaises "reject truncated 2-byte"
                 (fn () => decodeUtf8 "\195")
      val () = Harness.checkRaises "reject truncated 3-byte"
                 (fn () => decodeUtf8 "\226\130")
      val () = Harness.checkRaises "reject surrogate on encode"
                 (fn () => encodeUtf8 [0xD800])

      (* ---- UTF-16 codec ---- *)
      val () = Harness.section "UTF-16"
      val () = Harness.checkIntList "decode BE BMP (A)"
                 ([0x0041], decodeUtf16 BE "\000\065")
      val () = Harness.checkString "encode BE BMP (A)"
                 ("\000\065", encodeUtf16 BE [0x0041])
      val () = Harness.checkIntList "decode LE BMP (A)"
                 ([0x0041], decodeUtf16 LE "\065\000")
      val () = Harness.checkIntList "decode BE surrogate pair (grin U+1F600)"
                 ([0x1F600], decodeUtf16 BE "\216\061\222\000")
      val () = Harness.checkString "encode BE surrogate pair (grin U+1F600)"
                 ("\216\061\222\000", encodeUtf16 BE [0x1F600])
      val () = Harness.checkIntList "decode LE surrogate pair (grin U+1F600)"
                 ([0x1F600], decodeUtf16 LE "\061\216\000\222")
      val () = Harness.checkString "encode LE surrogate pair (grin U+1F600)"
                 ("\061\216\000\222", encodeUtf16 LE [0x1F600])
      val () = Harness.checkRaises "reject odd-length UTF-16"
                 (fn () => decodeUtf16 BE "\000")
      val () = Harness.checkRaises "reject unpaired high surrogate"
                 (fn () => decodeUtf16 BE "\216\061\000\065")

      (* ---- Normalization ---- *)
      val () = Harness.section "Normalization"
      (* e-acute: precomposed U+00E9 vs composed sequence U+0065 U+0301 *)
      val () = Harness.checkIntList "NFD of precomposed e-acute"
                 ([0x0065, 0x0301], normalize NFD [0x00E9])
      val () = Harness.checkIntList "NFD of decomposed e-acute is stable"
                 ([0x0065, 0x0301], normalize NFD [0x0065, 0x0301])
      val () = Harness.checkIntList "NFC of decomposed e-acute"
                 ([0x00E9], normalize NFC [0x0065, 0x0301])
      val () = Harness.checkIntList "NFC of precomposed e-acute is stable"
                 ([0x00E9], normalize NFC [0x00E9])
      val () = Harness.checkIntList "NFD agrees for both spellings"
                 (normalize NFD [0x00E9], normalize NFD [0x0065, 0x0301])
      val () = Harness.checkIntList "NFC agrees for both spellings"
                 (normalize NFC [0x00E9], normalize NFC [0x0065, 0x0301])
      (* canonical ordering: acute (ccc 230) after dot-below (ccc 220) *)
      val () = Harness.checkIntList "canonical reorder of combining marks"
                 ([0x0071, 0x0323, 0x0301], normalize NFD [0x0071, 0x0301, 0x0323])
      val () = Harness.checkIntList "NFC idempotent on reordered marks"
                 (normalize NFC [0x0071, 0x0301, 0x0323],
                  normalize NFC (normalize NFC [0x0071, 0x0301, 0x0323]))
      (* idempotence NFC(NFD(x)) = NFC(x) across the set *)
      val () = Harness.checkIntList "NFC(NFD(e-acute)) = NFC(e-acute)"
                 (normalize NFC [0x00E9], normalize NFC (normalize NFD [0x00E9]))
      val () = Harness.checkIntList "NFD idempotent"
                 (normalize NFD [0x00C0, 0x00E9],
                  normalize NFD (normalize NFD [0x00C0, 0x00E9]))

      (* ---- Case folding ---- *)
      val () = Harness.section "Case folding"
      val () = Harness.checkIntList "fold ASCII uppercase"
                 ([0x0061], caseFold [0x0041])
      val () = Harness.checkIntList "fold STRASSE -> strasse"
                 ([0x73,0x74,0x72,0x61,0x73,0x73,0x65],
                  caseFold [0x53,0x54,0x52,0x41,0x53,0x53,0x45])
      val () = Harness.checkIntList "fold Greek capital sigma -> small sigma"
                 ([0x03C3], caseFold [0x03A3])
      val () = Harness.checkIntList "fold leaves lowercase unchanged"
                 ([0x0061,0x0062,0x0063], caseFold [0x0061,0x0062,0x0063])

      (* ---- Grapheme segmentation ---- *)
      val () = Harness.section "Graphemes"
      val () = Harness.checkStringList "plain ASCII splits per char"
                 (["a","b","c"], graphemes "abc")
      val () = Harness.checkStringList "base + combining is one cluster"
                 (["a" ^ acuteU8], graphemes ("a" ^ acuteU8))
      val () = Harness.checkInt "regional-indicator flag is one cluster"
                 (1, List.length (graphemes flagU8))
      val () = Harness.checkInt "emoji ZWJ sequence is one cluster"
                 (1, List.length (graphemes zwjSeqU8))
      val () = Harness.checkInt "grin emoji alone is one cluster"
                 (1, List.length (graphemes grinU8))
      val () = Harness.checkStringList "CRLF stays together"
                 (["\013\010"], graphemes "\013\010")
      val () = Harness.checkInt "mixed string cluster count"
                 (4, List.length (graphemes ("a" ^ acuteU8 ^ "b" ^ euroU8 ^ flagU8)))

      (* ---- Width ---- *)
      val () = Harness.section "Width"
      val () = Harness.checkInt "ASCII width 1" (1, width 0x0061)
      val () = Harness.checkInt "combining mark width 0" (0, width 0x0301)
      val () = Harness.checkInt "zero-width joiner width 0" (0, width 0x200D)
      val () = Harness.checkInt "CJK ideograph width 2" (2, width 0x4E2D)
      val () = Harness.checkInt "hiragana width 2" (2, width 0x3042)
      val () = Harness.checkInt "fullwidth A width 2" (2, width 0xFF21)
      val () = Harness.checkInt "emoji width 2" (2, width 0x1F600)
      val () = Harness.checkInt "latin-1 letter width 1" (1, width 0x00E9)
    in
      ()
    end

  fun run () = (Harness.reset (); runAll (); Harness.run ())
end
