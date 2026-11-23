@echo off
setlocal EnableExtensions EnableDelayedExpansion
chcp 65001 >nul
cd /d "%~dp0"

set "EXIT_CODE=0"
set "HAS_ARGS=0"
if not "%~1"=="" set "HAS_ARGS=1"
set "DRY_RUN=0"
set "FORCE_BUILD=0"
set "NO_PAUSE=0"
set "ARG_COMPOSE="

:parse_args
if "%~1"=="" goto after_args
set "ARG=%~1"
if /i "!ARG!"=="-h" goto show_help
if /i "!ARG!"=="--help" goto show_help
if /i "!ARG!"=="/?" goto show_help
if /i "!ARG!"=="--dry-run" (
    set "DRY_RUN=1"
) else if /i "!ARG!"=="--build" (
    set "FORCE_BUILD=1"
) else if /i "!ARG!"=="--no-pause" (
    set "NO_PAUSE=1"
) else if /i "!ARG!"=="watcher" (
    set "ARG_COMPOSE=compose.watcher-rtx4060-8gb.yaml"
) else if /i "!ARG!"=="4060" (
    set "ARG_COMPOSE=compose.rtx4060-8gb.yaml"
) else if /i "!ARG!"=="3090" (
    set "ARG_COMPOSE=compose.rtx3090-24gb.yaml"
) else if "!ARG:~0,1!"=="-" (
    echo [ERROR] Opcion desconocida: !ARG!
    echo Usa --help para ver las opciones disponibles.
    set "EXIT_CODE=1"
    goto finish
) else (
    set "ARG_COMPOSE=!ARG!"
)
shift
goto parse_args

:after_args
if not exist ".env" (
    if exist ".env.example" (
        copy /y ".env.example" ".env" >nul
        echo [INFO] No existia .env; se creo a partir de .env.example.
    )
)

if exist ".env" (
    for /f "usebackq tokens=* delims=" %%L in (".env") do (
        set "LINE=%%L"
        if not "!LINE!"=="" (
            if not "!LINE:~0,1!"=="#" (
                for /f "tokens=1* delims==" %%A in ("!LINE!") do (
                    set "K=%%~A"
                    set "V=%%~B"
                    for /f "tokens=*" %%K in ("!K!") do set "K=%%K"
                    if not "!K!"=="" set "!K!=!V!"
                )
            )
        )
    )
)

if not defined MINERU_WEBUI_PORT set "MINERU_WEBUI_PORT=7860"
if not defined MINERU_API_PORT set "MINERU_API_PORT=8000"
if not defined MINERU_COMPOSE_FILE set "MINERU_COMPOSE_FILE=compose.watcher-rtx4060-8gb.yaml"

set "COMPOSE_FILE=!MINERU_COMPOSE_FILE!"
if defined ARG_COMPOSE set "COMPOSE_FILE=!ARG_COMPOSE!"

if not exist "!COMPOSE_FILE!" (
    echo [ERROR] No se encontro el archivo Compose: !COMPOSE_FILE!
    set "EXIT_CODE=1"
    goto finish
)

if /i "!COMPOSE_FILE!"=="compose.watcher-rtx4060-8gb.yaml" (
    if not defined MINERU_INPUT_DIR set "MINERU_INPUT_DIR=.\libros\entrada"
    if not defined MINERU_OUTPUT_DIR set "MINERU_OUTPUT_DIR=.\libros\salida"
    if not defined MINERU_PROCESSED_DIR set "MINERU_PROCESSED_DIR=.\libros\procesados"
    if not defined MINERU_FAILED_DIR set "MINERU_FAILED_DIR=.\libros\fallidos"
)

call :ensure_dir "!MINERU_INPUT_DIR!"
call :ensure_dir "!MINERU_OUTPUT_DIR!"
call :ensure_dir "!MINERU_PROCESSED_DIR!"
call :ensure_dir "!MINERU_FAILED_DIR!"

set "DOCKER_OK=1"
docker info >nul 2>&1
if errorlevel 1 set "DOCKER_OK=0"

if "!DOCKER_OK!"=="0" (
    if "!DRY_RUN!"=="1" (
        echo [AVISO] Docker Desktop no esta corriendo en este momento.
    ) else (
        echo [ERROR] Docker Desktop no esta corriendo o no responde. Abrilo y volve a intentar.
        set "EXIT_CODE=1"
        goto finish
    )
)

set "BUILD_FLAG="
if "!FORCE_BUILD!"=="1" (
    set "BUILD_FLAG=--build"
) else if "!DOCKER_OK!"=="1" (
    docker image inspect mineru:4-vllm >nul 2>&1
    if errorlevel 1 set "BUILD_FLAG=--build"
)

if "!DRY_RUN!"=="1" (
    echo [DRY-RUN] Compose: !COMPOSE_FILE!
    if /i "!COMPOSE_FILE!"=="compose.watcher-rtx4060-8gb.yaml" (
        if defined MINERU_INPUT_DIR echo [DRY-RUN] Entrada: !MINERU_INPUT_DIR!
        if defined MINERU_OUTPUT_DIR echo [DRY-RUN] Salida:  !MINERU_OUTPUT_DIR!
    )
    if defined BUILD_FLAG (
        echo [DRY-RUN] Comando: docker compose -f "!COMPOSE_FILE!" up -d !BUILD_FLAG!
    ) else (
        echo [DRY-RUN] Comando: docker compose -f "!COMPOSE_FILE!" up -d
    )
    goto finish
)

if defined BUILD_FLAG (
    echo [INFO] Compilando imagen mineru:4-vllm y levantando !COMPOSE_FILE!...
) else (
    echo [INFO] Levantando !COMPOSE_FILE! ^(reutilizando imagen local sin recompilar^)...
)

docker compose -f "!COMPOSE_FILE!" up -d !BUILD_FLAG!
if errorlevel 1 (
    echo [ERROR] Fallo al iniciar el stack. Revisa logs con: docker compose -f "!COMPOSE_FILE!" logs --tail 50
    set "EXIT_CODE=1"
    goto finish
)

echo.
docker compose -f "!COMPOSE_FILE!" ps
echo.
echo [OK] WebUI disponible en: http://localhost:!MINERU_WEBUI_PORT!
if /i "!COMPOSE_FILE!"=="compose.watcher-rtx4060-8gb.yaml" (
    echo [OK] API OpenAPI docs:    http://localhost:!MINERU_API_PORT!/docs
    echo [OK] Carpeta entrada:     !MINERU_INPUT_DIR!
    echo [OK] Carpeta salida:      !MINERU_OUTPUT_DIR!
    echo [OK] Logs del watcher:    docker logs -f mineru-watcher
)
goto finish

:ensure_dir
if "%~1"=="" goto :eof
set "WIN_DIR=%~1"
set "WIN_DIR=!WIN_DIR:/=\!"
if "!DRY_RUN!"=="0" (
    if not exist "!WIN_DIR!" mkdir "!WIN_DIR!" >nul 2>&1
)
goto :eof

:show_help
echo Uso: start.bat [watcher^|4060^|3090^|archivo.yaml] [--build] [--dry-run] [--no-pause] [-h^|--help]
echo.
echo Perfiles disponibles:
echo   watcher   WebUI + Watcher automatico + API (compose.watcher-rtx4060-8gb.yaml)
echo   4060      Solo WebUI para RTX 4060 8 GB    (compose.rtx4060-8gb.yaml)
echo   3090      Solo WebUI para RTX 3090 24 GB   (compose.rtx3090-24gb.yaml)
echo.
echo Opciones:
echo   --build     Fuerza la recompilacion de la imagen Docker
echo   --dry-run   Muestra las rutas y el comando sin ejecutar Docker
echo   --no-pause  No pausa al finalizar si se ejecuta sin argumentos
echo   -h, --help  Muestra esta ayuda
echo.
echo Sin perfil indicado, lee MINERU_COMPOSE_FILE de .env ^(por defecto watcher^).
goto finish

:finish
if "!NO_PAUSE!"=="0" if "!HAS_ARGS!"=="0" (
    echo !cmdcmdline! | find /i "/c" >nul
    if not errorlevel 1 (
        echo !cmdcmdline! | find /i "%~nx0" >nul
        if not errorlevel 1 (
            echo.
            pause
        )
    )
)
exit /b !EXIT_CODE!
