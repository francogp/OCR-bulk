@echo off
setlocal EnableExtensions EnableDelayedExpansion
chcp 65001 >nul
cd /d "%~dp0"

set "EXIT_CODE=0"
set "HAS_ARGS=0"
if not "%~1"=="" set "HAS_ARGS=1"
set "DRY_RUN=0"
set "KEEP_CONTAINERS=0"
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
) else if /i "!ARG!"=="--keep" (
    set "KEEP_CONTAINERS=1"
) else if /i "!ARG!"=="--no-pause" (
    set "NO_PAUSE=1"
) else if /i "!ARG!"=="watcher" (
    set "ARG_COMPOSE=compose.watcher-rtx4060-8gb.yaml"
) else if /i "!ARG!"=="watcher-4060" (
    set "ARG_COMPOSE=compose.watcher-rtx4060-8gb.yaml"
) else if /i "!ARG!"=="watcher-3090" (
    set "ARG_COMPOSE=compose.watcher-rtx3090-24gb.yaml"
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

if not defined MINERU_COMPOSE_FILE set "MINERU_COMPOSE_FILE=compose.watcher-rtx4060-8gb.yaml"
set "COMPOSE_FILE=!MINERU_COMPOSE_FILE!"
if defined ARG_COMPOSE set "COMPOSE_FILE=!ARG_COMPOSE!"

if not exist "!COMPOSE_FILE!" (
    echo [ERROR] No se encontro el archivo Compose: !COMPOSE_FILE!
    set "EXIT_CODE=1"
    goto finish
)

set "ACTION=down --remove-orphans"
if "!KEEP_CONTAINERS!"=="1" set "ACTION=stop"

if "!DRY_RUN!"=="1" (
    echo [DRY-RUN] Compose: !COMPOSE_FILE!
    echo [DRY-RUN] Comando: docker compose -f "!COMPOSE_FILE!" !ACTION!
    goto finish
)

docker info >nul 2>&1
if errorlevel 1 (
    echo [ERROR] Docker Desktop no esta corriendo o no responde.
    set "EXIT_CODE=1"
    goto finish
)

echo [INFO] Deteniendo stack !COMPOSE_FILE!...
docker compose -f "!COMPOSE_FILE!" !ACTION!
if errorlevel 1 (
    echo [ERROR] No se pudo detener el stack correctamente.
    set "EXIT_CODE=1"
    goto finish
)

echo.
if "!KEEP_CONTAINERS!"=="1" (
    echo [OK] Contenedores detenidos ^(preservados^). Se libero la VRAM de la GPU.
) else (
    echo [OK] Stack detenido y contenedores removidos. Se libero la VRAM de la GPU.
    echo [OK] La imagen mineru:4-vllm y tus archivos se conservan intactos.
)
goto finish

:show_help
echo Uso: stop.bat [watcher^|watcher-4060^|watcher-3090^|4060^|3090^|archivo.yaml] [--keep] [--dry-run] [--no-pause] [-h^|--help]
echo.
echo Opciones:
echo   --keep      Solo detiene los contenedores ^(stop^) sin removerlos ^(por defecto usa down^)
echo   --dry-run   Muestra el comando sin ejecutar Docker
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
