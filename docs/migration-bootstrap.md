# Guía de Bootstrap CachyOS

Esta herramienta automatiza la configuración de un sistema CachyOS (basado en Arch Linux) optimizado para desarrollo y hardware Apple MacBook Pro (2015). El proceso se divide en bloques lógicos secuenciales para garantizar la estabilidad.

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
- **Docker:** Motor de contenedores y docker-compose.
- **Internet y Multimedia:** Firefox, LibreOffice (en español), FFmpeg, yt-dlp.

### 6. Aplicaciones KDE Plasma
Herramientas nativas del escritorio KDE:
- **Dolphin:** Gestor de archivos.
- **Spectacle:** Capturas de pantalla.
- **Ark:** Compresor/Descompresor.
- **Gwenview:** Visor de imágenes.

### 7. Paquetes de la Comunidad (AUR)
Software que no está en repositorios oficiales por licencias o naturaleza:
- **Navegadores y Editores:** Brave Browser, Visual Studio Code.
- **Redes y Utilidades:** Angry IP Scanner, Webapp-manager.
- **Tienda Visual:** Pamac (interfaz gráfica para instalar paquetes).

### 8. Herramientas de IA (CLI)
Instalación de interfaces de línea de comandos para asistentes de IA:
- **Codex:** `@openai/codex` vía npm.
- **Claude:** `claude` (nativo de Anthropic).
- **Gemini:** `@google/gemini-cli` vía npm.
- **OpenCode:** Integración con OpenCode CLI.

---
*Nota: Se recomienda reiniciar el sistema tras completar el bootstrap para asegurar que todos los cambios en el PATH y los grupos de usuario se apliquen correctamente.*
