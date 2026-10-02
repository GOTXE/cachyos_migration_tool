# ADR-002 — Formato de backup portable (v2) y nombre de carpeta

**Estado:** Accepted  
**Fecha:** 2026-10-02  
**Ámbito:** `backup`, `restore`, `restic-backup`, descubrimiento de backups en las TUI  
**Relacionados:** ADR-001 (D4, D6), SDD-001 (fase 2)

## Contexto

El backup clásico (formato que en este ADR llamamos **v1**) tiene estos problemas:

1. **Pierde la ruta de las configuraciones anidadas.** `rsync -a "$HOME/.config/Code" "$BACKUP_DIR/configs/"` crea `configs/Code`. El restore copia `configs/` sobre `$HOME/`, así que la configuración de VS Code acaba en `~/Code`. Afecta a `.config/*`, `.local/share/*`, `.var/app`, etc. El verificador de la TUI Python (`_verify_backup_selection`) replica el mismo mapeo por `basename`, por eso no lo detecta.
2. **Los directorios de datos se guardan por `basename`.** `/data/Projects` y `~/Projects` colisionan; un directorio fuera de `$HOME` se restaura como `~/<basename>`.
3. **Asume Arch.** El inventario de paquetes depende de pacman (o de dpkg en el código antiguo), la extracción de firmware Broadcom se ejecuta en cada backup y escribe dentro del repo, y había sudo global.
4. **El nombre `linux_backup_YYYY-MM-DD_HH-MM-SS` no identifica el equipo**, y con varios PCs se mezclan los backups.
5. **No hay manifest versionado**, así que el restore no puede saber qué formato está leyendo.

## Decisión

### D1 — El backup y el restore son portables

`backup`, `restore` y `restic-backup` deben funcionar como usuario normal en Arch/CachyOS, Debian/Ubuntu, Fedora/RHEL, openSUSE y derivadas.

Requisitos mínimos del sistema:

- Bash ≥ 4.4;
- GNU coreutils, findutils y util-linux (`stat -c`, `du -sb`, `df --output`, `findmnt`, `lsblk`);
- `rsync` (backup/restore) y `restic` + `ssh`/`sftp` (Restic);
- `python3` solo para la TUI Python (opcional).

No soportado: BusyBox/Alpine, macOS. El preflight lo detecta y falla con un mensaje claro.

El backup **no** usa sudo, **no** llama a pacman/apt/dnf más allá de consultas de inventario de solo lectura y **no** escribe nada fuera del destino del backup y del directorio de logs del usuario.

### D2 — Nombre de la carpeta de backup

Formato canónico:

~~~text
<equipo>_<DD>_<MM>_<AAAA>-<HH>:<mm>
~~~

Ejemplo: `mbp-gotxe_02_10_2026-14:30`

Reglas:

| Elemento | Regla |
|---|---|
| `<equipo>` | `BACKUP_HOST_LABEL` si está definida; si no, `uname -n` sin dominio (lo anterior al primer `.`). Se sustituye cualquier carácter fuera de `[A-Za-z0-9._-]` por `-`. Si queda vacío: `host`. Se conserva mayúscula/minúscula. |
| Fecha y hora | Hora local del sistema, formato `date +%d_%m_%Y-%H:%M`. |
| Separador `:` | Se usa `:` tal cual en sistemas de ficheros POSIX (ext4, btrfs, xfs, f2fs, zfs…). |
| Fallback | Si el destino es `exfat`, `vfat`, `msdos`, `ntfs`, `ntfs3`, `fuseblk`, `cifs` o `smb3`, `:` se sustituye por `h` (`mbp-gotxe_02_10_2026-14h30`), porque esos sistemas no admiten `:` en nombres. Se registra un aviso. |
| Colisión | Si ya existe una carpeta con ese nombre (dos backups en el mismo minuto), se añade `_2`, `_3`… |

Consecuencias que se aceptan explícitamente:

- `DD_MM_AAAA` **no ordena cronológicamente** por nombre. Las TUI y cualquier listado ordenan por `CREATED_AT` del manifest, nunca por el nombre.
- El nombre **no** es la fuente de verdad. Un directorio es un backup si contiene `metadata/manifest.env` (v2) o `metadata/user_ids.conf` (v1).
- `rsync` interpreta como remoto un argumento con `:` antes de la primera `/`. Las rutas de backup se construyen siempre absolutas, así que no aplica. Las funciones que pasan la ruta del backup a `rsync`, `ssh` o `scp` deben usar rutas absolutas.

### D3 — Estructura v2

~~~text
<nombre-backup>/
├── metadata/
│   ├── manifest.env          # obligatorio en v2 (ver D4)
│   ├── user_ids.conf         # se mantiene por compatibilidad con v1
│   ├── os-release            # copia literal de /etc/os-release (si existe)
│   ├── packages/             # inventario (ver D5); solo los ficheros que apliquen
│   ├── flatpak-apps.txt
│   ├── snap-list.txt
│   ├── vscode-extensions.txt
│   └── user-enabled-units.txt
├── configs/                  # rutas RELATIVAS a $HOME conservadas: configs/.config/Code/...
├── repos/                    # rutas relativas a $HOME (sin cambios respecto a v1)
├── data/
│   ├── home/<ruta relativa a $HOME>/...
│   └── external/<ruta absoluta sin la "/" inicial>/...
└── logs/
    ├── backup_selection.txt  # rutas ORIGINALES completas
    ├── copied_files.txt
    └── rsync_warnings.txt
~~~

### D4 — `metadata/manifest.env`

Fichero `CLAVE=valor`, una clave por línea, sin comillas y sin expansión. **Se lee con un parser `IFS='=' read`, nunca con `source`.**

| Clave | Ejemplo | Notas |
|---|---|---|
| `FORMAT_VERSION` | `2` | entero |
| `BACKUP_NAME` | `mbp-gotxe_02_10_2026-14:30` | nombre real usado (con fallback y sufijo si los hubo) |
| `CREATED_AT` | `2026-10-02T14:30:05+0200` | `date +%Y-%m-%dT%H:%M:%S%z` |
| `HOST_LABEL` | `mbp-gotxe` | |
| `TOOL_VERSION` | `1.12.0` | `$VERSION` |
| `OS_ID` / `OS_ID_LIKE` / `OS_VERSION_ID` | `cachyos` / `arch` / `` | de `/etc/os-release`; vacío si no existe |
| `OS_FAMILY` | `arch` | `arch`, `debian`, `fedora`, `suse` o `unknown` |
| `USER` / `UID` / `GID` / `HOME` | `gotxe` / `1000` / `1000` / `/home/gotxe` | |
| `PKG_MANAGERS` | `pacman,flatpak` | los inventariados con éxito, separados por comas |
| `INVENTORY_WARNINGS` | `dnf-userinstalled` | ids de inventario fallidos, separados por comas |
| `DATA_ROOTS` | `home:Documents,external:/data` | correspondencia de `data/` con las rutas originales. Cada ruta va codificada: `%` → `%25`, `,` → `%2C`, salto de línea → `%0A` (ejemplo: `external:/mnt/a%2Cb` para `/mnt/a,b`) |

### D5 — Inventario de paquetes (`metadata/packages/`)

Solo se ejecuta lo que existe en el sistema. Un fallo produce aviso y no aborta el backup.

| Fichero | Comando | Condición |
|---|---|---|
| `pacman-native-explicit.txt` | `pacman -Qqen` | `pacman` existe |
| `pacman-foreign.txt` | `pacman -Qqem` | `pacman` existe (salida vacía válida) |
| `apt-manual.txt` | `apt-mark showmanual` | `apt-mark` existe |
| `dpkg-selections.txt` | `dpkg --get-selections` | `dpkg` existe |
| `rpm-names.txt` | `rpm -qa --qf '%{NAME}\n'` ordenado y único | `rpm` existe |
| `dnf-userinstalled.txt` | `dnf repoquery --userinstalled` (salida tal cual, informativa) | `dnf` existe |
| `zypper-installed.txt` | `zypper --non-interactive --quiet search --installed-only --type package` (informativo) | `zypper` existe |
| `../flatpak-apps.txt` | `flatpak list --app --columns=application,origin` | `flatpak` existe |
| `../snap-list.txt` | `snap list` | `snap` existe |

La misma función de inventario la reutilizan el backup clásico y el runner de Restic (no debe haber dos implementaciones).

El restore **no reinstala paquetes**: reinstalar es tarea del bootstrap y solo dentro de la misma familia de distribución. Restaurar paquetes hardware-específicos (drivers, firmware) en otro equipo está explícitamente fuera de alcance.

### D6 — Restore y compatibilidad v1

- Si existe `metadata/manifest.env`, se usa su `FORMAT_VERSION`. Si es mayor que el soportado, se aborta sin tocar nada.
- Si no existe pero sí `metadata/user_ids.conf`, el backup es **v1**:
  - **configs**: si `logs/backup_selection.txt` contiene la sección `CONFIG_ITEMS:`, cada item `X` se restaura desde `configs/<basename X>` hacia `$HOME/X` (esto repara el bug de rutas anidadas). Si no existe la sección, se usa el comportamiento antiguo con un aviso.
  - **data**: comportamiento antiguo (por `basename`) con un aviso.
- Datos `data/external/...` (v2) se restauran por defecto en `$HOME/restored-external/<ruta absoluta original>`. Con `--external-to-original` se restauran en la ruta original, solo si su directorio padre existe y es escribible por el usuario; si no, se aplica el destino por defecto con aviso.
- El restore se ejecuta como usuario y **no** pide sudo por defecto. Si detecta ficheros que no son del usuario en `.ssh`, `.codex` o `.claude`, avisa e indica el comando. Solo con `--fix-ownership` ejecuta `sudo chown`.

### D7 — Restic

- El runner reutiliza el inventario de D5.
- `restic` se instala con el gestor detectado (`pacman`, `apt-get`, `dnf`, `zypper`); si no hay ninguno conocido, se indica cómo instalarlo y se aborta `init`.
- Cada ejecución hace `backup` + `forget` **sin** `--prune`. El `prune` y un `check` parcial van en una unidad de mantenimiento semanal separada, con `--retry-lock` para convivir con varios equipos sobre el mismo repositorio.
- Los backups se etiquetan con `--host "<HOST_LABEL>"` y el `forget` se limita a ese host.
- Rotación de logs del runner (por defecto 14 días).
- `init` y `status` advierten de que la contraseña de Restic **debe guardarse fuera del equipo**: si el equipo muere, la copia dentro del propio repositorio no sirve.

## Consecuencias

### Positivas

- Las configuraciones anidadas se restauran donde estaban (bug crítico corregido).
- Sin colisiones de datos y sin restaurar en rutas inesperadas.
- Se puede hacer backup en un Debian/Fedora y restaurar en CachyOS (o al revés).
- Varios equipos pueden compartir disco o repositorio sin mezclar backups.
- El restore sabe qué formato lee.

### Costes

- Dos formatos que leer durante un tiempo (v1 y v2).
- El nombre con `:` no es portable a FAT/NTFS/SMB: se acepta el fallback a `h`.
- El orden por nombre deja de ser cronológico; los listados deben leer el manifest.

## Alternativas descartadas

- **`AAAA-MM-DD_HH-mm` (ordenable)**: descartado por requisito explícito del propietario del proyecto (`DD_MM_AAAA-HH:mm`).
- **Prohibir `:` siempre**: descartado; se respeta el formato pedido donde el sistema de ficheros lo admite.
- **Sustituir el backup clásico por Restic**: se mantienen ambos; el clásico sirve para migración offline a disco externo.
