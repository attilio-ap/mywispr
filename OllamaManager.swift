import Foundation

/// Talks to the local Ollama server.
///
/// Every request targets `127.0.0.1` only — transcripts are never sent off the
/// machine by this class. When Ollama is unreachable the callbacks report
/// `success == false` and hand back the raw transcript, so a dictation is never
/// lost just because the model is down.
final class OllamaManager {

    /// Base URL of the local Ollama server.
    private static let baseURL = "http://127.0.0.1:11434"

    /// Sends the raw text to Ollama for cleanup. The completion runs on the main thread.
    /// - Returns: via completion, the processed text and whether Ollama actually answered.
    func cleanTranscript(
        _ rawText: String,
        modelName: String,
        temperature: Double,
        preset: AIPreset,
        customPrompt: String,
        language: AppLanguage,
        completion: @escaping (String, Bool) -> Void
    ) {
        let trimmed = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            DispatchQueue.main.async { completion("", true) }
            return
        }

        guard let url = URL(string: "\(Self.baseURL)/api/generate") else {
            DispatchQueue.main.async { completion(trimmed, false) }
            return
        }

        let prompt = buildPrompt(rawText: trimmed, preset: preset, customPrompt: customPrompt, language: language)
        let body: [String: Any] = [
            "model": modelName,
            "prompt": prompt,
            "stream": false,
            "options": ["temperature": temperature, "top_p": 0.9],
            "keep_alive": "5m"  // Release the RAM after 5 minutes of inactivity
        ]

        guard let bodyData = try? JSONSerialization.data(withJSONObject: body) else {
            DispatchQueue.main.async { completion(trimmed, false) }
            return
        }

        var request = URLRequest(url: url, timeoutInterval: 30)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = bodyData

        Logger.log("Ollama: sending transcript to model \(modelName) (temp: \(temperature), preset: \(preset.rawValue))...")

        URLSession.shared.dataTask(with: request) { data, _, error in
            if let error {
                Logger.log("Ollama NETWORK ERROR: \(error.localizedDescription). Falling back to the raw text.")
                DispatchQueue.main.async { completion(trimmed, false) }
                return
            }

            guard let data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let responseText = json["response"] as? String else {
                Logger.log("Ollama ERROR: malformed response. Falling back to the raw text.")
                DispatchQueue.main.async { completion(trimmed, false) }
                return
            }

            let cleaned = responseText
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\"")) // Strip stray wrapping quotes
                .trimmingCharacters(in: .whitespacesAndNewlines)

            Logger.logSensitive("Ollama cleaned text", cleaned)
            DispatchQueue.main.async { completion(cleaned, true) }
        }.resume()
    }

    /// Checks whether Ollama is listening on the local port.
    func checkConnection(completion: @escaping (Bool) -> Void) {
        guard let url = URL(string: "\(Self.baseURL)/api/tags") else {
            completion(false)
            return
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 1.5 // Short timeout so the dashboard never hangs on launch

        URLSession.shared.dataTask(with: request) { _, response, error in
            let connected = (error == nil && (response as? HTTPURLResponse)?.statusCode == 200)
            DispatchQueue.main.async { completion(connected) }
        }.resume()
    }

    /// Whether the given model is currently resident in RAM/VRAM.
    ///
    /// Used to show "Avvio modello AI..." instead of "Elaborazione..." when the
    /// model still has to be loaded, which can take several seconds.
    func isModelLoaded(_ modelName: String, completion: @escaping (Bool) -> Void) {
        fetchLoadedModels { loadedNames in
            let isLoaded = loadedNames.contains { name in
                name == modelName || name.hasPrefix(modelName + ":") || modelName.hasPrefix(name + ":")
            }
            completion(isLoaded)
        }
    }

    /// Models **installed** locally (`/api/tags`) — everything the user could select.
    func fetchAvailableModels(completion: @escaping ([String]) -> Void) {
        fetchModelNames(path: "/api/tags", timeout: 2.0, completion: completion)
    }

    /// Models **currently loaded** into RAM/VRAM (`/api/ps`) — a subset of the installed ones.
    ///
    /// Distinct from `fetchAvailableModels`: `/api/tags` lists what is on disk,
    /// `/api/ps` lists what is actually running right now.
    func fetchLoadedModels(completion: @escaping ([String]) -> Void) {
        fetchModelNames(path: "/api/ps", timeout: 1.0, completion: completion)
    }

    /// Shared helper for the two endpoints that return a `models` array.
    private func fetchModelNames(path: String, timeout: TimeInterval, completion: @escaping ([String]) -> Void) {
        guard let url = URL(string: "\(Self.baseURL)\(path)") else {
            DispatchQueue.main.async { completion([]) }
            return
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = timeout

        URLSession.shared.dataTask(with: request) { data, _, error in
            guard let data, error == nil,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let modelsArray = json["models"] as? [[String: Any]] else {
                DispatchQueue.main.async { completion([]) }
                return
            }

            let names = modelsArray.compactMap { $0["name"] as? String }
            DispatchQueue.main.async { completion(names) }
        }.resume()
    }

    /// Downloads a model from the Ollama registry (`/api/pull`).
    /// Downloads can take minutes, hence the long timeout.
    /// - Parameter l10n: string table used for the user-facing status message.
    func pullModel(_ model: String, l10n: L10n, completion: @escaping (Bool, String) -> Void) {
        guard let url = URL(string: "\(Self.baseURL)/api/pull") else {
            DispatchQueue.main.async { completion(false, l10n.ollamaInvalidURL) }
            return
        }

        let body: [String: Any] = ["name": model, "stream": false]
        guard let bodyData = try? JSONSerialization.data(withJSONObject: body) else {
            DispatchQueue.main.async { completion(false, l10n.ollamaSerializationError) }
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = bodyData
        request.timeoutInterval = 600

        Logger.log("Ollama: pulling model \(model)...")

        URLSession.shared.dataTask(with: request) { _, response, error in
            DispatchQueue.main.async {
                if let error {
                    Logger.log("Ollama pull failed: \(error.localizedDescription)")
                    completion(false, l10n.ollamaDownloadError(error.localizedDescription))
                    return
                }
                guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                    Logger.log("Ollama pull failed: model not found or server error.")
                    completion(false, l10n.ollamaModelNotFound)
                    return
                }
                Logger.log("Ollama: model \(model) pulled successfully.")
                completion(true, l10n.ollamaPullSuccess(model))
            }
        }.resume()
    }

    // MARK: - Prompt Construction

    /// Builds the full instruction prompt for the selected preset.
    ///
    /// The instructions are written in the target language rather than translated
    /// from one another: dictation fails differently in each language (Italian
    /// speakers mangle English technical terms phonetically, English speakers
    /// produce homophone errors), so each set is tuned for its own failure modes.
    private func buildPrompt(rawText: String, preset: AIPreset, customPrompt: String, language: AppLanguage) -> String {
        switch language {
        case .italian:
            return italianPrompt(rawText: rawText, preset: preset, customPrompt: customPrompt)
        case .english:
            return englishPrompt(rawText: rawText, preset: preset, customPrompt: customPrompt)
        }
    }

    // MARK: - Italian Prompts

    private func italianPrompt(rawText: String, preset: AIPreset, customPrompt: String) -> String {
        let presetInstruction: String
        switch preset {
        case .standard:
            presetInstruction = """
            Compito: Correggi, ripulisci e formatta la trascrizione vocale in italiano.
            Istruzioni operative dettagliate:
            - Rileva e risolvi le autocorrezioni e i ripensamenti dell'utente: se l'utente si corregge o cambia idea a metà frase (es. "ci vediamo alle 7... anzi no, alle 9" oppure "ti invio il file... no, l'e-mail"), la trascrizione finale deve riportare solo l'intento corretto (es. "Ci vediamo alle 9" o "Ti invio l'e-mail").
            - Correggi gli errori grammaticali, sintattici, ortografici e i refusi fonetici.
            - Rimuovi balbettii, ripetizioni involontarie e parole riempitive del parlato (ehm, uhm, cioè, tipo, allora, praticamente).
            - Mantieni la persona verbale originale e il significato finale voluto dall'utente.
            - NON spiegare le modifiche. Rispondi solo col testo pulito.
            """
        case .professional:
            presetInstruction = """
            Compito: Riformula la trascrizione vocale in un italiano formale, elegante e professionale.
            Istruzioni operative dettagliate:
            - Riscrivi il testo rendendolo perfetto per email di lavoro, comunicazioni formali o chat aziendali (Slack/Teams).
            - Rileva e risolvi le autocorrezioni e i ripensamenti dell'utente, rimuovendo le informazioni smentite a voce e mantenendo solo la versione finale corretta.
            - Traduci espressioni colloquiali o incomplete in formule sintatticamente impeccabili, fluide e professionali.
            - Conserva intatti tutti i dati sensibili ed essenziali (date, nomi, importi, decisioni).
            """
        case .bullets:
            presetInstruction = """
            Compito: Trasforma la trascrizione vocale in un elenco puntato strutturato ed estremamente sintetico.
            Istruzioni operative dettagliate:
            - Estrai i concetti chiave, i to-do e le decisioni menzionati nel dettato.
            - Risolvi e ignora i ripensamenti, le incertezze e le informazioni smentite a voce dall'utente durante la registrazione.
            - Organizza l'output in un elenco puntato Markdown ('-'), rendendo ogni punto conciso e orientato all'azione (es. verbi all'infinito per i task).
            """
        case .translation:
            presetInstruction = """
            Compito: Traduci la trascrizione vocale italiana in un inglese fluido, naturale e idiomatico.
            Istruzioni operative dettagliate:
            - **Risolvi prima i ripensamenti**: Rileva ed elabora le autocorrezioni e le incertezze dell'utente (es. se dice "ci vediamo alle 7... no, alle 9", comprendi che l'orario finale è le 9 e traduci direttamente in "See you at 9").
            - Rimuovi balbettii, esitazioni e parole riempitive tipiche del parlato italiano prima di tradurre.
            - Traduci l'intento finale corretto adottando un tono naturale e scorrevole (Business English se il contesto dedotto è lavorativo).
            - Mantieni corretti i nomi propri e i termini tecnici.
            """
        case .promptBuilder:
            presetInstruction = """
            Compito: Espandi l'idea o l'istruzione grezza dettata a voce in un prompt AI altamente strutturato ed ottimizzato.
            Istruzioni operative dettagliate:
            - Identifica e risolvi le autocorrezioni o i ripensamenti presenti nel dettato grezzo, concentrandoti solo sulle direttive finali volute.
            - Rimuovi incertezze, balbettii e divagazioni.
            - Organizza il prompt finale in sezioni Markdown chiare (es. `## Ruolo`, `## Contesto`, `## Istruzioni`, `## Vincoli`).
            - Assicurati che l'output contenga ESCLUSIVAMENTE il prompt pronto per la copia.
            """
        case .custom:
            presetInstruction = """
            Compito: Segui rigorosamente questa istruzione speciale definita dall'utente:
            "\(customPrompt)"
            """
        }

        return """
        Sei un assistente di scrittura vocale avanzato ed estremamente preciso. Il tuo compito è elaborare la trascrizione fornita.

        \(presetInstruction)

        Linee guida trasversali fondamentali:
        - Riconosci le parole inglesi trascritte erroneamente foneticamente in italiano e correggile (es. "tulle/tul" -> "tool", "svift/swifti" -> "Swift", "bild" -> "build", "opscion" -> "option", "gittab" -> "GitHub", "pul request" -> "pull request", "committare" -> "committare/commit", "deplorare/deploiare" -> "deployare/deploy", "end point" -> "endpoint", "debag" -> "debug").
        - Rileva il tono interrogativo: inserisci sempre il punto interrogativo (?) se la frase esprime una domanda.
        - Non aggiungere prefazioni (es. "Ecco il testo:", "Ecco il prompt espanso:"), scuse, spiegazioni, né racchiudere il testo finale tra virgolette. Rispondi SOLO ed ESCLUSIVAMENTE con il testo elaborato richiesto.

        Trascrizione grezza da elaborare:
        "\(rawText)"
        """
    }

    // MARK: - English Prompts

    private func englishPrompt(rawText: String, preset: AIPreset, customPrompt: String) -> String {
        let presetInstruction: String
        switch preset {
        case .standard:
            presetInstruction = """
            Task: Correct, clean up and format this English voice transcription.
            Detailed operating instructions:
            - Detect and resolve the speaker's self-corrections and changes of mind: if they correct themselves mid-sentence (e.g. "let's meet at 7... actually no, make it 9" or "send me the file... no, the email"), the final text must carry only the intended meaning (e.g. "Let's meet at 9" or "Send me the email").
            - Fix grammar, syntax and spelling, including the homophone errors typical of dictation (their/there/they're, its/it's, to/too/two, your/you're, affect/effect, whole/hole). Resolve each homophone from the meaning of the whole sentence rather than word by word, and correct the surrounding grammar to match: e.g. "there going to send they're report" becomes "They're going to send their report".
            - Remove stammers, involuntary repetitions and filler words (um, uh, er, like, you know, I mean, basically, actually, sort of, kind of, right).
            - Add correct punctuation and capitalisation, and split run-on sentences.
            - Keep the original grammatical person and the speaker's intended meaning.
            - Do NOT explain the changes. Reply with the cleaned text only.
            """
        case .professional:
            presetInstruction = """
            Task: Rewrite this English voice transcription in polished, professional English.
            Detailed operating instructions:
            - Rewrite the text so it is suitable for work email, formal communication or business chat (Slack/Teams).
            - Detect and resolve the speaker's self-corrections, dropping the retracted information and keeping only the final intended version.
            - Turn colloquial or incomplete phrasing into fluent, grammatically impeccable sentences.
            - Preserve every essential or sensitive detail intact (dates, names, figures, decisions).
            """
        case .bullets:
            presetInstruction = """
            Task: Turn this English voice transcription into a structured, highly concise bullet list.
            Detailed operating instructions:
            - Extract the key points, to-dos and decisions mentioned in the dictation.
            - Resolve and discard the speaker's changes of mind, hesitations and retracted statements.
            - Output a Markdown bullet list ('-'), keeping each point concise and action-oriented (imperative verbs for tasks).
            """
        case .translation:
            presetInstruction = """
            Task: Translate this English voice transcription into fluent, natural, idiomatic Italian.
            Detailed operating instructions:
            - **Resolve the changes of mind first**: detect and process the speaker's self-corrections (e.g. if they say "see you at 7... no, 9", understand the final time is 9 and translate directly as "Ci vediamo alle 9").
            - Remove stammers, hesitations and English filler words before translating.
            - Translate the corrected final intent with a natural, flowing tone (business Italian if the inferred context is professional).
            - Keep proper nouns and technical terms correct.
            """
        case .promptBuilder:
            presetInstruction = """
            Task: Expand this raw dictated idea or instruction into a highly structured, optimised AI prompt.
            Detailed operating instructions:
            - Identify and resolve any self-corrections or changes of mind in the raw dictation, focusing only on the final intended directives.
            - Remove hesitations, stammers and digressions.
            - Organise the final prompt into clear Markdown sections (e.g. `## Role`, `## Context`, `## Instructions`, `## Constraints`).
            - Make sure the output contains EXCLUSIVELY the ready-to-copy prompt.
            """
        case .custom:
            presetInstruction = """
            Task: Follow this special user-defined instruction strictly:
            "\(customPrompt)"
            """
        }

        return """
        You are an advanced, extremely precise voice writing assistant. Your task is to process the transcription provided.

        \(presetInstruction)

        Cross-cutting rules:
        - Recognise technical terms that dictation commonly mangles and restore them (e.g. "get hub" -> "GitHub", "my sequel" -> "MySQL", "post gress" -> "PostgreSQL", "pie torch" -> "PyTorch", "node jay ess" -> "Node.js", "cube c t l" -> "kubectl", "colonel" -> "kernel" in a computing context, "pull request", "end point" -> "endpoint", "dee bug" -> "debug").
        - Detect an interrogative tone: always add a question mark if the sentence is a question.
        - Do not add prefaces (e.g. "Here is the text:", "Here is the expanded prompt:"), apologies or explanations, and do not wrap the final text in quotation marks. Reply ONLY and EXCLUSIVELY with the processed text.

        Raw transcription to process:
        "\(rawText)"
        """
    }
}
