import Foundation

// Covers the bug where pausing mid-dictation reset the transcript to nothing.
//
// SFSpeechRecognizer ends its task whenever the speaker pauses, and MyWispr
// starts a replacement so the user can keep talking. Each new task reports its
// transcription from scratch, so without TranscriptAccumulator the replacement
// overwrote everything said before the pause.

T.section("the reported bug: speak, pause, speak again")
var a = TranscriptAccumulator()
a.update("hello world")                    // first task reports
a.commitCurrent()                          // pause -> task finalised and replaced
a.update("this is the second part")        // replacement starts from scratch
T.equal("text survives the pause", a.full, "hello world this is the second part")

T.section("three segments, two pauses")
a.reset()
for segment in ["one", "two", "three"] {
    a.update(segment)
    a.commitCurrent()
}
T.equal("all segments retained", a.full, "one two three")

T.section("a pause with nothing said in between")
a.reset()
a.update("only text"); a.commitCurrent()
a.update("");          a.commitCurrent()   // silent sub-session
a.update("more")
T.equal("no stray whitespace", a.full, "only text more")

T.section("whitespace reported by the recogniser")
a.reset()
a.update("  padded  "); a.commitCurrent()
a.update("  tail  ")
// Regression guard: trimming only the ends of the joined string left a double
// space at the seam between segments.
T.equal("normalised at the seam", a.full, "padded tail")

T.section("reset")
a.reset()
T.equal("empty after reset", a.full, "")

T.section("single segment (hold-to-talk, no pause)")
a.reset()
a.update("just one utterance")
T.equal("unchanged", a.full, "just one utterance")

T.section("committed is exposed for logging")
a.reset()
a.update("abc"); a.commitCurrent()
T.equal("committed only", a.committed, "abc")

T.section("the recogniser silently starting a new utterance")

// The real failure: SFSpeech never set isFinal, it just went back to reporting
// only the new words. Everything before the pause was lost.
a.reset()
a.update("buongiorno a tutti quanti")     // grows normally
a.update("buongiorno a tutti quanti oggi")
a.update("allora")                        // pause -> new utterance, much shorter
T.equal("the earlier sentence is kept", a.full, "buongiorno a tutti quanti oggi allora")

T.section("ordinary refinement is never mistaken for a reset")

a.reset()
a.update("ciao come")
a.update("ciao come stai")                 // growth
T.equal("growth replaces, does not duplicate", a.full, "ciao come stai")

a.reset()
a.update("ciao come stai")
a.update("Ciao, come stai?")               // punctuation and capitals added
T.equal("punctuation revision is not a new segment", a.full, "Ciao, come stai?")

a.reset()
a.update("il bonifico di tremila euro")
a.update("il bonifico di 3.000 euro")      // reworded, similar length
T.equal("rewording of similar length is not a new segment", a.full, "il bonifico di 3.000 euro")

a.reset()
a.update("uno")
a.update("uno due")
a.update("uno due tre")
T.equal("a short growing utterance is not chopped up", a.full, "uno due tre")

T.section("several pauses in one session")

a.reset()
a.update("prima frase abbastanza lunga")
a.update("seconda")
a.update("seconda frase")
a.update("terza")
T.equal("every segment survives", a.full, "prima frase abbastanza lunga seconda frase terza")

T.section("empty updates are ignored")

a.reset()
a.update("qualcosa")
a.update("")
a.update("   ")
T.equal("blank updates do not wipe the text", a.full, "qualcosa")

T.finish("TranscriptAccumulator")
