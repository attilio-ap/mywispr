# MyWispr 🎙️✨

**MyWispr** è un'applicazione macOS nativa, leggera ed elegante, scritta in Swift, progettata per rivoluzionare la dettatura vocale. Sfruttando le API di riconoscimento vocale di macOS e l'intelligenza artificiale locale tramite **Ollama**, MyWispr trascrive, corregge, formatta e incolla all'istante il tuo parlato in qualsiasi campo di testo attivo, eliminando errori grammaticali, ripetizioni e intercalari.

L'interfaccia utente è ispirata alla **Dynamic Island di Apple (Notch)**: un overlay fluttuante e minimale con effetto *glassmorphism* reale, che mostra feedback visivi in tempo reale durante la registrazione e l'elaborazione, espandendosi quando necessario per l'accesso rapido alle configurazioni.

---

## 🌟 Funzionalità Principali

### 1. Esperienza di Dettatura a Doppia Modalità
*   **Hold-to-Talk (Premi e Parla):** Tieni premuto l'hotkey globale (default: `Opzione Destra`) per registrare, rilascialo per trascrivere ed elaborare. Semplice e immediato.
*   **Lock-to-Listen (Modalità Mani Libere):** Premi **due volte rapidamente** l'hotkey per attivare la registrazione continua. MyWispr ascolterà costantemente il tuo parlato. Ogni volta che fai una pausa, trascriverà il blocco, lo elaborerà con l'AI, lo incollerà all'istante, e riavvierà automaticamente il microfono per continuare ad ascoltare.
    *   *Per disattivare il blocco:* Premi nuovamente l'hotkey o fai clic con il tasto sinistro del mouse in un punto qualsiasi dello schermo.
*   **Protezione dai Click Accidentali:** Se premi l'hotkey per errore per meno di `0.25` secondi senza parlare, la sessione viene annullata all'istante e la notch torna a riposo senza attivare alcuna elaborazione o inserimento di testo.

### 2. Interfaccia Stile "Dynamic Island" (Apple Glassmorphic Overlay)
*   **Vero Effetto Vetro (Glassmorphism):** Costruita con `.ultraThinMaterial` nativo di macOS e sagomata a capsula. Sfoca e lascia intravedere lo sfondo sottostante in perfetto stile Apple, arricchita da un sottile bordo e da un riflesso di luce superiore.
*   **Feedback Visivo Dinamico:**
    *   **Stato Idle:** Una linea sottile ed elegante integrata con lo schermo.
    *   **Stato Registrazione:** Mostra le barre dell'equalizzatore audio che si muovono al ritmo della tua voce o la trascrizione in tempo reale (streaming transcript) mentre parli.
    *   **Stato Elaborazione:** Un indicatore animato indica che l'AI locale sta rielaborando il testo.
*   **Menu Rapido al Passaggio del Mouse:** Passando il puntatore sopra la capsula, questa si espande per mostrarti i preset AI attivi e darti accesso rapido alla Dashboard.

### 3. Elaborazione AI Locale e Sicura al 100% (Ollama)
*   Nessun dato viene inviato a server esterni. Tutto viene elaborato localmente sul tuo Mac tramite **Ollama**.
*   **Preset AI Integrati:**
    *   *Standard:* Trascrizione pulita e fedele all'originale.
    *   *Formale:* Ottimizza il tono per email e contesti professionali.
    *   *Elenco Puntato:* Converte il parlato in una lista organizzata per punti.
    *   *Traduzione:* Traduce all'istante in lingua inglese.
    *   *Prompt Personalizzato:* Definisci le tue istruzioni specifiche per far formattare il testo all'AI.
*   **Controllo di Stato Intelligente:** L'app verifica se il modello LLM è già presente nella RAM/VRAM del tuo Mac prima di inviare la richiesta, indicando "Avvio modello AI..." se deve essere caricato, prevenendo lag e attese indefinite.
*   **Notifiche Offline:** Se Ollama è spento o non raggiungibile, MyWispr ti avvisa visivamente e applica un fallback sicuro per non perdere la trascrizione grezza.

### 4. Gestione Avanzata del Testo e Glossario
*   **Glossario Personalizzato:** Definisci una lista di parole o sigle personalizzate (es. nomi propri complessi, acronimi aziendali, termini tecnici o codici). L'applicazione sostituirà preventivamente le varianti errate della trascrizione prima dell'invio all'AI.
*   **Cronologia e Diff Viewer:** Accedi a una cronologia completa delle trascrizioni effettuate. Potrai confrontare graficamente il testo grezzo registrato con quello ripulito dall'AI tramite un sistema di evidenziazione dei cambiamenti (diff viewer).

### 5. Onboarding Intelligente e Gestione Permessi
*   Guida interattiva iniziale per abilitare i tre permessi richiesti (Microfono, Riconoscimento Vocale, Accessibilità).
*   Evita i tipici loop infiniti di macOS: cliccando sui pulsanti di onboarding verrai indirizzato direttamente alla specifica sezione delle Impostazioni di Sistema della privacy di macOS.

---

## 📋 Requisiti di Sistema

*   **OS:** macOS 13.0 Ventura o superiore.
*   **Hardware:** Mac con chip **Apple Silicon** (M1, M2, M3, M4, ecc.).
*   **Software Richiesto:**
    *   **Xcode Command Line Tools** (per la compilazione).
    *   **Ollama** (per l'elaborazione AI).

---

## 🛠️ Installazione e Compilazione

L'applicazione può essere compilata dai sorgenti ed essere installata in `/Applications` usando lo script automatizzato.

### 1. Installa gli Xcode Command Line Tools
Apri il terminale e digita:
```bash
xcode-select --install
```

### 2. Configura Ollama
1.  Scarica e installa Ollama da [ollama.com](https://ollama.com).
2.  Avvia l'applicazione Ollama.
3.  Scarica il modello predefinito da terminale (ad esempio, Qwen 2.5):
    ```bash
    ollama pull qwen2.5:14b
    ```
    *(Nota: puoi installare qualsiasi modello, come `llama3`, `mistral`, o varianti più leggere come `qwen2.5:7b` o `qwen2.5:3b`. Potrai sceglierlo comodamente dalle impostazioni dell'app).*

### 3. Compila MyWispr
1.  Apri il terminale nella cartella del progetto:
    ```bash
    cd "/percorso/di/MyWispr"
    ```
2.  Rendi eseguibile lo script di compilazione ed eseguilo:
    ```bash
    chmod +x build.sh
    ./build.sh
    ```
    Lo script compilerà i sorgenti Swift, creerà il pacchetto `MyWispr.app`, eseguirà una firma locale ad-hoc per aggirare i controlli del Gatekeeper e lo copierà in `/Applications`.

3.  Avvia l'applicazione:
    ```bash
    open /Applications/MyWispr.app
    ```

---

## 🔑 Configurazione Permessi su macOS

Al primo avvio, MyWispr ti guiderà nella concessione dei permessi tramite un popup di onboarding pulito.

1.  **Microfono & Riconoscimento Vocale:** Clicca su "Concedi" nel pannello di onboarding per acconsentire.
2.  **Accessibilità (Hotkey Globale):**
    *   Clicca su "Concedi" accanto a "Accesso all'Accessibilità". Verrai reindirizzato alle Impostazioni di Sistema.
    *   Attiva il toggle per **MyWispr**.
    *   **Nota importante per macOS:** Se i permessi non sembrano venire recepiti o l'hotkey non risponde nonostante il toggle attivo, disattiva e riattiva il toggle di MyWispr in Accessibilità per forzare macOS a svuotare la cache dei permessi TCC.
