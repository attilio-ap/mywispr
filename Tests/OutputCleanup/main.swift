import Foundation

// Deterministic cleanup of the prompt-builder output.
//
// The prompt forbids empty scaffolding sections, but models emit them anyway
// ("## Constraints" followed by "None specified"). Prompt rules are
// probabilistic; this pass is not. Unlike the Prompts suite it needs no model,
// so the guarantee is verified on every run.

let strip = OllamaManager.strippingEmptySections

T.section("empty sections are removed")
T.equal("English placeholder section dropped",
        strip("## Role\nSales Expert\n\n## Constraints\nNone specified"),
        "## Role\nSales Expert")
T.equal("Italian placeholder section dropped",
        strip("## Ruolo\nEsperto\n\n## Vincoli\nNon specificato"),
        "## Ruolo\nEsperto")
T.equal("several placeholders dropped at once",
        strip("## Instructions\nDo the thing\n\n## Context\nNot provided\n\n## Constraints\nN/A"),
        "## Instructions\nDo the thing")
T.equal("a heading with no body at all is dropped",
        strip("## Instructions\nDo the thing\n\n## Constraints"),
        "## Instructions\nDo the thing")

T.section("real content is never touched")
T.equal("ordinary sections survive",
        strip("## Role\nSales Expert\n\n## Instructions\nWrite emails"),
        "## Role\nSales Expert\n\n## Instructions\nWrite emails")
// Guard against over-eager matching: this body contains "none" but is real content.
T.equal("a long body containing a marker word is kept",
        strip("## Constraints\nLeave none of the requirements out, and make sure every clause is covered in full detail."),
        "## Constraints\nLeave none of the requirements out, and make sure every clause is covered in full detail.")
T.equal("plain text without headings is untouched",
        strip("Just a sentence with none of the structure."),
        "Just a sentence with none of the structure.")
T.equal("empty input stays empty", strip(""), "")

T.section("multi-line bodies")
T.equal("a multi-line real body is kept whole",
        strip("## Instructions\n- first\n- second\n\n## Constraints\nNone"),
        "## Instructions\n- first\n- second")

let preface = OllamaManager.strippingPreface

T.section("announcing prefaces are removed")
// Reported from real use: the model prefixed the cleaned text with a preface
// even though the prompt forbids it.
T.equal("Italian preface on its own line",
        preface("Ecco la trascrizione:\nCiao, come stai?"), "Ciao, come stai?")
T.equal("Italian preface on the same line",
        preface("Ecco il testo pulito: Ciao, come stai?"), "Ciao, come stai?")
T.equal("English preface",
        preface("Here is the cleaned text:\nHello, how are you?"), "Hello, how are you?")
T.equal("bare label",
        preface("Trascrizione: buongiorno a tutti"), "buongiorno a tutti")
T.equal("labelled variant",
        preface("Testo corretto:\nIl documento è pronto."), "Il documento è pronto.")

T.section("real content is never mistaken for a preface")
// A dictation may legitimately open with a colon-terminated phrase.
T.equal("a genuine note is kept",
        preface("Nota per il team: ricordarsi di aggiornare i documenti."),
        "Nota per il team: ricordarsi di aggiornare i documenti.")
T.equal("a name and a colon are kept",
        preface("Marco: confermato per domani."), "Marco: confermato per domani.")
// "testo" is intentionally not a bare label, since this is plausible dictation.
T.equal("a generic label is kept",
        preface("Testo: bozza numero uno"), "Testo: bozza numero uno")
T.equal("ordinary text is untouched",
        preface("Ciao, come stai?"), "Ciao, come stai?")
T.equal("a Markdown heading is never stripped",
        preface("## Istruzioni\nLeggi il system prompt."), "## Istruzioni\nLeggi il system prompt.")
T.equal("a bullet list is never stripped",
        preface("- primo punto\n- secondo punto"), "- primo punto\n- secondo punto")
T.equal("empty stays empty", preface(""), "")

T.section("preface and empty sections together")
T.equal("both passes apply to prompt-builder output",
        strip(preface("Ecco il prompt:\n## Ruolo\nEsperto\n\n## Vincoli\nNon specificato")),
        "## Ruolo\nEsperto")

T.finish("OutputCleanup")
