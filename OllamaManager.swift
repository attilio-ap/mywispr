import Foundation

/// Gestisce la comunicazione con il server Ollama locale.
final class OllamaManager {

    var modelName: String

    init(modelName: String) {
        self.modelName = modelName
    }

    /// Invia il testo grezzo a Ollama per la pulizia. Chiama completion sul main thread.
    func cleanTranscript(
        _ rawText: String,
        modelName: String,
        temperature: Double,
        preset: AIPreset,
        customPrompt: String,
        completion: @escaping (String, Bool) -> Void
    ) {
        let trimmed = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            DispatchQueue.main.async { completion("", true) }
            return
        }

        guard let url = URL(string: "http://127.0.0.1:11434/api/generate") else {
            DispatchQueue.main.async { completion(trimmed, false) }
            return
        }

        let prompt = buildPrompt(rawText: trimmed, preset: preset, customPrompt: customPrompt)
        let body: [String: Any] = [
            "model": modelName,
            "prompt": prompt,
            "stream": false,
            "options": ["temperature": temperature, "top_p": 0.9],
            "keep_alive": "5m"  // Libera la RAM dopo 5 min di inattività
        ]

        guard let bodyData = try? JSONSerialization.data(withJSONObject: body) else {
            DispatchQueue.main.async { completion(trimmed, false) }
            return
        }

        var request = URLRequest(url: url, timeoutInterval: 30)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = bodyData

        Logger.log("Ollama: invio trascrizione al modello \(modelName) (temp: \(temperature), preset: \(preset.rawValue))...")

        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error {
                Logger.log("Ollama ERRORE di rete: \(error.localizedDescription). Uso testo grezzo.")
                DispatchQueue.main.async { completion(trimmed, false) }
                return
            }

            guard let data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let responseText = json["response"] as? String else {
                Logger.log("Ollama ERRORE: risposta non valida. Uso testo grezzo.")
                DispatchQueue.main.async { completion(trimmed, false) }
                return
            }

            let cleaned = responseText
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\"")) // Rimuove eventuali virgolette extra
                .trimmingCharacters(in: .whitespacesAndNewlines)

            Logger.log("Ollama: testo pulito → \(cleaned)")
            DispatchQueue.main.async { completion(cleaned, true) }
        }.resume()
    }

    /// Verifica se Ollama è attivo sulla porta locale.
    func checkConnection(completion: @escaping (Bool) -> Void) {
        guard let url = URL(string: "http://127.0.0.1:11434/api/tags") else {
            completion(false)
            return
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 1.5 // Timeout breve per non rallentare l'avvio della dashboard
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            let connected = (error == nil && (response as? HTTPURLResponse)?.statusCode == 200)
            DispatchQueue.main.async { completion(connected) }
        }.resume()
    }

    /// Verifica se il modello specificato è attualmente caricato in memoria (RAM/VRAM) su Ollama.
    func isModelLoaded(_ modelName: String, completion: @escaping (Bool) -> Void) {
        guard let url = URL(string: "http://127.0.0.1:11434/api/ps") else {
            completion(false)
            return
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 1.0
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            guard let data, error == nil,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let modelsArray = json["models"] as? [[String: Any]] else {
                DispatchQueue.main.async { completion(false) }
                return
            }
            
            let loadedNames = modelsArray.compactMap { $0["name"] as? String }
            let isLoaded = loadedNames.contains { name in
                name == modelName || name.hasPrefix(modelName + ":") || modelName.hasPrefix(name + ":")
            }
            DispatchQueue.main.async { completion(isLoaded) }
        }.resume()
    }
    
    /// Scarica l'elenco dei modelli installati localmente da Ollama.
    func fetchAvailableModels(completion: @escaping ([String]) -> Void) {
        guard let url = URL(string: "http://127.0.0.1:11434/api/tags") else {
            completion([])
            return
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 2.0
        
        URLSession.shared.dataTask(with: request) { data, response, error in
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

    private func buildPrompt(rawText: String, preset: AIPreset, customPrompt: String) -> String {
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
        case .englishTranslation:
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
}
