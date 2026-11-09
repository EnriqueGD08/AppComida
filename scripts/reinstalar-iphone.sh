#!/bin/bash
#
#  reinstalar-iphone.sh
#  AppComida
#
#  Autor: Enrique Gómez Díaz
#  Mail: enriquegd2004@gmail.com
#  Date: 2026-11-09
#  Plataforma: macOS · bash
#  Descripción: Reinstala la app en el iPhone para renovar el plazo de 7 días de las cuentas gratuitas de Apple.
#  Pensado para ejecutarse desde una tarea programada (launchd) cada pocas horas: solo actúa si han pasado
#  MIN_DAYS días desde la última instalación correcta, y reintenta en la siguiente ejecución si falla.
#
#  Variables de entorno:
#    DEVICE_ID    (obligatoria) Identificador (UDID) del iPhone, como aparece en `xcrun devicectl list devices`.
#    MIN_DAYS     Días mínimos entre reinstalaciones. Por defecto 5.
#    WARN_DAYS    Días desde la última instalación a partir de los cuales un fallo avisa con una notificación. Por defecto 6.
#    FORCE        Con valor 1 ignora MIN_DAYS y reinstala ya.
#    PROJECT_DIR  Carpeta del proyecto. Por defecto, la carpeta que contiene `scripts/`.
#    STATE_DIR    Carpeta donde se guardan el registro y la fecha de la última instalación.
#

set -uo pipefail

PATH="/usr/bin:/bin:/usr/sbin:/sbin:/Applications/Xcode.app/Contents/Developer/usr/bin"

: "${DEVICE_ID:?Define DEVICE_ID con el UDID del iPhone}"
MIN_DAYS="${MIN_DAYS:-5}"
WARN_DAYS="${WARN_DAYS:-6}"
FORCE="${FORCE:-0}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="${PROJECT_DIR:-$(dirname "$SCRIPT_DIR")}"
STATE_DIR="${STATE_DIR:-$HOME/Library/Application Support/AppComida-Reinstall}"
STAMP="$STATE_DIR/last_success"
LOG="$STATE_DIR/reinstall.log"
LOCK="$STATE_DIR/lock"
DERIVED="$STATE_DIR/DerivedData"
APP="$DERIVED/Build/Products/Debug-iphoneos/AppComida.app"

mkdir -p "$STATE_DIR"

# Escribe una línea con fecha en el registro.
# Argumentos: el mensaje.
log() {
    printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >> "$LOG"
}

# Muestra una notificación de macOS.
# Argumentos: título y texto (sin comillas dobles).
notify() {
    osascript -e "display notification \"$2\" with title \"$1\"" >/dev/null 2>&1 || true
}

now=$(date +%s)
last=$(cat "$STAMP" 2>/dev/null || echo 0)
age_days=$(( (now - last) / 86400 ))

# Registra el fallo y, si el plazo está a punto de acabar, avisa con una notificación.
# Argumentos: motivo del fallo.
fail() {
    log "ERROR: $1"
    if [ "$age_days" -ge "$WARN_DAYS" ]; then
        notify "AppComida: no se pudo reinstalar" "La app caduca pronto. Desbloquea el iPhone y conéctalo a la misma wifi que el Mac."
    fi
    exit 1
}

# Todavía no toca reinstalar.
if [ "$FORCE" != "1" ] && [ "$age_days" -lt "$MIN_DAYS" ]; then
    exit 0
fi

# Evita dos ejecuciones a la vez; descarta un bloqueo de más de dos horas (ejecución interrumpida).
if [ -d "$LOCK" ] && [ -n "$(find "$LOCK" -maxdepth 0 -mmin +120 2>/dev/null)" ]; then
    rmdir "$LOCK" 2>/dev/null
fi
if ! mkdir "$LOCK" 2>/dev/null; then
    exit 0
fi
trap 'rmdir "$LOCK" 2>/dev/null' EXIT

log "Inicio (última instalación hace $age_days días)"

if ! xcrun devicectl device info details --device "$DEVICE_ID" >/dev/null 2>&1; then
    fail "No se puede contactar con el iPhone (¿bloqueado, apagado o fuera de la red?)"
fi

if ! xcodebuild \
        -project "$PROJECT_DIR/AppComida.xcodeproj" \
        -scheme AppComida \
        -destination "id=$DEVICE_ID" \
        -derivedDataPath "$DERIVED" \
        -allowProvisioningUpdates \
        build >> "$LOG" 2>&1; then
    fail "Falló la compilación o la firma (más detalles arriba en este registro)"
fi

if ! xcrun devicectl device install app --device "$DEVICE_ID" "$APP" >> "$LOG" 2>&1; then
    fail "Falló la instalación en el iPhone"
fi

echo "$now" > "$STAMP"
log "Instalación correcta"
notify "AppComida" "App reinstalada en el iPhone. Plazo renovado 7 días."
