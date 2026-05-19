# Linux Migration Tool

## Objetivo

Script orientado a migración y bootstrap de workstation Linux para desarrollo.

Pensado especialmente para:

- Linux Mint / Ubuntu → CachyOS / Arch
- Desarrollo Python / Web
- Workflows terminal-heavy
- IA tooling (Codex, Claude CLI)
- Entornos multi-dispositivo Linux
- Configuración moderna basada en:
  - KDE Plasma
  - Hyprland opcional
  - ZSH
  - Kitty
  - Docker
  - Syncthing

---

# Funcionalidades

El script principal:

```bash
migration.sh
```

incluye:

1. Backup del sistema de usuario
2. Restauración del backup
3. Bootstrap automatizado de CachyOS
4. Instalación de tooling dev moderno
5. Base estable sobre KDE Plasma
6. Instalación opcional de Hyprland
7. Extras opcionales para Apple MBP Intel

---

# Modelo de instalación

```text
CachyOS
└── KDE Plasma (base estable)
    └── Hyprland (opcional)
```

## Capas del bootstrap

### 1. Base común de desarrollo

- terminal/dev: `zsh`, `kitty`, `tmux`, `neovim`
- tooling: `git`, `ripgrep`, `fd`, `bat`, `eza`, `fzf`
- validación shell: `shellcheck`, `shfmt`
- runtimes: `python`, `python-pip`, `docker`, `docker-compose`
- utilidades: `github-cli`, `opencode`, `direnv`, `firefox`, `syncthing`
- desktop dev: `opencode-desktop-bin`

### 2. KDE Plasma base

- utilidades KDE: `dolphin`, `ark`, `gwenview`, `kate`
- soporte diario: `spectacle`, `kcalc`, `filelight`, `plasma-systemmonitor`

### 3. Hyprland opcional

- `hyprland`
- `waybar`
- `rofi-wayland`
- `hyprpaper`
- `grim`
- `slurp`
- `mako`

### 4. Apple MBP 2015 opcional

- `thermald`
- `powertop`

Pensado para ajuste térmico/energético en portátil Intel.
No instala drivers Broadcom propietarios por defecto.
Si el script detecta un MacBook por DMI, preguntará si deseas instalar estos extras.

El bootstrap ya no muestra este bloque como una lista fija para el MBP 2015:
construye el checklist según el modelo detectado y oculta bloques que no encajan
con ese hardware. Hoy están contemplados al menos:

- `MacBookPro12,1` - MacBook Pro Retina 13" 2015
- `MacBookPro8,1` - MacBook Pro 13" Early 2011

La acción de VA-API se adapta al modelo:

- `MacBookPro12,1` - Intel Broadwell / `libva-intel-driver-irql`
- `MacBookPro8,1` - Intel Sandy Bridge / `libva-intel-driver`

### 4.1 Tests y preflight inicial

Para esta primera versión también puedes ejecutar comprobaciones locales sin
lanzar el bootstrap completo:

```bash
./migration.sh test profiles   # perfil detectado, características y resumen
./migration.sh test catalog    # catálogo de bloques por hardware
./migration.sh test syntax     # bash -n sobre el árbol principal
./migration.sh test            # ejecuta todo lo anterior
```

Estos tests están pensados para:

- verificar que el modelo Apple detectado cae en el perfil esperado
- comprobar qué bloques de bootstrap se mostrarán antes de instalar nada
- servir como base para automatizar validaciones cuando añadas más modelos

### 5. Cámara FaceTime HD (MBP 2013+)

El MBP 2015 usa una cámara FaceTime HD conectada por **PCIe** (`14e4:1570`, Broadcom),
no por USB. Requiere el driver `facetimehd` en lugar de `uvcvideo`.

El bootstrap detecta automáticamente el dispositivo con `lspci` y pregunta si instalar:

- `facetimehd-dkms` — driver (AUR)
- `facetimehd-firmware` — firmware extraído de macOS (AUR)

Pasos que aplica si se confirma:

```bash
yay -S facetimehd-dkms facetimehd-firmware
# descarga bdc_pci si está cargado (en kernels modernos puede no existir)
sudo modprobe -r bdc_pci 2>/dev/null
sudo modprobe facetimehd
echo "facetimehd"       | sudo tee /etc/modules-load.d/facetimehd.conf
echo "blacklist bdc_pci" | sudo tee /etc/modprobe.d/facetimehd.conf
```

Si `/dev/video*` no aparece tras instalar el driver, instala el **kernel Zen** y reinicia:

```bash
sudo pacman -S linux-cachyos-zen linux-cachyos-zen-headers
# seleccionar linux-cachyos-zen en el bootloader al reiniciar
```

Verificar cámara:

```bash
ls /dev/video*
mpv /dev/video0          # previsualización directa
v4l2-ctl --list-devices  # info técnica (formatos, resoluciones)
```

## Checklist post-instalación MBP 2015

### Core

- verificar escalado y resolución Retina en KDE Plasma
- comprobar suspensión, reanudación y consumo en reposo
- validar Wi‑Fi en 2.4 GHz y 5 GHz
- revisar temperatura y ruido de ventiladores bajo carga
- confirmar audio, Bluetooth, cámara y brillo

### Observabilidad recomendada

- revisar `journalctl -b` tras un arranque normal
- revisar `journalctl -b -1` tras un fallo de suspensión/reanudación
- usar `powertop` para observar consumo y wakeups
- usar `systemd-analyze blame` si el arranque se siente lento
- registrar incidencias recurrentes antes de cambiar drivers o kernel

## Observación temporal en segundo plano

Para la primera etapa con CachyOS en el MBP puedes usar:

```bash
sudo /usr/local/bin/mbp_watch.sh status
sudo /usr/local/bin/mbp_watch.sh report
sudo /usr/local/bin/mbp_watch.sh inventory
sudo /usr/local/bin/mbp_watch.sh stop
sudo systemctl start mbp-watch.service
```

Qué hace:

- vigila `journalctl -f` buscando eventos de: Wi‑Fi (brcmfmac/iwlwifi), GPU/DRM (i915), suspensión/resume (PM), audio (snd_hda_intel), sensores Apple (applesmc), Thunderbolt, Bluetooth, NetworkManager y ACPI
- toma snapshots periódicos con: estado del sistema, memoria, temperatura/ventiladores, batería, audio, cámara, rfkill, unidades fallidas
- captura un inventario estático de hardware al arrancar: modelo Apple, kernel, GPU, chip Wi‑Fi, firmware Broadcom cargado, audio, cámara, puertos Thunderbolt
- **comprueba el estado de los drivers** al arrancar y cada 60 s: módulo cargado, dispositivo presente, errores en dmesg — 7 subsistemas (camera, wifi, bluetooth, gpu, audio, applesmc, thunderbolt)
- genera un informe HTML interactivo en `http://localhost:7070/report.html` con 7 tarjetas de métricas, historial diario y sección de inventario hardware
- sirve el informe vía HTTP embebido (`python3 -m http.server`, puerto 7070) para que fetch(), audio y favicon funcionen sin restricciones CORS
- genera un **AI digest** en `/var/lib/mbp-watch/report.txt` — formato clave:valor compacto, token-eficiente, listo para pegar en una IA
- acumula en `daily_errors.log` una línea por día con contadores por subsistema — nunca se trunca, ideal para análisis IA multi-día
- ejecuta el servicio supervisado por systemd y se reinicia si falla
- actualiza la página del informe cada 5 segundos mediante `fetch()` sin recargar la página completa (el `AudioContext` y el estado de los `<details>` se conservan)
- crea un lanzador clicable (`MBP-Watch-Report.desktop`) y un redirect HTML (`MBP-Watch-Report.html`) en la carpeta XDG Desktop

### Informe web (http://localhost:7070/report.html)

- 7 tarjetas de métricas con contadores de los últimos 200 eventos de journal
- banner de severidad: **Stable** / **Warnings Found** / **Critical Issues Detected**
- favicon SVG color-coded: verde (ok), amarillo (warn), rojo (critical)
- secciones expandibles (`<details>`): Error History, Hardware Inventory, **Driver Health**, Recent Matched Events, Last Snapshot
- estado abierto/cerrado de cada `<details>` persiste en `sessionStorage` entre ciclos de refresco
- botón 🔇/🔊 para activar alertas de audio — el clic crea el `AudioContext` (gesto de usuario requerido por el navegador); emite pitido de confirmación al activar, y alerta sonora cuando aumentan los contadores
- enlace directo a `report.txt` para descarga y análisis IA

### Sección Driver Health

Tabla en el informe web con el estado de cada driver del MBP:

| Driver | Qué comprueba |
|---|---|
| camera | `facetimehd` (PCIe `14e4:1570`) o `uvcvideo` (USB) + `/dev/video*` |
| wifi | `brcmfmac` en `/proc/modules` + interfaz activa + errores firmware en dmesg |
| bluetooth | `btusb` + dispositivo hci en `/sys/class/bluetooth/` |
| gpu | `i915` + `/dev/dri/card*` |
| audio | `snd_hda_intel` + tarjeta ALSA |
| applesmc | módulo + path sysfs de temperatura |
| thunderbolt | módulo + dispositivos en bus |

Cada fila muestra badge **✓ OK** / **⚠ WARN** / **✗ ERROR** con el detalle del problema y un campo `fix:` con el comando exacto para solucionarlo. El botón **⎘** copia el comando al portapapeles (muestra `¡Copiado!` 1.5 s).

Los checks se realizan leyendo `/proc/modules` directamente para evitar el problema de SIGPIPE que afecta a `lsmod | grep -q` con `set -o pipefail`.

El estado se refresca al arrancar el servicio y luego cada 60 s en el snapshot loop.

### Métricas monitorizadas

| Tarjeta | Subsistema vigilado | Umbral crítico |
|---|---|---|
| Wi‑Fi | brcmf, wpa_supplicant, iwlwifi, mt76, ath, rtl, rtw | ≥ 3 |
| Connectivity | NetworkManager, DHCP, activación de red | ≥ 3 |
| GPU/DRM | drm, gpu, i915 (Intel Iris) | ≥ 3 |
| Bluetooth | bluetoothd | ≥ 5 |
| Thermal/ACPI | thermal, acpi | ≥ 5 |
| Suspend/PM | PM: suspend/resume errors, s2idle | ≥ 2 |
| Audio/HW | snd_hda_intel, applesmc, thunderbolt | ≥ 3 |

### Usar el AI digest

El archivo `report.txt` está diseñado para ser pegado directamente en una IA. Incluye las secciones:

- `SEVERITY` — estado global y razón
- `COUNTERS` — contadores por subsistema (ventana de 200 eventos)
- `HARDWARE` — inventario estático (modelo, GPU, chip Wi‑Fi, firmware, audio, cámara)
- `SYSTEM` — último snapshot (temperatura, batería, estado de red, rfkill, unidades fallidas)
- `HISTORY` — historial diario completo desde `daily_errors.log` (nunca truncado)
- `ERRORS_DEDUPED` — hasta 20 líneas únicas de eventos recientes
- `RAW_LOGS` — rutas a los logs completos

```bash
# Ver el digest en terminal
sudo cat /var/lib/mbp-watch/report.txt

# Ver historial de errores por día
sudo cat /var/lib/mbp-watch/daily_errors.log

# Pasarlo a una IA: pegar el contenido de report.txt
# Flujo recomendado: dejar corriendo varios días → abrir report.html →
# si hay errores, pegar report.txt en la IA para análisis
```

## Instalación automática en bootstrap

Durante `Bootstrap CachyOS`, el script instala:

- `/usr/local/bin/mbp_watch.sh`
- `/usr/local/sbin/uninstall_mbp_watch.sh`
- `/etc/systemd/system/mbp-watch.service`
- `/etc/mbp-watch.conf`

Y activa el servicio con:

```bash
sudo systemctl enable --now mbp-watch.service
```

Ficheros generados:

| Ruta | Descripción |
|---|---|
| `/var/lib/mbp-watch/report.html` | Informe HTML interactivo (actualización fetch cada 5 s) |
| `/var/lib/mbp-watch/report.txt` | AI digest — texto compacto estructurado para pegar en una IA |
| `/var/lib/mbp-watch/inventory.log` | Inventario estático de hardware (capturado al arrancar) |
| `/var/lib/mbp-watch/daily_errors.log` | Historial de errores por día — nunca truncado, para análisis multi-día |
| `/var/lib/mbp-watch/events.log` | Eventos de journal filtrados (últimas 10 000 líneas) |
| `/var/lib/mbp-watch/snapshots.log` | Snapshots periódicos del sistema (últimas 500 líneas) |
| `/var/lib/mbp-watch/status.log` | Log interno del servicio (últimas 2 000 líneas) |
| `$XDG_DESKTOP_DIR/MBP-Watch-Report.desktop` | Lanzador clicable en el escritorio → `http://localhost:7070/report.html` |

### Comandos de uso

```bash
# Ver estado del servicio (muestra URL, PIDs y rutas)
sudo /usr/local/bin/mbp_watch.sh status

# Comprobar drivers ahora mismo (muestra OK/WARN/ERROR + fix en terminal)
sudo /usr/local/bin/mbp_watch.sh drivers

# Forzar un snapshot manual inmediato
sudo /usr/local/bin/mbp_watch.sh snapshot

# (Re)capturar inventario de hardware y mostrarlo
sudo /usr/local/bin/mbp_watch.sh inventory

# Regenerar informe HTML y AI digest manualmente
sudo /usr/local/bin/mbp_watch.sh report

# Ver el AI digest en terminal
sudo cat /var/lib/mbp-watch/report.txt

# Ver historial diario de errores
sudo cat /var/lib/mbp-watch/daily_errors.log

# Parar el servicio
sudo systemctl stop mbp-watch.service

# Arrancar el servicio
sudo systemctl start mbp-watch.service

# Abrir el informe web
xdg-open http://localhost:7070/report.html
```

### Actualizar el script sin reinstalar el bootstrap

Usar el script de despliegue incluido (para, copia, reinicia y valida en un paso):

```bash
bash assets/diagnostics/deploy_mbp_watch.sh
```

Para limpiar de forma segura el histórico anterior y relanzar desde cero:

```bash
bash assets/diagnostics/deploy_mbp_watch.sh --clean
```

El script `deploy_mbp_watch.sh`:
1. Se re-ejecuta con `sudo` si no es root
2. Valida la sintaxis con `bash -n` antes de tocar nada
3. Para el servicio, copia el script a `/usr/local/bin/mbp_watch.sh` y lo arranca
4. Con `--clean`, archiva el estado anterior en una copia con marca temporal antes de arrancar
5. Espera 2 s y muestra el estado final

Desinstalación:

```bash
# Desde migration.sh (recomendado — integra dry-run y el flujo de confirmación)
./migration.sh uninstall-mbp-watch
./migration.sh uninstall-mbp-watch --dry-run
./migration.sh add-mbp-plasmoid
./migration.sh add-mbp-plasmoid --dry-run
./migration.sh move-mbp-plasmoid --target primary
./migration.sh move-mbp-plasmoid --target screen:1
./migration.sh move-mbp-plasmoid --target screen:2 --dry-run
./migration.sh uninstall-mbp-plasmoid
./migration.sh uninstall-mbp-plasmoid --dry-run
./migration.sh reinstall-mbp-plasmoid
./migration.sh reinstall-mbp-plasmoid --dry-run

# Standalone como root (equivalente al script instalado en /usr/local/sbin)
sudo /usr/local/sbin/uninstall_mbp_watch.sh           # conserva /var/lib/mbp-watch
sudo /usr/local/sbin/uninstall_mbp_watch.sh --purge   # elimina también los logs y reportes

# Standalone del plasmoid KDE desde el repo
bash assets/diagnostics/uninstall_mbp_plasmoid.sh
bash assets/diagnostics/uninstall_mbp_plasmoid.sh --dry-run
bash assets/diagnostics/move_mbp_plasmoid.sh --target primary
bash assets/diagnostics/move_mbp_plasmoid.sh --target screen:1
bash assets/diagnostics/move_mbp_plasmoid.sh --target screen:2 --dry-run
bash assets/diagnostics/reinstall_mbp_plasmoid.sh
bash assets/diagnostics/reinstall_mbp_plasmoid.sh --dry-run
```

Qué elimina el desinstalador:

- Servicio systemd (`mbp-watch.service`): parado, deshabilitado y eliminado
- `/usr/local/bin/mbp_watch.sh`
- `/usr/local/sbin/uninstall_mbp_watch.sh` (se auto-elimina)
- `/etc/mbp-watch.conf`
- `/etc/systemd/system/mbp-watch.service`
- `$XDG_DESKTOP_DIR/MBP-Watch-Report.desktop`

Con `--purge` (o eligiendo "sí" al confirmar desde el menú):

- `/var/lib/mbp-watch/` (logs, reportes, inventario, historial diario)

El desinstalador del plasmoid KDE:

- intenta quitar instancias activas del escritorio con `qdbus6`
- elimina el paquete de usuario con `kpackagetool6 --type Plasma/Applet --remove io.github.cachyosmigrationtool.mbpwatch`
- no edita directamente archivos internos de configuración de Plasma

El reinstalador del plasmoid KDE:

- ejecuta primero la desinstalación del plasmoid actual
- reinstala el paquete de usuario desde `assets/plasmoids/mbp-watch`
- reintenta el auto-add del widget al escritorio usando `qdbus6`
- no reinicia `plasmashell`, para no romper la barra o el shell de Plasma

El comando de movimiento del plasmoid KDE:

- elimina la instancia activa del plasmoid del escritorio
- la recrea en el target pedido con `qdbus6`
- soporta `--target primary` y `--target screen:N`
- sirve para recolocar el widget sin desinstalar ni reinstalar el paquete

Úsalo durante los primeros días de uso real y desactívalo cuando confirmes que:

- suspensión y reanudación son estables
- Wi‑Fi reconecta sin errores
- no aparecen errores repetidos en kernel/journal

---

# Menú principal

Al ejecutarse:

```bash
./migration.sh
```

muestra:

```text
1) Backup sistema
2) Bootstrap CachyOS
3) Post-check tras reinicio
4) Restaurar backup
5) Desinstalar MBP Watch
6) Desinstalar plasmoid MBP Watch
7) Reinstalar plasmoid MBP Watch
8) Mover plasmoid MBP Watch
9) Instalar YouTube Force H264
10) Salir
```

---

# 1. BACKUP DEL SISTEMA

## Objetivo

Crear backup selectivo y portable entre distribuciones Linux.

Evita copiar:
- basura histórica
- caches
- configuraciones problemáticas
- entornos virtuales Python

---

## Selección de disco

El script:

- detecta discos montados
- muestra:
  - tamaño
  - filesystem
  - etiqueta
  - punto de montaje
  - tipo de conexión

Ejemplo:

```text
[1]
 Device : /dev/sdb1
 Size   : 931G
 FS     : ext4
 Label  : BACKUP
 Mount  : /media/<user>/BACKUP
 Type   : usb
```

---

# Estructura del backup

```text
linux_backup_DATE/
├── configs/
├── repos/
├── data/
├── metadata/
└── logs/
```

Dentro de `repos/`, los proyectos se guardan manteniendo su ruta relativa desde `~`. Ejemplo:

```text
repos/Documentos/GITEA/mi_repo
repos/Documentos/GITHUB/otro_repo
repos/Documentos/Prog_Local/proyecto_local
```

---

# Configuraciones exportadas

## SSH

```text
~/.ssh
```

Incluye:
- claves
- config
- known_hosts

---

## Git

```text
~/.gitconfig
```

---

## Shell

```text
~/.bashrc
~/.zshrc
~/.profile
```

---

## IA / Orchestration

```text
~/.claude
~/.claude.json
~/.codex
~/.neocoding
```

---

## VSCode

```text
~/.config/Code
~/.vscode
```

---

## Scripts

```text
$HOME/Scripts
```

No se copia por defecto. Si lo quieres incluir, añádelo en:

```text
~/.config/linux-migration-tool.conf
```

---

# Repositorios Git

El script busca automáticamente:

```text
$XDG_DOCUMENTS_DIR/GITEA
$XDG_DOCUMENTS_DIR/GITHUB
$XDG_DOCUMENTS_DIR/Prog_Local
```

y si esas rutas no existen, contempla `~/Documents` o `~/Documentos` como fallback.
Después detecta carpetas `.git`.

Directorios extra como `~/Apps_Testing` se configuran en:

```text
~/.config/linux-migration-tool.conf
```

Ejemplo base disponible en:

```text
linux-migration-tool.conf.example
```

---

# Datos de usuario

Además de repos y configuraciones, el script archiva por defecto:

```text
$XDG_DOCUMENTS_DIR
```

Ese contenido se guarda en:

```text
data/
```

Los subdirectorios configurados como raíces de repositorio se excluyen de esta
copia para evitar duplicar los repos ya respaldados en `repos/`.

---

# Exclusiones automáticas

NO se copian:

```text
venv
.venv
__pycache__
.cache
```

---

# Metadata exportada

## UID/GID

```text
metadata/user_ids.conf
```

Guarda:

```text
USER=
UID=
GID=
```

---

## Paquetes del sistema

```text
dpkg_packages.txt
```

---

## Flatpaks

```text
flatpak_packages.txt
```

---

## Extensiones VSCode

```text
vscode_extensions.txt
```

---

# 2. RESTORE DEL SISTEMA

## Objetivo

Restaurar backup en nueva instalación Linux.

Especialmente:
- CachyOS
- Arch
- KDE Plasma

---

# Funciones del restore

## Restaurar configuraciones

Restaura:
- SSH
- Codex
- Claude
- VSCode
- scripts
- zsh

---

## Restaurar repositorios

Los repos se restauran en su ubicación original relativa a `~`. Ejemplo:

```text
~/Documentos/GITEA/mi_repo
~/Documentos/GITHUB/otro_repo
~/Documentos/Prog_Local/proyecto_local
```

## Restaurar datos de usuario

Si existe `data/`, el script restaura también:

- `$XDG_DOCUMENTS_DIR`
- cualquier ruta adicional definida en `DATA_DIRS`

---

## Adaptación UID/GID

El script:

- compara UID/GID antiguos y actuales
- corrige ownership automáticamente

Usa:

```bash
chown -R
```

---

## Corrección permisos SSH

Aplica automáticamente:

```bash
chmod 700 ~/.ssh
find ~/.ssh -type f \( -name 'id_*' -o -name 'authorized_keys' -o -name 'known_hosts' -o -name 'config' \) -exec chmod 600 {} +
find ~/.ssh -type f -name '*.pub' -exec chmod 644 {} +
```

---

# 3. BOOTSTRAP CACHYOS

## Objetivo

Convertir instalación limpia CachyOS en workstation moderna de desarrollo.

---

# Paquetes instalados

## Base dev

```text
git
base-devel
curl
wget
unzip
zip
jq
yq
ripgrep
fd
bat
eza
btop
fastfetch
fzf
tree
neovim
github-cli
shellcheck
shfmt
direnv
nmap
wireshark-qt
mtr
bind
inetutils
firefox
syncthing
kdeconnect
solaar
piper
libratbag
wl-clipboard
noto-fonts
noto-fonts-emoji
```

---

# Terminal / Shell

## Terminal

```text
kitty
```

### Motivos

- excelente en Wayland
- muy rápido
- GPU accelerated
- ideal para Hyprland
- ideal para desarrollo

---

## Shell

```text
zsh
oh-my-zsh
powerlevel10k
```

---

## Multiplexor

```text
tmux
```

---

# Fuentes instaladas

```text
JetBrainsMono Nerd Font
Noto Fonts
Noto Emoji
```

---

# Python

```text
python
python-pip
```

---

# Node / JS

## Instalado mediante

```text
nvm
```

Luego:
- Node LTS
- npm
- pnpm
- bun

---

# IA Tooling

## Codex CLI

Instalación:

```bash
npm install -g @openai/codex
```

---

# Ajustes post-instalacion opcionales

Durante `Bootstrap CachyOS` el script ahora puede ofrecer tambien:

- Detectar `Broadcom BCM43602` en equipos Apple y aplicar un workaround para `brcmfmac` pensado para `MacBookPro12,1`.
- Configurar `wireless-regdb` y `/etc/conf.d/wireless-regdom` con tu codigo ISO de pais para mejorar canales/potencia Wi-Fi segun la region.
- Instalar `appmenu-gtk-module` y `libdbusmenu-glib` para mejorar `Global Menu` en Plasma en apps tipo VS Code.
- Escribir un fichero de flags para `Brave` o `Google Chrome` y dejar activada aceleracion hardware en combinaciones soportadas por la wiki de CachyOS.
- Preparar la extension local `YouTube Force H264` en `~/extensions/youtube-force-h264/` para cargarla como `Load unpacked` desde `brave://extensions` o `chrome://extensions`.
- Instalar solo esa extension con `./migration.sh install-youtube-force-h264` sin ejecutar todo `Bootstrap CachyOS`.

Notas:

- Para `MacBookPro12,1` con cámara FaceTime HD PCIe (`14e4:1570`), el script instala `facetimehd-dkms` y `facetimehd-firmware`, configura la carga persistente del módulo y hace blacklist de `bdc_pci`. Si el módulo `bdc_pci` no existe en el kernel (kernels modernos CachyOS), se omite sin error.
- Para `MacBookPro12,1` con `Broadcom BCM43602`, el script puede crear `/etc/modprobe.d/brcmfmac-apple-bcm43602.conf` con `feature_disable=0x82000` y recargar `brcmfmac`.
- Si existe un bundle local en `firmware/brcm/`, el script copia esos ficheros a `/usr/lib/firmware/brcm/` antes de recargar `brcmfmac`.
- Esto permite dejar preparado firmware/NVRAM Broadcom en el propio repo para no depender de Wi-Fi durante el post-install.
- Durante `Backup sistema`, el script intenta extraer en silencio ese bundle desde el sistema actual y lo guarda junto a `migration.sh` en `firmware/brcm/`.
- Si aun asi el Wi-Fi falla y en `dmesg` aparece `backplane type 15 is not supported`, toca revisar manualmente el PCI runtime power management de ese dispositivo.
- La extension `YouTube Force H264` queda preparada en `~/extensions/youtube-force-h264/` con `manifest.json`, `content.js`, `inject.js` y `README.md`.
- Para activarla, abre `brave://extensions` o `chrome://extensions`, activa `Modo desarrollador` y usa `Cargar descomprimida`.
- Si solo quieres ese paquete, puedes ejecutar `./migration.sh install-youtube-force-h264`.
- El popup de la extension incluye un slide para activar o desactivar el parche sin desinstalarla; recarga la pestaña de YouTube para aplicar el cambio.
- La aceleracion Chromium se ofrece solo para combinaciones conservadoras automatizadas:
  - `Brave + AMD`
  - `Chrome + AMD`
  - `Brave + NVIDIA`
- Si la GPU o el navegador no encajan en una plantilla fiable, el script no fuerza nada y remite a la wiki para revision manual.
- AppArmor, parametros de boot y otros cambios de politica del sistema siguen siendo mejor como paso manual posterior por su impacto.

Sin sudo/root.

---

## Claude CLI

Instalación oficial:

```bash
curl -fsSL https://claude.ai/install.sh | bash
```

---

# Docker

Instala:

```text
docker
docker-compose
lazydocker
```

y añade usuario al grupo docker.

---

# Navegadores

```text
Firefox
Brave
```

---

# Herramientas de red

```text
nmap
wireshark
mtr
bind
inetutils
angryipscanner
```

---

# Logitech

Instala:

```text
solaar
piper
libratbag
```

Para:
- MX Master
- MX Keys
- Bolt
- Unifying

---

# Sincronización

## Syncthing

Pensado para sincronizar:
- NAS
- portátil
- workstation
- configs
- scripts
- docs

---

## KDE Connect

Integración:
- móvil
- tablet
- clipboard
- notificaciones
- envío de archivos

---

# Hyprland

## Filosofía

Hyprland NO reemplaza KDE Plasma.

Arquitectura prevista:

```text
KDE Plasma = base estable
Hyprland = opcional/experimental
```

---

# Instalación opcional

El script pregunta:

```text
¿Instalar Hyprland opcional?
```

---

# Componentes Hyprland

```text
hyprland
waybar
rofi-wayland
hyprpaper
grim
slurp
mako
```

---

# Snapshots BTRFS

## Instalado

```text
snapper
grub-btrfs
snap-pac
```

---

# Importante

El script:

- NO modifica particiones
- NO crea subvolúmenes automáticamente

La configuración BTRFS debe realizarse manualmente durante instalación.

---

# DRY RUN

Modo disponible:

```text
¿Modo dry-run?
```

Actualmente:
- evita ejecutar cambios reales
- muestra los comandos que se lanzarían
- sirve para validar rutas, paquetes y flujo general

---

# Filosofía general del sistema

## Prioridades

- estabilidad
- continuidad de trabajo
- entorno moderno
- tooling IA
- terminal eficiente
- separación KDE/Hyprland
- evitar configuraciones rotas entre distros

---

# Recomendaciones finales

## Recomendado sincronizar con Syncthing

Ejemplos:

```text
~/Scripts
~/Notes
~/Documentos/dev_shared
```

---

# NO sincronizar

```text
node_modules
venv
.venv
.cache
dist
build
docker
```

---

# Recomendación importante

Usar repositorio Git privado para dotfiles:

```text
dotfiles/
├── zsh
├── kitty
├── tmux
├── fastfetch
├── hypr
```

---

# Estado esperado final

## Resultado

Workstation Linux moderna con:

- CachyOS
- KDE Plasma
- Hyprland opcional
- ZSH
- Kitty
- tmux
- Docker
- VSCode
- Codex CLI
- Claude CLI
- Syncthing
- KDE Connect
- Solaar
- tooling dev moderno

orientada a:
- programación
- IA
- orchestration
- multi-device workflows
- terminal-heavy development
