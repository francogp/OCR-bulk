# MinerU 4.x WebUI con GPU NVIDIA en Arcane

Configuraciones Docker Compose autocontenidas para desplegar **MinerU 4.x** (WebUI en puerto `7860`) optimizadas para convertir **libros escaneados** a Markdown, JSON, LaTeX y EPUB usando aceleración por GPU NVIDIA.

Ambas configuraciones usan `build.dockerfile_inline` (Compose Spec ≥ 2.17) y omiten `profiles:` para que puedas pegar **un único YAML en Arcane** y presionar **Build & Deploy** sin subir archivos adicionales.

---

## Comparativa de configuraciones

| Archivo | GPU objetivo | VRAM | Motor VLM + Small | Tiers habilitados en WebUI | Uso recomendado |
| --- | --- | --- | --- | --- | --- |
| [compose.rtx3090-24gb.yaml](compose.rtx3090-24gb.yaml) | RTX 3090 (Ampere CC 8.6) | 24 GB | `vllm` + `torch` | `flash`, `basic`, `standard`, `advanced` | Máxima velocidad y calidad en libros completos complejos |
| [compose.rtx4060-8gb.yaml](compose.rtx4060-8gb.yaml) | RTX 4060 Laptop (Ada CC 8.9) | 8 GB | `vllm` (`mineru-vlm` con `--gpu-memory-utilization 0.65` + `--enforce-eager`) + `torch` | `flash`, `basic`, `standard` | Pruebas y lotes en notebook 100% en CUDA sin errores de memoria (OOM) |
| [compose.watcher-rtx4060-8gb.yaml](compose.watcher-rtx4060-8gb.yaml) | RTX 4060 Laptop | 8 GB | `vllm` (`0.65` + `--enforce-eager`) + `torch` vía `mineru-api` | `flash`, `basic`, `standard` | WebUI en `7860` + carpeta vigilada automática (`mineru-watcher`) en 8 GB |
| [compose.watcher-rtx3090-24gb.yaml](compose.watcher-rtx3090-24gb.yaml) | RTX 3090 | 24 GB | `vllm` (`0.70`, CUDA Graphs activos) + `torch` vía `mineru-api` | `flash`, `basic`, `standard`, `advanced` | WebUI en `7860` + carpeta vigilada automática (`mineru-watcher`) en 24 GB |

> **Nota sobre tiempos y disco del primer build:** La primera compilación descarga la imagen base (~8–10 GB), instala `mineru[torch]>=4.0,<5` y pre-descarga los modelos de Hugging Face dentro de la imagen (`MINERU_MODEL_SOURCE=local`). Calculá **10–25 minutos** y **25–30 GB libres** la primera vez; los reinicios posteriores son instantáneos.

---

## Prerrequisitos en cada equipo

### 1. Verificar versión de CUDA del driver NVIDIA
Ejecutá en una terminal del equipo donde corre Docker/Arcane:

```bash
nvidia-smi
```

Mirá la esquina superior derecha (`CUDA Version: ...`):
- **CUDA 13.0 o superior:** Dejá `FROM vllm/vllm-openai:v0.21.0` tal como está.
- **CUDA 12.x (por ejemplo `12.8` o `12.9`):** En el YAML correspondiente, comentá `FROM vllm/vllm-openai:v0.21.0` y descomentá `# FROM vllm/vllm-openai:v0.21.0-cu129` antes de compilar.

### 2. Soporte de GPU en Docker
- **Linux (servidor con RTX 3090):**
  - Tener instalado el driver propietario de NVIDIA y **`nvidia-container-toolkit`** configurado para Docker (`sudo nvidia-ctk runtime configure --runtime=docker && sudo systemctl restart docker`).
- **Windows con Docker Desktop + WSL2 (notebook con RTX 4060):**
  - Tener instalado el driver NVIDIA Game Ready/Studio reciente en Windows (no hace falta instalar drivers dentro de WSL2) y usar el backend **WSL 2** en Docker Desktop.

---

## Inicio y detención rápidos (scripts Windows y Linux)

Tenés scripts listos para levantar y apagar todo el stack leyendo los parámetros desde [.env](.env) (si no existe, se crea automáticamente desde [.env.example](.env.example)):

### Windows
- **Iniciar (o doble clic desde el Explorador):**
  ```bat
  start.bat
  ```
- **Detener y liberar VRAM de la GPU:**
  ```bat
  stop.bat
  ```

### Linux
1. Dales permiso de ejecución una única vez:
   ```bash
   chmod +x start.sh stop.sh
   ```
2. Usalos igual que en Windows:
   ```bash
   ./start.sh
   ./stop.sh
   ```

### Opciones útiles en ambos sistemas
- **Elegir perfil sin editar `.env`:** pasá `watcher` / `watcher-4060` (por defecto), `watcher-3090`, `4060` o `3090`, por ejemplo:
  - `start.bat watcher-3090` / `./start.sh watcher-3090`
  - `stop.bat watcher-3090` / `./stop.sh watcher-3090`
  - `start.bat 3090` / `./start.sh 3090` (solo WebUI)
- **Forzar recompilación de la imagen:** `start.bat --build` / `./start.sh --build` (si `mineru:4-vllm` no existe todavía, compila automáticamente; si ya existe, arranca directo sin reconstruir).
- **Solo pausar contenedores sin eliminarlos (`stop` en lugar de `down`):** `stop.bat --keep` / `./stop.sh --keep`.
- **Ver el comando sin ejecutarlo:** `start.bat --dry-run` / `./start.sh --dry-run`.

---

## Despliegue en Arcane paso a paso

1. Abrí **Arcane** → **Projects** → **New Project**.
2. Asigná un nombre al proyecto (por ejemplo `mineru-ocr`).
3. Pegá el contenido completo de:
   - [compose.rtx3090-24gb.yaml](compose.rtx3090-24gb.yaml) en la PC con RTX 3090 (solo WebUI),
   - [compose.rtx4060-8gb.yaml](compose.rtx4060-8gb.yaml) en la notebook con RTX 4060 (solo WebUI),
   - [compose.watcher-rtx3090-24gb.yaml](compose.watcher-rtx3090-24gb.yaml) en la PC con RTX 3090 (**WebUI + carpeta vigilada**), o
   - [compose.watcher-rtx4060-8gb.yaml](compose.watcher-rtx4060-8gb.yaml) en la notebook con RTX 4060 (**WebUI + carpeta vigilada**).
4. Si necesitás cambiar la base a `cu129` o ajustar `device_ids` (en caso de tener múltiples GPUs NVIDIA, consultá `nvidia-smi -L`), editalo ahí mismo.
5. Hacé clic en **Build & Deploy** y esperá a que finalice la construcción y el contenedor `mineru-webui` (y `mineru-vlm` en la configuración de 8 GB) quede en estado **Healthy**.
6. Abrí en tu navegador `http://<IP-DEL-EQUIPO>:7860`.

### Selección de GPU (`device_ids` y `CUDA_VISIBLE_DEVICES`)
- `device_ids: ["0"]` en `deploy.resources.reservations.devices` asigna la primera GPU NVIDIA (`nvidia-smi -L`) al contenedor.
- Si tu servidor tiene varias GPUs NVIDIA y querés asignarle otra (por ejemplo la segunda), cambiá `device_ids: ["0"]` por `device_ids: ["1"]`, o exponé varias con `device_ids: ["0", "1"]`.
- Si exponés varias GPUs al contenedor y querés restringir cuál ve MinerU en runtime, podés agregar `CUDA_VISIBLE_DEVICES: "0"` en la sección `environment:`.

---

## Modo Watcher (procesamiento automático en lote + WebUI activa)

Tanto [compose.watcher-rtx4060-8gb.yaml](compose.watcher-rtx4060-8gb.yaml) (8 GB VRAM) como [compose.watcher-rtx3090-24gb.yaml](compose.watcher-rtx3090-24gb.yaml) (24 GB VRAM) mantienen la WebUI de 1 archivo en `http://localhost:7860`, enviando tanto los archivos de la interfaz como los del lote (`mineru-watcher`) a una única cola compartida en `mineru-api` (puerto `8000`) respaldada por `mineru-vlm`.

### Directorios configurables
Podés definir las rutas en el `.env` de Arcane (o cambiar directamente los valores por defecto en `volumes:`):
- `MINERU_INPUT_DIR` (por defecto `./libros/entrada`): carpeta vigilada donde dejás los PDFs/imágenes a convertir.
- `MINERU_OUTPUT_DIR` (por defecto `./libros/salida`): crea una subcarpeta por libro (`markdown.md`, `middle_json.json`, `structured_content.json` e `images/`).
- `MINERU_PROCESSED_DIR` (por defecto `./libros/procesados`): mueve acá cada archivo original cuando termina bien.
- `MINERU_FAILED_DIR` (por defecto `./libros/fallidos`): mueve acá los archivos que fallen para no trabar la cola.

### Opciones del watcher y reporte de errores
En `mineru-watcher` → `environment:` (o vía `.env`) podés ajustar:
- `WATCH_ERROR_REPORT` (por defecto `/data/salida/errores.md`): documento Markdown donde se registra fecha/hora, intentos, nombre de archivo, error y traza de cada archivo fallido.
- `WATCH_TIER`: `flash`, `basic` o `standard` (o `advanced` en la RTX 3090).
- `WATCH_OCR_MODE`: `ocr` (recomendado para libros escaneados), `auto` o `txt`.
- `WATCH_EXTENSIONS`: extensiones vigiladas (`.pdf,.png,.jpg,.jpeg,.webp,.tif,.tiff`).
- `WATCH_POLL_INTERVAL` / `WATCH_STABLE_SECONDS`: frecuencia de sondeo y espera hasta que el archivo termine de copiarse.
- `WATCH_MAX_RETRIES` / `WATCH_RETRY_DELAY` (`3` intentos / `15` s por defecto): espera automática a `/v1/health` y reintentos ante reinicios o cortes momentáneos antes de mover el archivo a `_fallidos`.
- `MINERU_PROCESSING_WINDOW_SIZE` / `MINERU_VLM_MAX_CONCURRENCY` (`16` / `8` en 4060 8 GB y `32` / `16` en 3090 24 GB): limita picos de RAM/VRAM en libros grandes y evita saturar `mineru-vlm`.

Para ver el avance del lote en vivo:
```bash
docker logs -f mineru-watcher
```

---

## Consejos para libros escaneados en la WebUI

1. **Activá `Force OCR`:** Para libros escaneados (especialmente PDFs antiguos que a veces traen una capa de texto oculta defectuosa), activá **Force OCR** antes de presionar **Convert** para forzar el reconocimiento completo de página.
2. **Probá primero con un rango de páginas:** Al subir el PDF, arrastrá el selector de rango (por ejemplo páginas `1` a `10`) para validar calidad y velocidad antes de procesar un libro de 300+ páginas.
3. **Elección de tier:**
   - **RTX 3090:** Usá `standard` para el mejor balance velocidad/calidad o `advanced` en páginas con tablas densas, fórmulas matemáticas o tipografía compleja.
   - **RTX 4060 (8 GB):** Empezá con `standard` (usa `mineru-vlm` con vLLM en CUDA limitado al `65%` de VRAM y `--enforce-eager`); si el libro es puro texto simple o querés procesar mucho más rápido, seleccioná `basic` en la WebUI.
4. **Formato de descarga recomendado:** Elegí **Markdown (ZIP)** para obtener el archivo `.md` junto con la carpeta `images/` de figuras/tablas extraídas listas para leer offline, o **EPUB / LaTeX** según tu flujo.

---

## Solución de problemas frecuentes

- **Error de versión de driver / CUDA al iniciar el contenedor:**
  Verificá `nvidia-smi`. Si tu CUDA Version es `12.x`, cambiá la imagen base dentro de `dockerfile_inline` a `vllm/vllm-openai:v0.21.0-cu129` y volvé a hacer **Build & Deploy**.
- **Error `could not select device driver "nvidia"`:**
  En Linux falta instalar/configurar `nvidia-container-toolkit` o reiniciar el daemon de Docker.
- **Falta de memoria (OOM) en la laptop de 8 GB:**
  Cerrá apps pesadas que consuman VRAM en Windows, ajustá `--gpu-memory-utilization` en `mineru-vlm` dentro de `compose.rtx4060-8gb.yaml` (rango recomendado en 8 GB: `0.60` a `0.70`, manteniendo `--enforce-eager`), o seleccioná el tier `basic` en la WebUI (no usa el VLM).
- **Cómo ver el uso real de GPU en Windows:**
  El Administrador de tareas de Windows muestra por defecto *3D*, *Copy*, *Video Encode* y *Video Decode*, que no reflejan cargas CUDA. Hacé clic en la flecha de cualquiera de esos gráficos (por ejemplo `Copy`) y elegí **`Cuda`**, o ejecutá `nvidia-smi` en una terminal.
- **Ver logs en vivo:**
  Desde Arcane en el contenedor `mineru-webui` → **Logs**, o por terminal con:
  ```bash
  docker logs -f mineru-webui
  ```
