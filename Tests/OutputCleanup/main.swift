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

T.finish("OutputCleanup")
