# Guía de Bootstrap CachyOS

Esta herramienta automatiza la configuración de un sistema CachyOS (basado en Arch Linux) optimizado para desarrollo y hardware Apple MacBook Pro. El proceso se divide en bloques lógicos secuenciales para garantizar la estabilidad.

El bootstrap construye el checklist en runtime según el modelo Apple detectado
y oculta los bloques que no encajan con ese hardware. Eso permite ampliar la
compatibilidad sin mantener una lista fija de opciones para un solo MacBook.

## Bloques de Instalación

### 1. Sistema y Repositorios
- **Sincronización:** Actualiza las bases de datos de paquetes oficiales de CachyOS y Arch.
- **Actualización:** Aplica todas las actualizaciones pendientes del sistema (`pacman -Syyu`).

### 2. Infraestructura de Desarrollo
- **base-devel:** Grupo de herramientas esenciales para compilar software (gcc, make, etc.).
- **git:** Sistema de control de versiones necesario para descargar scripts de AUR y otros recursos.

### 3. AUR Helper (yay)
- **Instalación:** Descarga y compila `yay` desde el repositorio de la comunidad (AUR).
- **Dependencia Go:** Instala temporalmente el lenguaje `go`, necesario únicamente para compilar `yay`.

### 4. Flatpak
- **Motor:** Instala el soporte para aplicaciones universales Flatpak.
- **Integración:** Añade `flatpak-kcm` para gestionar aplicaciones desde los Ajustes del Sistema de KDE.
- **Flathub:** Configura el repositorio principal de Flathub.

### 5. Paquetes Oficiales (Repositorio)
Incluye herramientas de alta confianza probadas por CachyOS/Arch:
- **Terminal:** zsh, tmux, neovim, kitty, btop, fastfetch.
- **Utilidades:** jq, yq, ripgrep, curl, wget, zip/unzip.
- **AppImages:** bloque opcional que instala `fuse2` para compatibilidad con AppImages clásicas y `webkit2gtk-4.1` para las que dependen de WebKitGTK.
- **Docker:** Motor de contenedores y docker-compose.
- **Internet y Multimedia:** Firefox, LibreOffice (en español) + Java 21, FFmpeg, yt-dlp.
- **Aplicaciones extra seleccionables:** Restic, FileZilla, MarkdownPart, LibreOffice ES + Java 21, Android Studio + JDK 21 y Obsidian como bloques opcionales.
- **CLI de forja opcional:** `tea` como cliente de línea de comandos para Gitea desde repositorio oficial.
- **Utilidades SSH opcionales:** `sshpass` como bloque opcional desde repositorio oficial.

### 6. Aplicaciones KDE Plasma
Herramientas nativas del escritorio KDE:
- **Dolphin:** Gestor de archivos.
- **Spectacle:** Capturas de pantalla.
- **Ark:** Compresor/Descompresor.
- **Gwenview:** Visor de imágenes.
- **Kate:** editor para documentación y texto.

### 7. Paquetes de la Comunidad (AUR)
Software que no está en repositorios oficiales por licencias o naturaleza:
- **Navegadores y Editores:** Brave Browser, Visual Studio Code.
- **Redes y Utilidades:** Webapp-manager.
- **Tienda Visual:** Pamac (interfaz gráfica para instalar paquetes).
- **Apps propias y extras:** `talk2ai` como bloque opcional descargado desde GitHub, instalando `handy-bin` como dependencia; `codexBar Tray` como bloque opcional desde repo local detectado/restaurado; Angry IP Scanner como bloque opcional independiente; `tea` como CLI opcional para Gitea.
- **Android Studio:** bloque opcional que instala `android-studio` desde AUR junto con `jdk21-openjdk` desde repositorio oficial.

### 8. Herramientas de IA (CLI)
Instalación de interfaces de línea de comandos para asistentes de IA:
- **Codex:** `@openai/codex` vía npm.
- **Engram:** `engram` vía `go install`, con `engram setup codex` para registrar MCP e instrucciones de memoria.
- **Claude:** `claude` (nativo de Anthropic).
- **Gemini:** `@google/gemini-cli` vía npm.
- **OpenCode:** Integración con OpenCode CLI.

## Perfiles de hardware contemplados

- `MacBookPro12,1` - MacBook Pro Retina 13" 2015
- `MacBookPro8,1` - MacBook Pro 13" Early 2011

La corrección VA-API se adapta al perfil detectado:

- `MacBookPro12,1` - Intel Broadwell / `libva-intel-driver-irql`
- `MacBookPro8,1` - Intel Sandy Bridge / `libva-intel-driver`

## Preflight y tests

La versión inicial también expone un modo de comprobación para validar el
perfil y el catálogo sin tocar el sistema:

```bash
./migration.sh test profiles
./migration.sh test catalog
./migration.sh test syntax
./migration.sh test
```

Uso recomendado:

- `profiles` para confirmar que el MacBook cae en el perfil correcto
- `catalog` para ver qué bloques se mostrarán en la TUI
- `syntax` para validar el árbol Bash antes de un cambio
- `all` para ejecutar todo junto en una pasada

---
*Nota: Se recomienda reiniciar el sistema tras completar el bootstrap para asegurar que todos los cambios en el PATH y los grupos de usuario se apliquen correctamente.*
