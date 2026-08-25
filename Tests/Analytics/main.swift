import Foundation

// Covers two defects in the history/analytics path:
//  1. wordCount split on " " only, so the Bullet List preset's newline-separated
//     output silently merged words across line breaks.
//  2. updateRecord replaced the text without adjusting the running totals, so
//     every edit drifted Analytics away from the history it describes.

T.section("word count across line breaks")
let bullets = TranscriptionRecord(
    rawText: "x",
    cleanedText: "- Ship the endpoint\n- Debug the pipeline\n- Update docs")
T.equal("bullet list counted correctly", bullets.wordCount, 11)

let spaced = TranscriptionRecord(rawText: "x", cleanedText: "double  spaced   text")
T.equal("runs of spaces are not words", spaced.wordCount, 3)

T.section("totals follow edits")
let state = AppState()
state.clearHistory()

let record = TranscriptionRecord(rawText: "raw", cleanedText: "one two three")
state.addRecord(record)
T.equal("words after add", state.totalWords, 3)
T.equal("time saved after add", state.timeSavedSeconds, 3 * AppState.secondsSavedPerWord)

state.updateRecord(id: record.id, newCleanedText: "one two three four five")
T.equal("words after an edit that grows", state.totalWords, 5)
T.equal("time saved after growing", state.timeSavedSeconds, 5 * AppState.secondsSavedPerWord)

state.updateRecord(id: record.id, newCleanedText: "one")
T.equal("words after an edit that shrinks", state.totalWords, 1)
T.equal("time saved after shrinking", state.timeSavedSeconds, 1 * AppState.secondsSavedPerWord)

state.updateRecord(id: UUID(), newCleanedText: "ignored")
T.equal("unknown id is a no-op", state.totalWords, 1)

// Leave no residue in the developer's own UserDefaults.
state.clearHistory()

T.section("glossary substitution")
state.glossary = ["gittab": "GitHub"]
T.equal("word-boundary replacement", state.applyGlossary(to: "il gittab è lento"), "il GitHub è lento")
// Regression guard: an unescaped template treated "$1" as a capture reference.
state.glossary = ["prezzo": "costo $1"]
T.equal("replacement is not a regex template", state.applyGlossary(to: "il prezzo sale"), "il costo $1 sale")

T.section("word count is shown with the right plural")
// "1 words" was visible on every single-word row in the history list.
let it = L10n(.italian), en = L10n(.english)
T.equal("one, Italian",  it.historyWordCount(1), "1 parola")
T.equal("one, English",  en.historyWordCount(1), "1 word")
T.equal("many, Italian", it.historyWordCount(7), "7 parole")
T.equal("many, English", en.historyWordCount(7), "7 words")
T.equal("zero, English", en.historyWordCount(0), "0 words")

T.finish("Analytics")
