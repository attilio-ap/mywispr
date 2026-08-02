import Foundation

// Covers the bug where pausing mid-dictation reset the transcript to nothing.
//
// SFSpeechRecognizer ends its task whenever the speaker pauses, and MyWispr
// starts a replacement so the user can keep talking. Each new task reports its
// transcription from scratch, so without TranscriptAccumulator the replacement
// overwrote everything said before the pause.

T.section("the reported bug: speak, pause, speak again")
var a = TranscriptAccumulator()
a.current = "hello world"                  // first task reports
a.commitCurrent()                          // pause -> task finalised and replaced
a.current = "this is the second part"      // replacement starts from scratch
T.equal("text survives the pause", a.full, "hello world this is the second part")

T.section("three segments, two pauses")
a.reset()
for segment in ["one", "two", "three"] {
    a.current = segment
    a.commitCurrent()
}
T.equal("all segments retained", a.full, "one two three")

T.section("a pause with nothing said in between")
a.reset()
a.current = "only text"; a.commitCurrent()
a.current = "";          a.commitCurrent()   // silent sub-session
a.current = "more"
T.equal("no stray whitespace", a.full, "only text more")

T.section("whitespace reported by the recogniser")
a.reset()
a.current = "  padded  "; a.commitCurrent()
a.current = "  tail  "
// Regression guard: trimming only the ends of the joined string left a double
// space at the seam between segments.
T.equal("normalised at the seam", a.full, "padded tail")

T.section("reset")
a.reset()
T.equal("empty after reset", a.full, "")

T.section("single segment (hold-to-talk, no pause)")
a.reset()
a.current = "just one utterance"
T.equal("unchanged", a.full, "just one utterance")

T.section("committed is exposed for logging")
a.reset()
a.current = "abc"; a.commitCurrent()
T.equal("committed only", a.committed, "abc")

T.finish("TranscriptAccumulator")
