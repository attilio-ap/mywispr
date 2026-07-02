# MyWispr 🎙️✨

**MyWispr** è un'applicazione macOS nativa (scritta in Swift) che cattura e trascrive il dettato vocale, ripulendo e formattando il testo trascritto in tempo reale grazie a un modello linguistico locale in esecuzione su **Ollama**.

L'app presenta un'interfaccia minimale stile "Dynamic Island" (overlay) che mostra l'equalizzatore di registrazione, lo stato di elaborazione dell'AI e permette di cambiare al volo i preset di trascrizione.

---

## 📋 Requisiti di Sistema

* **Sistema Operativo:** macOS 13.0 Ventura o superiore.
* **Hardware:** Mac con chip **Apple Silicon** (M1, M2, M3, M4, ecc.) - l'app è configurata per la compilazione su architettura `arm64` in `build.sh`.
* **Dipendenze Hardware:**
  * Un microfono funzionante.
* **Dipendenze Software:**
  * **Xcode Command Line Tools** (per compilare i sorgenti Swift).
  * **Ollama** (per l'elaborazione del testo con modelli LLM locali).

---

## 🛠️ Installazione e Compilazione

L'app viene fornita sotto forma di codice sorgente e può essere compilata e installata direttamente nella cartella `/Applications` tramite lo script di compilazione incluso.

### 1. Prerequisiti di compilazione (Xcode Command Line Tools)
Se non lo hai già fatto, installa i componenti di compilazione di macOS aprendo il Terminale e digitando:
```bash
xcode-select --install
```

### 2. Installazione di Ollama e download del modello LLM
1. Scarica e installa **Ollama** da [ollama.com](https://ollama.com).
2. Avvia Ollama.
3. Scarica il modello consigliato eseguendo questo comando nel Terminale:
   ```bash
   ollama run qwen2.5:14b
   ```
   *(Nota: Puoi usare anche altri modelli, come `llama3`, `mistral` o modelli più leggeri come `qwen2.5:7b` o `qwen2.5:3b`. Potrai selezionare il modello direttamente dal pannello delle impostazioni dell'applicazione).*

### 3. Compilazione ed esecuzione di MyWispr
1. Apri il **Terminale** nella cartella del progetto:
   ```bash
   cd "/percorso/della/cartella/MyWispr"
   ```
2. Rendi lo script di compilazione eseguibile (se non lo è già):
   ```bash
   chmod +x build.sh
   ```
3. Avvia la compilazione:
   ```bash
   ./build.sh
   ```
   Lo script compilerà il codice, creerà l'app bundle `MyWispr.app`, la firmerà ad-hoc e la copierà automaticamente nella cartella **Applicazioni** del tuo Mac (`/Applications/MyWispr.app`).

4. Avvia l'applicazione con il comando:
   ```bash
   open /Applications/MyWispr.app
   ```
   O semplicemente cercandola in Spotlight.

---

## 🔑 Configurazione Permessi su macOS (FONDAMENTALE)

Al primo avvio (o dopo una nuova compilazione), macOS bloccherà alcune funzionalità dell'app per motivi di privacy. Segui questi passaggi per configurarla correttamente:

### 1. Accesso al Microfono e Riconoscimento Vocale
Quando richiesto dall'applicazione, acconsenti all'accesso per il **Microfono** e per il **Riconoscimento Vocale** (Speech Recognition).

### 2. Permessi di Accessibilità (Keyboard Shortcut)
L'app utilizza le API di Accessibilità per catturare la scorciatoia da tastiera globale (tasto `Opzione Destra` di default) per avviare/fermare la registrazione.
1. Vai in **Impostazioni di Sistema > Privacy e Sicurezza > Accessibilità**.
2. Abilita l'interruttore accanto a **MyWispr**.
3. *Se l'applicazione era già presente ma la scorciatoia non risponde:* Rimuovi l'app dalla lista selezionandola e cliccando sul tasto `-` in basso, quindi avvia l'app e aggiungila nuovamente.

---

## 🚀 Come Funziona l'App

1. **Avvio:** Avvia `MyWispr.app`. Vedrai una piccola "notch" (un indicatore ovale minimale) comparire in alto sullo schermo.
2. **Registrazione:** Tieni premuto o primi il tasto **Opzione Destra (Right Option / Alt Destro)** per iniziare a parlare. L'equalizzatore mostrerà il livello della tua voce.
3. **Elaborazione:** Rilascia o premi nuovamente il tasto per terminare. L'applicazione trascriverà le tue parole tramite le API native del sistema, invierà la trascrizione grezza a Ollama per ripulirla (correzione errori, rimozione balbettii, formattazione) e infine sostituirà o incollerà automaticamente il testo formattato dove si trova il tuo cursore.
4. **Dashboard delle Impostazioni:** Passa il mouse sopra la notch per espandere il menu rapido, oppure clicca sull'icona delle impostazioni per configurare:
   * Preset AI (Standard, Formale, Elenco Puntato, Traduzione Inglese, ecc.)
   * Selezione del modello Ollama locale.
   * Scorciatoia da tastiera personalizzata.
   * Glossario personalizzato (es. per termini tecnici o nomi propri difficili).
