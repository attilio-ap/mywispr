#!/bin/bash
set -e

echo "=== Compilazione MyWispr per macOS (Apple Silicon) ==="

# Chiude l'applicazione se in esecuzione per sbloccare i file durante la compilazione
if pgrep -x "MyWispr" > /dev/null; then
    echo "Chiusura istanza attiva di MyWispr in corso..."
    killall "MyWispr" 2>/dev/null || true
    sleep 0.5
fi

# 1. File sorgenti
SOURCES="main.swift AppState.swift KeyboardManager.swift SpeechManager.swift OllamaManager.swift PasteManager.swift OverlayWindow.swift DashboardView.swift Logger.swift"
OUTPUT_BINARY="MyWispr"
APP_NAME="MyWispr.app"

# 2. SDK macOS
SDK_PATH=$(xcrun --show-sdk-path --sdk macosx)

echo "Compilazione in corso..."
swiftc -O \
    -sdk "$SDK_PATH" \
    -target arm64-apple-macosx13.0 \
    $SOURCES \
    -o "$OUTPUT_BINARY"

echo "Creazione del bundle ($APP_NAME)..."
mkdir -p "$APP_NAME/Contents/MacOS"
mv "$OUTPUT_BINARY" "$APP_NAME/Contents/MacOS/"

if [ -f "Info.plist" ]; then
    cp Info.plist "$APP_NAME/Contents/"
else
    echo "Errore: Info.plist non trovato!"
    exit 1
fi

# 2b. Copia l'icona dell'applicazione se presente
if [ -f "AppIcon.icns" ]; then
    mkdir -p "$APP_NAME/Contents/Resources"
    cp AppIcon.icns "$APP_NAME/Contents/Resources/"
    echo "Icona dell'applicazione configurata."
fi

# 3. Firma ad-hoc (FONDAMENTALE per i permessi di Accessibilità su macOS)
echo "Firma ad-hoc in corso..."
codesign --force --deep --sign - "$APP_NAME"

# 4. Copia automatica in /Applications
if [ -d "/Applications" ]; then
    echo "Copia automatica in /Applications in corso..."
    rm -rf "/Applications/$APP_NAME"
    cp -R "$APP_NAME" "/Applications/"
    echo "Copia in /Applications aggiornata!"
    # Rimuove la copia locale nel progetto per evitare duplicati in macOS Accessibility
    rm -rf "$APP_NAME"
    echo "Copia locale nel progetto rimossa per evitare conflitti."
fi

echo "=== Compilazione completata con successo! ==="
echo "Puoi avviare l'applicazione con: open /Applications/$APP_NAME"
echo ""
echo "NOTA: Se è la prima volta o hai ricompilato, vai in:"
echo "  Impostazioni di Sistema > Privacy e Sicurezza > Accessibilità"
echo "  e attiva MyWispr (toggle off/on se già presente)."
