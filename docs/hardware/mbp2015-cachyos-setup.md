# Ajustes recomendados de instalación: CachyOS en MacBook Pro Retina 13" 2015

## Equipo objetivo

- **Modelo:** MacBook Pro Retina 13" 2015
- **Identificador habitual:** MacBookPro12,1
- **Uso principal:** programación, navegador, VSCode, terminal, herramientas IA, Docker ocasional
- **Uso en batería:** poco frecuente; normalmente conectado a corriente
- **No prioritario:** cámara, micrófono, Bluetooth
- **Objetivo:** sistema moderno, rápido y mantenible, con KDE Plasma como base estable y Hyprland como opción secundaria

---

## Elección general

| Apartado | Recomendación |
|---|---|
| Distribución | CachyOS |
| Entorno principal | KDE Plasma |
| Entorno opcional | Hyprland, instalado después |
| Bootloader | systemd-boot |
| Sistema de archivos | Btrfs |
| Tabla de particiones | GPT |
| Cifrado | No recomendado en este caso |
| Swap | zram, no partición swap grande |
| Snapshots | Sí, pero con política limitada |

---

## Arranque del instalador

### Primera opción

Usar:

```text
CachyOS
```

Es la opción normal y la primera que probaría.

### Si hay problemas gráficos

Usar:

```text
CachyOS LTS Kernel
```

Más conservador y puede ser útil si hay problemas de kernel, suspensión o gráficos.

### Solo como último recurso

Usar:

```text
CachyOS Legacy Hardware / nomodeset
```

Solo si no arranca el entorno gráfico o hay pantalla negra. No es ideal para uso normal porque puede limitar la aceleración gráfica.

---

## Bootloader

Recomendado:

```text
systemd-boot
```

### Motivo

- Encaja bien con UEFI puro.
- Es simple y rápido.
- Tiene buena integración en Arch/CachyOS.
- Evita complejidad innecesaria.

### No elegiría inicialmente

```text
GRUB
rEFInd
Limine
```

GRUB solo lo usaría si necesitas una configuración multiboot más compleja. rEFInd tiene sentido en Macs con varios sistemas, pero para Linux-only añade una capa innecesaria.

---

## Particionado recomendado

Para SSD interno de 256 GB:

```text
EFI       512 MB - 1 GB    FAT32
Sistema   resto del disco  Btrfs
Swap      zram
```

### EFI

Recomendado:

```text
512 MB o 1 GB
```

No usaría 2 GB salvo que el instalador lo deje así y no quieras tocarlo. No es grave, pero en un SSD de 256 GB prefiero conservar espacio.

### Cifrado

No lo activaría en este caso.

Motivos:

- Equipo usado casi siempre conectado.
- Menos complejidad de arranque.
- Menos puntos de fallo.
- Más simple para snapshots, recuperación y mantenimiento.

---

## Sistema de archivos

Recomendado:

```text
Btrfs
```

Con compresión:

```text
zstd
```

### Motivo

- Buen equilibrio entre rendimiento y ahorro de espacio.
- Snapshots útiles antes/después de actualizaciones.
- Adecuado para Arch/CachyOS.

---

## Subvolúmenes Btrfs

Si el instalador ofrece subvolúmenes automáticos, aceptarlos.

Ideal:

```text
@
@home
@cache
@log
@snapshots
```

### Motivo

Permite separar sistema, home, logs, cachés y snapshots. Esto evita que logs y cachés ensucien snapshots innecesariamente.

---

## Swap

Recomendado:

```text
zram
```

No haría una partición swap grande.

### Motivo

- Mejor para SSD pequeño.
- Menos escrituras.
- Flexible.
- Suficiente para este tipo de uso.

---

## Entorno de escritorio

### Elegir en la instalación

```text
Plasma Desktop / KDE Plasma
```

### Motivo

- Base estable.
- Buena experiencia en Retina.
- Wayland bastante maduro.
- Buen soporte para portátil.
- KDE Connect integrado.
- Excelente fallback si Hyprland falla.

---

## Hyprland

No lo instalaría como entorno principal durante la instalación.

### Estrategia recomendada

```text
KDE Plasma = base estable
Hyprland   = sesión opcional para probar
```

Instalar Hyprland después, cuando el sistema base esté funcionando correctamente.

### Motivo

- Evita mezclar demasiadas variables al principio.
- Si Hyprland falla, KDE sigue disponible.
- Mejor para un MBP 2015 con hardware Apple.

---

## Opciones del instalador

Mantendría marcadas:

```text
CachyOS Packages
CachyOS shell configuration
Base-devel + Common packages
KDE-Desktop
Firefox and language package
```

No marcaría inicialmente:

```text
Hyprland
Printing Support
HP Printer/Scanner
Accessibility Tools
Bluetooth
```

### Notas

- **Base-devel + Common packages** es importante para compilar paquetes, usar AUR y herramientas de desarrollo.
- **Firefox** lo dejaría aunque uses Brave, porque es buen navegador de respaldo y suele funcionar muy bien en Wayland.
- **Bluetooth** no lo instalaría si no lo usas.
- **Printing Support** se puede instalar después si hace falta.

---

## WiFi Broadcom

En este MBP puede haber problemas con Broadcom usando el backend clásico.

La solución que funcionó fue usar `iwd` como backend WiFi de NetworkManager.

```bash
sudo pacman -S iwd
sudo systemctl enable --now iwd
echo -e "[device]\nwifi.backend=iwd" | sudo tee /etc/NetworkManager/conf.d/wifi_backend.conf
sudo systemctl restart NetworkManager
```

### Motivo

Con `wpa_supplicant` puede aparecer el error de contraseña incorrecta aunque la clave sea correcta. Con `iwd`, la autenticación funciona correctamente en este hardware.

---

## Ventilador y temperatura

Instalar `mbpfan` es recomendable en este MacBook.

```bash
sudo pacman -S mbpfan lm_sensors
sudo systemctl enable --now mbpfan
```

### Motivo

En Linux, el módulo `applesmc` expone el ventilador, pero no siempre gestiona la curva térmica como macOS. `mbpfan` permite controlar el ventilador de forma activa y reducir throttling.

### Ajuste inicial razonable para este equipo

```ini
[general]

min_fan1_speed = 1800
max_fan1_speed = 6199

low_temp = 65
high_temp = 78
max_temp = 88

polling_interval = 3
```

### Verificación

```bash
sensors
cat /sys/devices/platform/applesmc.768/fan1_input
cat /sys/devices/platform/applesmc.768/fan1_max
```

Si `fan1_max` no es `6199`, ajustar `max_fan1_speed` al valor real.

---

## Snapshots Btrfs

Sí usaría snapshots, pero limitados por el SSD de 256 GB.

Instalar después:

```bash
sudo pacman -S snapper grub-btrfs snap-pac
```

### Política recomendada

- No snapshots horarios agresivos.
- Pocos snapshots retenidos.
- Limpiar caché de paquetes regularmente.

Ejemplo de limpieza de caché:

```bash
sudo paccache -rk2
```

---

## Paquetes recomendados postinstalación

### Terminal y shell

```text
kitty
zsh
oh-my-zsh
tmux
powerlevel10k
```

### Fuentes

```text
ttf-jetbrains-mono-nerd
noto-fonts
noto-fonts-emoji
```

### Desarrollo

```text
git
base-devel
python
python-pip
uv
node vía nvm
pnpm
bun
vscode
brave
```

### IA / CLI

```text
codex cli
claude cli
```

### Docker

```text
docker
docker-compose
lazydocker
```

### Red

```text
nmap
wireshark-qt
mtr
bind
inetutils
angryipscanner
```

### Integración dispositivos

```text
solaar
piper
libratbag
kdeconnect
syncthing
```

---

## Syncthing

Tiene sentido usarlo para sincronizar entre:

- MBP
- NAS o servidor de archivos
- PC de escritorio Linux

### Sincronizar

```text
~/Scripts
~/Notes
~/Documentos/dev_shared
configs seleccionadas
snippets
```

### No sincronizar

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

## Resumen final recomendado

```text
CachyOS normal
systemd-boot
KDE Plasma
Btrfs + zstd
sin cifrado
zram
EFI 512 MB / 1 GB
Base-devel + Common packages
Firefox
CachyOS shell configuration
Hyprland después, opcional
WiFi con iwd
mbpfan para ventilador
Snapper limitado
Solaar para Logitech
KDE Connect
Syncthing
Kitty + ZSH + tmux
```

---

## Criterio general

La instalación debe priorizar:

- estabilidad
- mantenimiento fácil
- buen soporte gráfico
- recuperación mediante snapshots
- KDE Plasma como entorno fiable
- Hyprland solo como opción secundaria
- buen control térmico
- WiFi estable mediante iwd
- terminal bonito pero eficiente
