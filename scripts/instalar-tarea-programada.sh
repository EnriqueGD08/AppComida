#!/bin/bash
#
#  instalar-tarea-programada.sh
#  AppComida
#
#  Autor: Enrique Gómez Díaz
#  Mail: enriquegd2004@gmail.com
#  Date: 2026-11-09
#  Plataforma: macOS · bash
#  Descripción: Instala (o desinstala) una tarea de launchd que ejecuta `reinstalar-iphone.sh` cada 4 horas
#  mientras el Mac está encendido, para renovar automáticamente el plazo de 7 días de la app en el iPhone.
#  macOS no permite que una tarea en segundo plano lea la carpeta Escritorio, así que el instalador copia el script
#  a una carpeta no protegida y la tarea compila desde su propia copia del repositorio (la rama main de GitHub),
#  por lo que se instala siempre la última versión subida.
#
#  Uso:
#    ./scripts/instalar-tarea-programada.sh <UDID del iPhone> [--probar]
#    ./scripts/instalar-tarea-programada.sh --desinstalar
#
#  --probar   Fuerza una reinstalación inmediata desde la tarea, para comprobar que todo funciona.
#  DRY_RUN=1  Solo muestra el archivo de la tarea, sin instalarla.
#

set -euo pipefail

LABEL="com.enrique.appcomida.reinstall"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
STATE_DIR="$HOME/Library/Application Support/AppComida-Reinstall"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOURCE_SCRIPT="$SCRIPT_DIR/reinstalar-iphone.sh"
TARGET="$STATE_DIR/reinstalar-iphone.sh"
REPO_URL="$(git -C "$SCRIPT_DIR/.." remote get-url origin 2>/dev/null || true)"

# Muestra cómo se usa el script.
uso() {
    echo "Uso: $0 <UDID del iPhone> [--probar]"
    echo "     $0 --desinstalar"
    echo "El UDID aparece en: xcrun devicectl list devices"
}

# Escribe en la salida estándar el archivo .plist de la tarea.
# Argumentos: el UDID del iPhone.
render_plist() {
    cat <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>$LABEL</string>
    <key>ProgramArguments</key>
    <array>
        <string>/bin/bash</string>
        <string>$TARGET</string>
    </array>
    <key>EnvironmentVariables</key>
    <dict>
        <key>DEVICE_ID</key>
        <string>$1</string>
        <key>REPO_URL</key>
        <string>$REPO_URL</string>
    </dict>
    <key>RunAtLoad</key>
    <true/>
    <key>StartInterval</key>
    <integer>14400</integer>
    <key>StandardOutPath</key>
    <string>$STATE_DIR/launchd.out.log</string>
    <key>StandardErrorPath</key>
    <string>$STATE_DIR/launchd.err.log</string>
</dict>
</plist>
EOF
}

case "${1:-}" in
    "" | -h | --help)
        uso
        exit 1
        ;;
    --desinstalar)
        launchctl bootout "gui/$(id -u)" "$PLIST" 2>/dev/null || true
        rm -f "$PLIST"
        echo "Tarea desinstalada."
        exit 0
        ;;
esac

DEVICE_ID="$1"
PROBAR="${2:-}"

if [ "${DRY_RUN:-0}" = "1" ]; then
    render_plist "$DEVICE_ID"
    exit 0
fi

if [ -z "$REPO_URL" ]; then
    echo "No se pudo leer la dirección del repositorio (git remote origin)." >&2
    exit 1
fi

mkdir -p "$HOME/Library/LaunchAgents" "$STATE_DIR"
cp "$SOURCE_SCRIPT" "$TARGET"
chmod +x "$TARGET"
render_plist "$DEVICE_ID" > "$PLIST"
plutil -lint "$PLIST" >/dev/null

if [ "$PROBAR" = "--probar" ]; then
    rm -f "$STATE_DIR/last_success"
fi

launchctl bootout "gui/$(id -u)" "$PLIST" 2>/dev/null || true
launchctl bootstrap "gui/$(id -u)" "$PLIST"

echo "Tarea instalada: se ejecuta al iniciar sesión y cada 4 horas."
echo "Registro:  $STATE_DIR/reinstall.log"
echo "Para quitarla: $0 --desinstalar"
