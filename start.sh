#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

DRY_RUN=0
FORCE_BUILD=0
ARG_COMPOSE=""

show_help() {
  cat <<'EOF'
Uso: ./start.sh [watcher|watcher-4060|watcher-3090|4060|3090|archivo.yaml] [--build] [--dry-run] [-h|--help]

Perfiles disponibles:
  watcher       WebUI + Watcher 4060 8 GB  (compose.watcher-rtx4060-8gb.yaml)
  watcher-4060  WebUI + Watcher 4060 8 GB  (compose.watcher-rtx4060-8gb.yaml)
  watcher-3090  WebUI + Watcher 3090 24 GB (compose.watcher-rtx3090-24gb.yaml)
  4060          Solo WebUI RTX 4060 8 GB   (compose.rtx4060-8gb.yaml)
  3090          Solo WebUI RTX 3090 24 GB  (compose.rtx3090-24gb.yaml)

Opciones:
  --build     Fuerza la recompilacion de la imagen Docker
  --dry-run   Muestra las rutas y el comando sin ejecutar Docker
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

ensure_dir() {
  local dir_path="${1:-}"
  [[ -z "$dir_path" ]] && return 0
  if [[ "$dir_path" =~ ^[A-Za-z]:[/\\] ]]; then
    echo "[AVISO] Se detecto una ruta de Windows en .env ($dir_path). Ajustala a una ruta Linux antes de usar el watcher."
    return 0
  fi
  if [[ "$DRY_RUN" -eq 0 ]]; then
    mkdir -p "$dir_path"
  fi
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
    --build)
      FORCE_BUILD=1
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

if [[ ! -f ".env" && -f ".env.example" ]]; then
  cp ".env.example" ".env"
  echo "[INFO] No existia .env; se creo a partir de .env.example."
fi

if [[ -f ".env" ]]; then
  load_env_file ".env"
fi

MINERU_WEBUI_PORT="${MINERU_WEBUI_PORT:-7860}"
MINERU_API_PORT="${MINERU_API_PORT:-8000}"
COMPOSE_FILE="${ARG_COMPOSE:-${MINERU_COMPOSE_FILE:-compose.watcher-rtx4060-8gb.yaml}}"

if [[ ! -f "$COMPOSE_FILE" ]]; then
  echo "[ERROR] No se encontro el archivo Compose: $COMPOSE_FILE" >&2
  exit 1
fi

IS_WATCHER=0
if [[ "$COMPOSE_FILE" == "compose.watcher-rtx4060-8gb.yaml" || "$COMPOSE_FILE" == "compose.watcher-rtx3090-24gb.yaml" ]]; then
  IS_WATCHER=1
  MINERU_INPUT_DIR="${MINERU_INPUT_DIR:-./libros/entrada}"
  MINERU_OUTPUT_DIR="${MINERU_OUTPUT_DIR:-./libros/salida}"
  MINERU_PROCESSED_DIR="${MINERU_PROCESSED_DIR:-./libros/procesados}"
  MINERU_FAILED_DIR="${MINERU_FAILED_DIR:-./libros/fallidos}"
fi

ensure_dir "${MINERU_INPUT_DIR:-}"
ensure_dir "${MINERU_OUTPUT_DIR:-}"
ensure_dir "${MINERU_PROCESSED_DIR:-}"
ensure_dir "${MINERU_FAILED_DIR:-}"

DOCKER_OK=1
if ! command -v docker >/dev/null 2>&1 || ! docker info >/dev/null 2>&1 || ! docker compose version >/dev/null 2>&1; then
  DOCKER_OK=0
fi

if [[ "$DOCKER_OK" -eq 0 ]]; then
  if [[ "$DRY_RUN" -eq 1 ]]; then
    echo "[AVISO] Docker o Docker Compose no esta disponible/activo en este entorno."
  else
    echo "[ERROR] Docker o Docker Compose no esta corriendo o no esta instalado." >&2
    exit 1
  fi
fi

BUILD_ARGS=()
if [[ "$FORCE_BUILD" -eq 1 ]]; then
  BUILD_ARGS+=(--build)
elif [[ "$DOCKER_OK" -eq 1 ]] && ! docker image inspect mineru:4-vllm >/dev/null 2>&1; then
  BUILD_ARGS+=(--build)
fi

if [[ "$DRY_RUN" -eq 1 ]]; then
  echo "[DRY-RUN] Compose: $COMPOSE_FILE"
  if [[ "$IS_WATCHER" -eq 1 ]]; then
    [[ -n "${MINERU_INPUT_DIR:-}" ]] && echo "[DRY-RUN] Entrada: $MINERU_INPUT_DIR"
    [[ -n "${MINERU_OUTPUT_DIR:-}" ]] && echo "[DRY-RUN] Salida:  $MINERU_OUTPUT_DIR"
  fi
  echo "[DRY-RUN] Comando: docker compose -f \"$COMPOSE_FILE\" up -d${BUILD_ARGS[*]:+ ${BUILD_ARGS[*]}}"
  exit 0
fi

if [[ ${#BUILD_ARGS[@]} -gt 0 ]]; then
  echo "[INFO] Compilando imagen mineru:4-vllm y levantando $COMPOSE_FILE..."
else
  echo "[INFO] Levantando $COMPOSE_FILE (reutilizando imagen local sin recompilar)..."
fi

docker compose -f "$COMPOSE_FILE" up -d ${BUILD_ARGS[@]+"${BUILD_ARGS[@]}"}

echo
docker compose -f "$COMPOSE_FILE" ps
echo
echo "[OK] WebUI disponible en: http://localhost:${MINERU_WEBUI_PORT}"
if [[ "$IS_WATCHER" -eq 1 ]]; then
  echo "[OK] API OpenAPI docs:    http://localhost:${MINERU_API_PORT}/docs"
  echo "[OK] Carpeta entrada:     ${MINERU_INPUT_DIR}"
  echo "[OK] Carpeta salida:      ${MINERU_OUTPUT_DIR}"
  echo "[OK] Logs del watcher:    docker logs -f mineru-watcher"
fi
