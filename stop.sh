#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

DRY_RUN=0
KEEP_CONTAINERS=0
ARG_COMPOSE=""

show_help() {
  cat <<'EOF'
Uso: ./stop.sh [watcher|watcher-4060|watcher-3090|4060|3090|archivo.yaml] [--keep] [--dry-run] [-h|--help]

Opciones:
  --keep      Solo detiene los contenedores (stop) sin removerlos (por defecto usa down)
  --dry-run   Muestra el comando sin ejecutar Docker
  -h, --help  Muestra esta ayuda

Sin perfil indicado, lee MINERU_COMPOSE_FILE de .env (por defecto watcher).
EOF
}

load_env_file() {
  local env_file="$1"
  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line%$'\r'}"
    [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue
    if [[ "$line" == *=* ]]; then
      local key="${line%%=*}"
      local val="${line#*=}"
      key="${key#"${key%%[![:space:]]*}"}"
      key="${key%"${key##*[![:space:]]}"}"
      if [[ "$val" =~ ^\"(.*)\"$ || "$val" =~ ^\'(.*)\'$ ]]; then
        val="${BASH_REMATCH[1]}"
      fi
      [[ -n "$key" ]] && export "$key=$val"
    fi
  done < "$env_file"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help)
      show_help
      exit 0
      ;;
    --dry-run)
      DRY_RUN=1
      ;;
    --keep)
      KEEP_CONTAINERS=1
      ;;
    watcher|watcher-4060)
      ARG_COMPOSE="compose.watcher-rtx4060-8gb.yaml"
      ;;
    watcher-3090)
      ARG_COMPOSE="compose.watcher-rtx3090-24gb.yaml"
      ;;
    4060)
      ARG_COMPOSE="compose.rtx4060-8gb.yaml"
      ;;
    3090)
      ARG_COMPOSE="compose.rtx3090-24gb.yaml"
      ;;
    -*)
      echo "[ERROR] Opcion desconocida: $1" >&2
      echo "Usa --help para ver las opciones disponibles." >&2
      exit 1
      ;;
    *)
      ARG_COMPOSE="$1"
      ;;
  esac
  shift
done

if [[ -f ".env" ]]; then
  load_env_file ".env"
fi

COMPOSE_FILE="${ARG_COMPOSE:-${MINERU_COMPOSE_FILE:-compose.watcher-rtx4060-8gb.yaml}}"

if [[ ! -f "$COMPOSE_FILE" ]]; then
  echo "[ERROR] No se encontro el archivo Compose: $COMPOSE_FILE" >&2
  exit 1
fi

if [[ "$KEEP_CONTAINERS" -eq 1 ]]; then
  ACTION=(stop)
else
  ACTION=(down --remove-orphans)
fi

if [[ "$DRY_RUN" -eq 1 ]]; then
  echo "[DRY-RUN] Compose: $COMPOSE_FILE"
  echo "[DRY-RUN] Comando: docker compose -f \"$COMPOSE_FILE\" ${ACTION[*]}"
  exit 0
fi

if ! command -v docker >/dev/null 2>&1 || ! docker info >/dev/null 2>&1 || ! docker compose version >/dev/null 2>&1; then
  echo "[ERROR] Docker o Docker Compose no esta corriendo o no esta instalado." >&2
  exit 1
fi

echo "[INFO] Deteniendo stack $COMPOSE_FILE..."
docker compose -f "$COMPOSE_FILE" "${ACTION[@]}"

echo
if [[ "$KEEP_CONTAINERS" -eq 1 ]]; then
  echo "[OK] Contenedores detenidos (preservados). Se libero la VRAM de la GPU."
else
  echo "[OK] Stack detenido y contenedores removidos. Se libero la VRAM de la GPU."
  echo "[OK] La imagen mineru:4-vllm y tus archivos se conservan intactos."
fi
