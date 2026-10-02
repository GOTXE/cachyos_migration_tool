# SDD-001 — Refactor genérico de CachyOS Migration Tool

**Estado:** Approved for phased implementation (revisión 2, 2026-10-02)  
**ADR relacionados:** ADR-001 (arquitectura genérica), ADR-002 (backup portable v2)  
**Ejecutor previsto:** Claude Code CLI con Sonnet, esfuerzo *medium*, **una tarea por sesión**  
**Objetivo:** convertir la herramienta en un bootstrap/migration tool reutilizable en workstations CachyOS heterogéneas, con backup/restore portable entre distribuciones, sin rehacer el proyecto desde cero.

---

## 0. Cómo usar este documento (léelo antes de cualquier tarea)

Este SDD está escrito para que un agente ejecute **una tarea `T*` cada vez** sin tener que tomar decisiones de diseño. Todas las decisiones ya están tomadas aquí o en los ADR. Si algo no está decidido, la respuesta correcta es **parar y preguntar**, no improvisar.

### 0.1 Protocolo por tarea

1. Lee: `CLAUDE.md`, la sección 1 (reglas globales), la sección 2 (hechos verificados) y **solo** la sección de tu tarea. Lee los ADR solo si la tarea los cita.
2. Comprueba las dependencias de la tarea en la tabla de la sección 4. Si alguna no está en `main` (o en la rama de integración indicada por el humano), para y avisa.
3. Crea la rama `feature/T<id>-<slug>` (ejemplo: `feature/T2.2-backup-naming`).
4. Localiza el código por **nombre de función** con Grep. Los números de línea de este documento pueden estar desfasados; los nombres no.
5. Escribe primero los tests de la tarea (deben fallar), después implementa.
6. Ejecuta la verificación de la tarea y la verificación global (sección 1.5). Todo en verde.
7. Actualiza `CHANGELOG.md` (sección `## Unreleased`) y la documentación que la tarea liste.
8. Haz commit (sección 1.7). **No** hagas merge, tag ni release: se hace después de la aprobación humana, según `CLAUDE.md`.
9. Al terminar, responde con: resumen de los cambios, ficheros tocados, salida resumida de la verificación y cualquier desviación respecto al SDD.

### 0.2 Condiciones de parada (pregunta al humano y no continúes)

- La tarea requiere tocar un fichero que no está en su lista **Archivos**, salvo `CHANGELOG.md`, tests nuevos y la documentación listada.
- Un test solo podría pasar ejecutando algo como root, instalando paquetes en el host o tocando el `$HOME` real.
- Hace falta un nombre de paquete, URL o flag que no esté en la sección 2 o en la tarea.
- Implementar exactamente lo especificado rompe un test existente que la tarea no menciona.
- La tarea pertenece a la fase 4 o posterior y no tiene el estado `Lista para implementar` (ver sección 4).

### 0.3 Lo que nunca debe hacer el agente

- Ejecutar `./migration.sh bootstrap`, `restore`, `restic-backup run/init` o cualquier comando real sobre el sistema. Solo `--dry-run` y tests con `HOME` temporal.
- Usar `sudo` en tests.
- Cambiar textos de UI que los tests comprueban, salvo que la tarea lo pida.
- Reformatear ficheros enteros (shfmt, reordenar funciones) fuera del alcance de la tarea.
- Borrar funciones legacy sin que la tarea lo pida.

### 0.4 Prompt de arranque recomendado (Claude Code, Sonnet, esfuerzo medium)

Abre una sesión nueva para cada tarea y pega esto, cambiando `<ID>`:

~~~text
Implementa la tarea <ID> de docs/architecture/SDD-001-generic-workstation-refactor.md.

Sigue al pie de la letra la sección 0 (protocolo, condiciones de parada y prohibiciones)
y la sección 1 (reglas globales). Lee solo la sección de la tarea <ID>, las secciones 2-3
y los ADR que la tarea cite. Localiza el código por nombre de función, no por número de línea.

Orden: rama feature/<ID>-<slug> → tests que fallan → implementación → verificación de la
tarea + verificación global (sección 1.5) → CHANGELOG ## Unreleased → commit con el formato
de la sección 1.7. No hagas merge, tag ni release.

Si algo no está especificado o se cumple una condición de parada, detente y pregúntame
antes de seguir. Al terminar, dame: resumen, ficheros tocados, salida resumida de la
verificación y desviaciones respecto al SDD.
~~~

Para las tareas en estado `Refinar`, cambia la primera línea por: `Refina la tarea <ID> según la sección 8: propone subtareas con el formato de las secciones 5-7 y no implementes código.`

---

## 1. Reglas globales

### 1.1 Lenguaje y estilo

- Bash ≥ 4.4 con `set -euo pipefail` en los entrypoints (ya existe). Python 3 solo con stdlib.
- Identificadores en inglés. **Mensajes al usuario en español**, sin cambiar el tono actual.
- Variables locales con `local` declaradas antes de asignar (evita SC2155).
- Las funciones de librería devuelven códigos con `return`; **solo** `main` y los comandos CLI usan `exit`. Las tareas nuevas no añaden `exit` a funciones de librería.
- Rutas siempre entre comillas y absolutas al pasarlas a `rsync`/`ssh`/`scp`.
- Toda acción con efecto pasa por `run_cmd`, `run_cmd_quiet` o `run_shell`, que respetan `DRY_MODE`. No se añaden usos nuevos de `run_shell` si basta con `run_cmd`.
- Sin `eval`. Sin `source` de ficheros de datos nuevos: los ficheros de datos se parsean con `IFS='=' read`.

### 1.2 Privilegios

- Backup, inventario, restore en `$HOME`, plasmoids y systemd `--user` se ejecutan sin sudo.
- `ensure_sudo_session` solo se llama al principio de operaciones que **seguro** necesitan root (instalación de paquetes, `/etc`, systemd de sistema), y nunca en `DRY_MODE`.

### 1.3 Errores

- No se convierte un fallo de instalación o configuración en éxito con `|| true`. `|| true` solo se permite para consultas opcionales, limpieza best-effort o una ausencia esperable.
- Un bloque o paso que falla devuelve código distinto de 0 y lo registra con `log_warn` o un mensaje `[ERROR]`.

### 1.4 Tests

- Los tests viven en `tests/test_*.sh`, son autocontenidos y usan `HOME="$(mktemp -d)"` cuando tocan ficheros de usuario.
- Los comandos externos se simulan con funciones shell o con stubs en un `PATH` temporal (`tests/lib/stubs.sh`, creado en T0.1).
- Los fixtures van en `tests/fixtures/<area>/<caso>/`.
- Ningún test necesita red, root ni hardware real.

### 1.5 Verificación global (obligatoria al final de cada tarea)

~~~bash
bash tests/run.sh
shellcheck -S warning $(git diff --name-only main -- '*.sh')
python3 -m py_compile src/lib/tui.py
./migration.sh --help >/dev/null
~~~

### 1.6 Versionado

- Las tareas no tocan `VERSION`. El bump lo hace el humano al publicar (siguiente versión prevista: `1.12.0`).
- Cada tarea añade una o más líneas a `## Unreleased` en `CHANGELOG.md` (créala si no existe, encima de la última versión). Los cambios incompatibles se marcan con el prefijo `**BREAKING:**`.

### 1.7 Commits

~~~text
T<id>: <resumen imperativo en inglés>

<qué y por qué, 2-5 líneas>

Refs: SDD-001 T<id>
~~~

---

## 2. Hechos verificados (2026-10-02) — no los vuelvas a investigar

| Hecho | Fuente |
|---|---|
| Intel archivó `intel-vaapi-driver` (i965) el 31-01-2025 y remite a `intel-media-driver`. | github.com/intel/intel-vaapi-driver |
| `intel-media-driver` (iHD) soporta BDW, SKL, KBL/CFL/CML, ICL, JSL/EHL, TGL/RKL/ADL/RPL, MTL/ARL, LNL, Arc, BMG. | github.com/intel/media-driver |
| CachyOS, snapshots BTRFS: Limine → `limine-snapper-sync`; GRUB → `grub-btrfs-support`; systemd-boot → `sdboot-manage`; comunes: `snapper`, `snap-pac`, `btrfsmaintenance`. | wiki.cachyos.org/configuration/btrfs_snapshots |
| CachyOS ofrece systemd-boot, rEFInd, GRUB y Limine. | wiki.cachyos.org/installation/boot_managers |
| `chwd -a` autoconfigura drivers en CachyOS; `chwd --list-all` lista perfiles. | wiki.cachyos.org/features/chwd/chwd |
| `yay-bin` está en el repo `cachyos` (12.5.0). | packages.cachyos.org |
| En Arch, `rofi` 2.0 provee y reemplaza `rofi-wayland`. | archlinux.org/packages/extra/x86_64/rofi |
| `opencode` está en Arch `extra`. | archlinux.org/packages/extra/x86_64/opencode |
| **CodexBar Plasma**: repo `Lucenx9/codexbar-plasma`, licencia MIT, `KPlugin.Id = app.codexbar.plasma`, `KPackageStructure = Plasma/Applet`, `X-Plasma-API-Minimum-Version = 6.0`, última release `v0.2.43`. | `metadata.json` del repo |
| CodexBar Plasma publica los assets `codexbar-plasma.plasmoid` y `codexbar-plasma.plasmoid.sha256`. El checksum tiene el formato `^[0-9a-f]{64}[[:space:]][ *]codexbar-plasma\.plasmoid$`. | `scripts/update-widget.sh` del repo |
| CodexBar Plasma necesita en tiempo de ejecución la CLI `codexbar` en el PATH (o una CLI "Managed" configurable desde el widget) y `org.kde.plasma.plasma5support`. | README del repo |
| Instalación/actualización: `kpackagetool6 -t Plasma/Applet -i|-u <fichero>`; borrado: `kpackagetool6 -t Plasma/Applet -r app.codexbar.plasma`. | README / Makefile del repo |

**No verificado (no lo cambies, no lo amplíes):** que el paquete AUR `codexbar-cli` usado hoy por `install_codexbar_tray_dependencies` siga existiendo. Se mantiene tal cual.

---

## 3. Estado actual (baseline tras PR #26)

### 3.1 Ya implementado en PR #26 (Fase 1)

- Catálogo GPU por capacidad (`get_bootstrap_checklist_items`) y `tests/test_gpu_catalog.sh`.
- `pacman -Syu` en lugar de `-Syyu`.
- `eval echo ~user` sustituido por `getent passwd` en `is_mbp_plasmoid_on_desktop`.
- Backup sin `ensure_sudo_session`; inventario `pacman -Qqe` / `-Qqm`.
- `chown` en restore con el grupo primario real.
- CI (`.github/workflows/ci.yml`): `tests/run.sh` + ShellCheck con severidad error.

### 3.2 Observaciones sobre la Fase 1 (las resuelven tareas posteriores)

| Observación | Resuelta en |
|---|---|
| `pacman -Qqe` incluye paquetes foráneos, que quedan duplicados con `-Qqm`. v2 usa `-Qqen`. | T2.1 |
| El catálogo muestra `vaapi` también en `intel+amd` / `intel+nvidia`, pero `configure_vaapi_intel` sigue forzando i965 en Intel genérico, lo que rompe VA-API en Intel moderno. | T1.4 |
| `backup_system` sigue llamando a `extract_broadcom_bundle_silent` en cualquier equipo, que escribe dentro del repo. | T2.3 |
| El restore sigue usando `sudo chown` por defecto. | T2.4 |
| `tests/run.sh` no compila `tui.py` ni descubre tests automáticamente. | T0.1 |

### 3.3 Bugs conocidos aún abiertos

| ID | Bug | Ancla (nombre de función) | Tarea |
|---|---|---|---|
| B1 | Las configuraciones anidadas pierden la ruta (`.config/Code` → `~/Code`). El verificador Python replica el bug. | `backup_system`, `restore_system`, `_verify_backup_selection` (tui.py) | T2.3, T2.4, T2.5 |
| B2 | La CLI `bootstrap` ignora el catálogo e instala MBP Watch e IA en cualquier PC. Hay tres listas de bloques. | `bootstrap_cachyos`, `tui_bootstrap_run`, `get_bootstrap_checklist_items` | T1.3 |
| B3 | `select_disk`: la opción `0` selecciona el último disco (`${DISKS[-1]}`). | `select_disk` | T1.2 |
| B4 | VA-API Intel genérico fuerza i965 y sobrescribe `brave-flags.conf`. | `configure_vaapi_intel`, `write_browser_flags_file`, `configure_chromium_hw_acceleration` | T1.4 |
| B5 | Los datos se guardan por `basename`: colisiones y restauración en otra ruta. | `backup_system`, `restore_system` | T2.3, T2.4 |
| B6 | El log se escribe en `$(pwd)`; `log` usa `echo -e` sobre datos arbitrarios. | `LOGFILE` (common.sh), `log`, `tty_log` | T1.1 |
| B7 | El bloque btrfs instala `grub-btrfs` sin mirar el bootloader. | `configure_btrfs_snapshots` | T1.5 |
| B8 | Restic hace `forget --prune` cada 30 min, no rota logs, no avisa de guardar la contraseña e instala restic solo con pacman. | `restic_backup_install_runtime_script`, `install_restic_package` | T2.7 |
| B9 | El intro referencia `linux-migration-tool.conf.example`, que no existe. | `print_main_menu_intro` | T1.1 |
| B10 | El bloque `appimage` aparece en el catálogo pero `tui_bootstrap_run` nunca lo ejecuta. | `tui_bootstrap_run` | T1.3 |

---

## 4. Índice de tareas

Estados: `Lista` = lista para implementar · `Refinar` = el agente **no** la implementa; debe proponer subtareas y esperar aprobación.

| ID | Título | Depende de | Tamaño | Estado |
|---|---|---|---|---|
| T0.1 | Infraestructura de tests | — | S | Lista |
| T1.1 | Logging en XDG state y `log` seguro | T0.1 | S | Lista |
| T1.2 | Validación de rango en `select_disk` | T0.1 | XS | Lista |
| T1.3 | Registro único de bloques + CLI `bootstrap --blocks` | T0.1 | L | Lista |
| T1.4 | VA-API Intel correcto + flags de navegador sin pisar | T1.3 | M | Lista |
| T1.5 | Snapshots BTRFS según bootloader | T1.3 | S | Lista |
| T2.1 | `os.sh` + inventario de paquetes multi-distro | T0.1 | M | Lista |
| T2.2 | Nombre de carpeta `<equipo>_DD_MM_AAAA-HH:mm` | T2.1 | S | Lista |
| T2.3 | Backup v2 (manifest, rutas relativas, preflight portable) | T2.1, T2.2 | L | Lista |
| T2.4 | Restore v2 + compatibilidad v1 + sin sudo por defecto | T2.3 | L | Lista |
| T2.5 | Descubrimiento y verificación v2 en las TUI | T2.3, T2.4 | M | Lista |
| T2.6 | CI roundtrip en Arch, Debian y Fedora | T2.4 | M | Lista |
| T2.7 | Restic portable + mantenimiento separado | T2.1 | M | Lista |
| T2.8 | Guarda de distribución para `bootstrap` | T2.1, T1.3 | XS | Lista |
| T3.1 | Bloque e instalación verificada de CodexBar Plasma | T1.3 | M | Lista |
| T4.x | Hardware probe (`src/hardware/`, `probe`) | T1.3 | L | Refinar |
| T5.x | Modelo de capacidades sustituye a `MACBOOK_MODEL` en el catálogo | T4.x | M | Refinar |
| T6.x | Perfiles Apple aislados | T5.x | M | Refinar |
| T7.x | Modularización de `bootstrap.sh` (detect/plan/apply/verify) | T1.3 | XL | Refinar |
| T8.x | Configuración declarativa TOML | — | M | Refinar |
| T9.x | Inventario y reducción de `curl \| bash` | — | M | Refinar |
| T10.x | Fixtures hardware en CI | T4.x | M | Refinar |

Orden recomendado: `T0.1 → T1.1 → T1.2 → T1.3 → T2.1 → T2.2 → T2.3 → T2.4 → T2.5 → T2.6 → T2.7 → T2.8 → T1.4 → T1.5 → T3.1`.

---

## 5. Tareas de Fase 0 y Fase 1

### T0.1 — Infraestructura de tests

**Objetivo:** que cualquier test nuevo se ejecute solo y comparta helpers.

**Archivos:** `tests/run.sh`, `tests/lib/assert.sh` (nuevo), `tests/lib/stubs.sh` (nuevo).

**Especificación:**
- `tests/lib/assert.sh` define `fail`, `assert_eq <actual> <esperado> <etiqueta>`, `assert_contains <haystack> <needle> <etiqueta>`, `assert_not_contains`, `assert_file <ruta>`, `assert_no_file <ruta>` y `assert_mode <ruta> <octal>` (usa `stat -c %a`).
- `tests/lib/stubs.sh` define `stub_setup` (crea `STUB_DIR=$(mktemp -d)`, lo antepone a `PATH` y define `STUB_LOG=$STUB_DIR/calls.log`) y `stub_cmd <nombre> [código_salida] [stdout]`, que crea un ejecutable que añade `"<nombre> <args>"` a `$STUB_LOG`, imprime stdout y sale con el código dado. También `stub_teardown`.
- `tests/run.sh`:
  1. ejecuta en orden alfabético todos los `tests/test_*.sh` encontrados;
  2. ejecuta `bash -n` sobre todos los `*.sh` de `migration.sh`, `src/` y `assets/`;
  3. ejecuta `python3 -m py_compile src/lib/tui.py` si existe `python3`;
  4. ejecuta `shellcheck -S error` sobre `src/` y `migration.sh` si existe `shellcheck` (si no, imprime `SKIP shellcheck`);
  5. sale con código ≠0 en el primer fallo, mostrando el nombre del test.
- Los tests existentes **no** se reescriben en esta tarea.

**Verificación:** `bash tests/run.sh` muestra los 4 `OK` actuales más los pasos nuevos.

---

### T1.1 — Logging en XDG state y `log` seguro

**Objetivo:** corregir B6 y B9.

**Archivos:** `src/lib/common.sh`, `tests/test_logging.sh` (nuevo), `README.md`, `README.en.md`, `linux-migration-tool.conf.example` (nuevo).

**Especificación:**
- Las variables de color se definen como bytes reales: `GREEN=$'\033[0;32m'`, etc. (mismos valores).
- `LOGFILE` por defecto: `${XDG_STATE_HOME:-$HOME/.local/state}/linux-migration-tool/logs/linux_migration_tool_<YYYY-MM-DD_HH-MM-SS>.log`. El directorio se crea con `mkdir -p` la primera vez que `log` escribe, no al hacer `source`. Si la variable `LOGFILE` ya viene del entorno, se respeta.
- `log` y `tty_log` usan `printf '%s\n'` (sin interpretar barras invertidas). Al fichero se escribe el mensaje sin secuencias ANSI (`sed -E 's/\x1b\[[0-9;]*m//g'`).
- `prompt_read` sigue funcionando con los colores nuevos (sustituye `printf "%b"` por `printf '%s'`).
- Revisa con Grep `echo -e` y `printf "%b"` en `src/` y migra los que impriman colores a la nueva forma. No toques `assets/`.
- Crea `linux-migration-tool.conf.example` con las variables documentadas hoy (`DATA_DIRS`, `EXTRA_REPO_SEARCH_DIRS`, `EXTRA_CONFIG_ITEMS`, `CODEXBAR_TRAY_REPO_DIR`, `MBP_PLASMOID_TARGET`) comentadas con ejemplos.

**Tests (`tests/test_logging.sh`):**
- Con `HOME` temporal y `cd` a otro directorio temporal: tras `log "x"`, el log existe bajo `$HOME/.local/state/linux-migration-tool/logs/` y **no** hay `*.log` en el cwd.
- `log 'C:\new\table'` escribe literalmente `C:\new\table` en el fichero.
- `log "${GREEN}ok${NC}"` escribe `ok` sin secuencias ESC en el fichero.

**Verificación:** global + el test.

---

### T1.2 — Validación de rango en `select_disk`

**Archivos:** `src/lib/common.sh`, `tests/test_select_disk.sh` (nuevo).

**Especificación:** tras leer `SELECTION`, se acepta solo `1 ≤ SELECTION ≤ ${#DISKS[@]}`. En otro caso, `[ERROR] Seleccion invalida.` y `return 1` (el llamador `backup_system` ya hace `exit` si falla: ajústalo a `select_disk || exit 1`). No cambies el resto de la función.

**Tests:** extrae la validación a `validate_disk_selection <seleccion> <total>` (devuelve 0/1) y prueba `0`, `-1`, `abc`, `""`, `1`, `<total>` y `<total+1>`.

---

### T1.3 — Registro único de bloques + CLI `bootstrap --blocks`

**Objetivo:** corregir B2 aplicando ADR-001 D2.

**Archivos:** `src/core/blocks.sh` (nuevo), `src/lib/common.sh`, `src/lib/tui.sh`, `src/main.sh`, `src/modules/bootstrap.sh` (solo `bootstrap_cachyos`), `tests/test_blocks.sh` (nuevo), `README.md`, `README.en.md`.

**Especificación:**

1. `src/core/blocks.sh`, cargado desde `src/main.sh` después de `common.sh` y de los módulos:
   ~~~bash
   BLOCK_IDS=( sync base_dev yay flatpak official kde aur talk2ai restic appimage \
               filezilla markdownpart libreoffice androidstudio ipscan tea obsidian \
               sshpass codexbar_tray docker_svc zsh node ai_codex ai_engram ai_claude \
               ai_gemini ai_opencode ai_antigravity mbpwatch plasmoid youtube apple \
               facetime iwd hyprland wifi globalmenu hwaccel vaapi btrfs )
   declare -A BLOCK_FN=(
     [sync]=update_system_repos [base_dev]=install_base_devel [yay]=install_yay
     [flatpak]=install_flatpak [official]=install_official_packages [kde]=install_kde_packages
     [aur]=install_aur_packages [talk2ai]=install_talk2ai_from_github [restic]=install_restic_package
     [appimage]=install_appimage_support_package [filezilla]=install_filezilla_package
     [markdownpart]=install_markdownpart_package [libreoffice]=install_libreoffice_package
     [androidstudio]=install_android_studio_package [ipscan]=install_ipscan_package
     [tea]=install_tea_package [obsidian]=install_obsidian_package [sshpass]=install_sshpass_package
     [codexbar_tray]=install_codexbar_tray_from_local_repo [docker_svc]=setup_docker
     [zsh]=block_zsh [node]=install_node_stack [ai_codex]=install_codex_cli
     [ai_engram]=install_engram_for_codex [ai_claude]=install_claude_cli
     [ai_gemini]=install_gemini_cli [ai_opencode]=install_opencode_cli
     [ai_antigravity]=install_antigravity [youtube]=install_youtube_force_h264_package
     [iwd]=configure_networkmanager_iwd_backend [hyprland]=install_hyprland
     [wifi]=configure_wifi_regulatory_domain [globalmenu]=configure_global_menu_support
     [mbpwatch]=install_mbp_watch_diagnostics [plasmoid]=install_mbp_plasmoid_if_accepted
     [apple]=install_apple_laptop_extras [facetime]=configure_facetimehd_camera
     [hwaccel]=configure_chromium_hw_acceleration [vaapi]=configure_vaapi_intel
     [btrfs]=configure_btrfs_snapshots
   )
   ~~~
   `block_zsh` es una función nueva que llama a `install_ohmyzsh` y `install_powerlevel10k`. **El orden de `BLOCK_IDS` es el de ejecución**: es el que tiene hoy `tui_bootstrap_run`, con `appimage` añadido después de `restic` (hoy falta, ver B10).
2. Etiquetas, valores por defecto y visibilidad **siguen saliendo de `get_bootstrap_checklist_items`** (no se duplican). Funciones nuevas:
   - `block_catalog_visible_ids` → ids visibles, en el orden del catálogo;
   - `block_catalog_default_ids` → ids visibles con `ON`;
   - `block_is_visible <id>`.
3. `run_bootstrap_blocks <id>...`:
   - valida todos los ids **antes de ejecutar nada**: un id desconocido o no visible produce `[ERROR] Bloque desconocido o no compatible con este equipo: <id>` y `return 2`;
   - si no es `DRY_MODE`, llama a `ensure_sudo_session` una vez;
   - pone `AUTO_CONFIRM=true`;
   - ejecuta los ids seleccionados **en el orden de `BLOCK_IDS`**, cada uno así (para que `set -e` funcione dentro del bloque):
     ~~~bash
     set +e
     ( set -e; "${BLOCK_FN[$id]}" )
     rc=$?
     set -e
     ~~~
     registrando `log_block_progress` antes de cada bloque y acumulando los fallidos;
   - **importante:** bash ignora `set -e` dentro de cualquier código que se ejecute en contexto `if`/`while`/`&&`/`||`, incluidas las subshells. Por eso `run_bootstrap_blocks` debe llamarse siempre como sentencia simple y su código de salida se captura con `set +e; run_bootstrap_blocks …; rc=$?; set -e`. Nunca con `run_bootstrap_blocks … || …` ni dentro de un `if`. Esto aplica a `bootstrap_cachyos`, a `tui_bootstrap_run` y a los tests;
   - si se seleccionó algún `ai_*`, ejecuta `configure_shell_paths` y `verify_ai_tools` justo después del último bloque `ai_*` y antes de `mbpwatch` (mismo punto que hoy);
   - al final imprime `BOOTSTRAP COMPLETADO` o `BOOTSTRAP COMPLETADO CON ERRORES: <ids>` y devuelve 0 o 1.
   - Nota: al ir cada bloque en una subshell, un bloque no puede depender de variables exportadas por otro. Los bloques `ai_*` ya llaman a `ensure_nvm_node_lts`; compruébalo con Grep. Si encuentras otro caso, para y avisa.
4. `tui_bootstrap_run "$SELECTED" ...`: convierte `SELECTED` (ids entre comillas y separados por espacios, como lo envían whiptail y la TUI Python) a un array y llama a `run_bootstrap_blocks`. Se eliminan todas las líneas `[[ "$SELECTED" == *'"x"'* ]] && ...`.
5. CLI (`parse_bootstrap_args` y `bootstrap_cachyos`):
   - `--blocks a,b,c` → exactamente esos bloques;
   - sin `--blocks` → `block_catalog_default_ids`;
   - `--hyprland yes|no` añade o quita `hyprland`; `--apple-laptop yes|no` añade o quita `apple` (solo si es visible);
   - `--list-blocks` imprime `id<TAB>ON|OFF<TAB>etiqueta` de los bloques visibles y sale con 0;
   - `bootstrap_cachyos` pasa a ser: contexto + `run_bootstrap_blocks "${ids[@]}"` + mensaje final de recomendación. Se elimina la secuencia fija de llamadas.
6. El menú de texto (opción 2) llama a `bootstrap_cachyos` (por defecto) sin cambios.
7. CHANGELOG: `**BREAKING:** \`bootstrap\` sin \`--blocks\` ejecuta solo los bloques compatibles marcados por defecto; MBP Watch ya no se instala implícitamente.`

**Tests (`tests/test_blocks.sh`), con `BLOCK_FN` apuntando a stubs que añaden su id a un fichero:**
- cada id de `BLOCK_IDS` tiene entrada en `BLOCK_FN` y la función existe (`declare -F`) tras cargar `main.sh` sin ejecutar `main` (añade al final de `src/main.sh` la guarda `if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then main "$@"; fi`; **no** uses la forma `[[ … ]] && main`, porque al hacer `source` devolvería 1 y abortaría los tests con `set -e`);
- cada id que puede devolver `get_bootstrap_checklist_items` está en `BLOCK_IDS` (con perfiles `MacBookPro12,1` y `GenericPC` y GPU `intel+nvidia`);
- `run_bootstrap_blocks node sync` ejecuta `sync` antes que `node`;
- `run_bootstrap_blocks appimage` ejecuta `install_appimage_support_package` (regresión B10);
- con `MACBOOK_MODEL=GenericPC`, `run_bootstrap_blocks mbpwatch` devuelve 2 y no ejecuta nada;
- un stub que falla con `false` a mitad de función hace que el bloque cuente como fallido aunque la última línea tenga éxito;
- un bloque fallido no impide ejecutar los siguientes y el retorno final es 1;
- `--list-blocks` en `GenericPC` no contiene `mbpwatch`.

**Verificación:** global + `DRY_MODE=true ./migration.sh bootstrap --dry-run --blocks sync,node` muestra solo esos dos bloques.

---

### T1.4 — VA-API Intel correcto + flags de navegador sin pisar

**Objetivo:** corregir B4.

**Archivos:** `src/modules/bootstrap.sh` (`configure_vaapi_intel`, `write_browser_flags_file`, `configure_chromium_hw_acceleration`), `src/lib/common.sh` (solo la etiqueta de `vaapi` si cambia), `tests/test_vaapi.sh` (nuevo), `docs/hardware/vaapi-testing-notes.md` (añadir una sección breve).

**Especificación:**

| Caso (`get_macbook_profile_id`) | Paquetes | `~/.config/environment.d/vaapi.conf` |
|---|---|---|
| `mbp12_1` | `libva-intel-driver-irql` (AUR) + `libva-utils` | `LIBVA_DRIVER_NAME=i965` (sin cambios) |
| `mbp8_1` | `libva-intel-driver` + `libva-utils` | `LIBVA_DRIVER_NAME=i965` (sin cambios) |
| cualquier otro con GPU Intel | `intel-media-driver` + `libva-intel-driver` + `libva-utils` | **no se crea**. Si ya existe y su único contenido es la línea `LIBVA_DRIVER_NAME=i965` (lo que escribía la versión anterior de esta herramienta), se renombra a `vaapi.conf.bak.<YYYYmmddHHMMSS>` con aviso; con cualquier otro contenido no se toca |

- Se instalan ambos drivers en el caso genérico para no tener que adivinar la generación: libva elige el driver adecuado y, en GPUs anteriores a Broadwell, el i965 sigue disponible.
- `write_browser_flags_file <fichero> <contenido>`:
  - si el fichero no existe, lo escribe;
  - si existe con el mismo contenido, no hace nada (`log_info`);
  - si existe con otro contenido, lo copia a `<fichero>.bak.<YYYYmmddHHMMSS>`, lo sobrescribe y avisa con la ruta del backup.
- En el caso Intel genérico **no** se escribe `brave-flags.conf` (se elimina `--ozone-platform-hint=x11` para Intel genérico). Los perfiles MBP mantienen sus flags actuales.
- Verificación al final del bloque: si existe `vainfo`, se ejecuta y se registra la línea `Driver version`; si falla, `log_warn` (no error).

**Tests:** stubs de `yay`, `sudo` y `vainfo`; `DRY_MODE=false` con `run_cmd` redefinido para registrar llamadas:
- genérico: aparecen `intel-media-driver` y `libva-intel-driver`; no aparece `LIBVA_DRIVER_NAME`; no se crea `brave-flags.conf`;
- `mbp12_1`: aparece `libva-intel-driver-irql` y se crea `vaapi.conf` con `i965`;
- `write_browser_flags_file`: los tres casos (nuevo, idéntico, distinto → `.bak` creado).

---

### T1.5 — Snapshots BTRFS según bootloader

**Objetivo:** corregir B7.

**Archivos:** `src/modules/bootstrap.sh` (`configure_btrfs_snapshots`, nueva `detect_bootloader`), `src/lib/common.sh` (visibilidad de `btrfs`), `tests/test_btrfs_block.sh` (nuevo).

**Especificación:**
- `detect_bootloader` (sin sudo; usa `BOOT_ROOT_PREFIX`, por defecto vacío, para los tests) devuelve la primera coincidencia:
  1. `limine` si existe `limine.conf` en `$PREFIX/boot`, `$PREFIX/boot/limine`, `$PREFIX/efi`, `$PREFIX/boot/efi` o `$PREFIX/boot/EFI/limine`;
  2. `grub` si existe `$PREFIX/boot/grub/grub.cfg`;
  3. `systemd-boot` si existe `$PREFIX/boot/loader/loader.conf` o `$PREFIX/efi/loader/loader.conf`;
  4. si no, `unknown`.
- Paquetes: `snapper snap-pac` más `limine-snapper-sync` (limine), `grub-btrfs-support` (grub) o `sdboot-manage` (systemd-boot). Con `unknown`, `log_warn` y `return 1` sin instalar nada.
- El bloque `btrfs` solo es visible si `findmnt -no FSTYPE /` es `btrfs` (función `detect_root_filesystem`, que se puede simular en los tests).
- Se mantiene el aviso de que la herramienta no crea subvolúmenes. Si `snapper list-configs` no lista `root`, se imprime la orientación de la wiki de CachyOS (texto, sin ejecutar nada).

**Tests:** fixtures de árbol `/boot` para los cuatro casos, paquetes esperados por caso y visibilidad con `btrfs` frente a `ext4`.

---

## 6. Fase 2 — Backup portable (ADR-002)

### T2.1 — `os.sh` + inventario multi-distro

**Archivos:** `src/lib/os.sh` (nuevo), `src/lib/inventory.sh` (nuevo), `src/main.sh` (cargarlos), `tests/test_os.sh`, `tests/test_inventory.sh`, `tests/fixtures/os-release/{cachyos,arch,debian,ubuntu,fedora,opensuse-tumbleweed,unknown}`.

**Especificación `os.sh`:**
- `os_release_value <CLAVE>` lee `${OS_RELEASE_FILE:-/etc/os-release}` con un parser (sin `source`) y quita comillas.
- `os_family` devuelve `arch | debian | fedora | suse | unknown` mirando `ID` y luego `ID_LIKE`:
  - `arch`: `arch`, `cachyos`, `endeavouros`, `manjaro` o `ID_LIKE` que contenga `arch`;
  - `debian`: `debian`, `ubuntu` o `ID_LIKE` que contenga `debian` o `ubuntu`;
  - `fedora`: `fedora`, `rhel`, `centos`, `rocky`, `almalinux` o `ID_LIKE` que contenga `fedora` o `rhel`;
  - `suse`: `ID` que empiece por `opensuse` o sea `sles`, o `ID_LIKE` que contenga `suse`.
- `os_pkg_install_cmd <paquete>` imprime el comando sugerido (`sudo pacman -S --needed <p>`, `sudo apt-get install -y <p>`, `sudo dnf install -y <p>`, `sudo zypper --non-interactive install <p>`) o vacío si la familia es `unknown`.
- `require_commands <cmd>...`: por cada comando ausente imprime `[ERROR] Falta <cmd>. Instálalo con: <sugerencia>` y al final `return 1` si faltó alguno. Sustituye a `require_command rsync` en backup y restore.
- `require_bash_44`: devuelve 1 con mensaje si `BASH_VERSINFO` < 4.4.

**Especificación `inventory.sh`:**
- `inventory_write <dir_metadata>` crea `<dir>/packages/` y genera los ficheros de la tabla D5 de ADR-002, solo para los comandos que existan. Cada comando se ejecuta con `LC_ALL=C` y salida a un fichero temporal que se mueve al destino solo si el comando terminó con 0.
- Exporta (como variables globales) `INVENTORY_MANAGERS` e `INVENTORY_WARNINGS`, ambas separadas por comas.
- El fichero debe poder cargarse con `source` sin depender de `common.sh` (lo reutiliza el runner de Restic en T2.7): **no** usa `log`, `run_cmd` ni colores; escribe avisos por stderr.

**Tests:** fixtures de os-release; stubs de `pacman`, `apt-mark`, `dpkg`, `rpm`, `flatpak` y `dnf` (este último con salida 1 para comprobar `INVENTORY_WARNINGS`); un `PATH` sin gestores produce un `packages/` vacío sin error.

---

### T2.2 — Nombre de carpeta `<equipo>_DD_MM_AAAA-HH:mm`

**Archivos:** `src/modules/backup.sh`, `tests/test_backup_naming.sh` (nuevo).

**Especificación (ADR-002 D2):**
- `backup_host_label` → `BACKUP_HOST_LABEL` o `uname -n`; se quita el dominio, se sanea con `sed -E 's/[^A-Za-z0-9._-]/-/g'` y queda `host` si resulta vacío.
- `backup_timestamp_label` → `date +%d_%m_%Y-%H:%M` (si existe `BACKUP_NOW_EPOCH`, `date -d "@$BACKUP_NOW_EPOCH" +...`, solo para tests).
- `backup_fs_forbids_colon <fstype>` → 0 para `exfat|vfat|msdos|ntfs|ntfs3|fuseblk|cifs|smb3`.
- `build_backup_name <destino>`:
  1. `<host>_<timestamp>`;
  2. si el destino prohíbe `:`, cambia `:` por `h` y avisa con `log_warn`;
  3. si `<destino>/<nombre>` ya existe, añade `_2`, `_3`… hasta encontrar uno libre.
- `backup_system` usa `build_backup_name "$DISK_MOUNT"` en lugar de `linux_backup_${DATE}`. Necesita `BACKUP_FS_TYPE`, así que `configure_backup_rsync_mode` se llama antes.

**Tests:**
- `TZ=UTC`, `BACKUP_NOW_EPOCH=1790951405` (2026-10-02 14:30:05 UTC) y `BACKUP_HOST_LABEL='Mi PC/01'` → `Mi-PC-01_02_10_2026-14:30`;
- `uname -n` simulado `box.lan` → `box_…`;
- fstype `exfat` → `…-14h30`;
- colisión → sufijo `_2`;
- regex `^[A-Za-z0-9._-]+_[0-9]{2}_[0-9]{2}_[0-9]{4}-[0-9]{2}[:h][0-9]{2}(_[0-9]+)?$`.

---

### T2.3 — Backup v2

**Objetivo:** corregir B1 y B5 en el lado del backup; portabilidad (ADR-002 D1, D3, D4, D5).

**Archivos:** `src/modules/backup.sh`, `src/lib/common.sh` (solo `estimate_backup_bytes` y `select_disk` si hace falta), `tests/test_backup_roundtrip.sh` (nuevo; en esta tarea solo cubre el backup).

**Especificación:**
1. Preflight al inicio de `backup_system`: `require_bash_44`, `require_commands rsync find du df findmnt stat`, y `lsblk` solo si se va a usar `select_disk`.
2. Se elimina la llamada a `extract_broadcom_bundle_silent` (la extracción de firmware sigue disponible en el bootstrap Apple; no se borra la función).
3. **configs:** cada item se copia con rutas relativas preservadas:
   ~~~bash
   rsync "${BACKUP_RSYNC_OPTIONS[@]}" -R "${BROKEN_LINK_EXCLUDES[@]}" \
         "$HOME/./$ITEM" "$BACKUP_DIR/configs/"
   ~~~
   Las exclusiones de enlaces rotos (`build_broken_symlink_excludes`) devuelven rutas relativas al item. Con `-R` la raíz de transferencia pasa a ser `$HOME/`, así que cada exclusión debe convertirse en `--exclude=/<ITEM>/<ruta relativa>` (con `/` inicial para anclarla a la raíz). Cubre esto con un test: un enlace roto dentro de `.config/Code` en destino `exfat` simulado no debe abortar el backup.
4. **repos:** sin cambios de layout. Se añaden las exclusiones `node_modules`, `.pnpm-store`, `.tox`, `.mypy_cache`, `.pytest_cache` y `.ruff_cache` a las existentes.
5. **data:** cada directorio de datos `D`:
   - si `D` está bajo `$HOME`: destino `data/home/<ruta relativa>/`;
   - si no: destino `data/external/<D sin la / inicial>/`;
   - se acumula `DATA_ROOTS` (`home:<rel>` o `external:<abs>`, separado por comas).
   Las exclusiones de repos anidados no cambian.
6. **metadata:**
   - `manifest.env` con todas las claves de ADR-002 D4, escrito con `printf '%s=%s\n'` (los valores no contienen saltos de línea; elimínalos si los hubiera);
   - `user_ids.conf` (se mantiene);
   - `os-release` (copia, si existe);
   - `inventory_write "$BACKUP_DIR/metadata"`;
   - `vscode-extensions.txt` (si existe `code`);
   - `user-enabled-units.txt` (`systemctl --user list-unit-files --state=enabled --no-pager`, best-effort).
   - Se elimina la exportación antigua `dpkg_packages.txt`, `flatpak_packages.txt` y `pacman_explicit.txt`/`aur_foreign.txt`: ahora la hace `inventory_write`.
7. `logs/backup_selection.txt` registra las rutas originales completas: `CONFIG_ITEMS:` (relativas a `$HOME`, como hoy) y `DATA_DIRS:` (absolutas, como hoy). El formato no cambia.
8. Todo el backup sigue funcionando en `DRY_MODE` sin escribir nada fuera del log.

**Test (`tests/test_backup_roundtrip.sh`, parte backup):** con `HOME` temporal, destino temporal y `BACKUP_SELECTION_FROM_TUI=1`, `SELECTED_CONFIG_ITEMS_RAW`, `SELECTED_DATA_DIRS_RAW`, `AUTO_CONFIRM_ENV=1` y `BACKUP_HOST_LABEL=testhost`, ejecuta `./migration.sh backup --target "$DEST"`. Fixture del `HOME`:
- `.config/Code/User/settings.json`, `.bashrc`, `.ssh/id_ed25519` (modo 600);
- `Documents/notes.txt` y un fichero con nombre `a\b c.txt`;
- `Documents/GITHUB/proj/.git/` (`git init`) con `node_modules/x` y `src/main.py`;
- directorio externo `$TMP/ext/data1/f.txt`.

Comprueba:
- `configs/.config/Code/User/settings.json` existe;
- `data/home/Documents/notes.txt` y `data/external/<TMP sin />/ext/data1/f.txt` existen;
- `repos/Documents/GITHUB/proj/src/main.py` existe y `node_modules` **no**;
- `manifest.env` contiene `FORMAT_VERSION=2` y `HOST_LABEL=testhost`;
- el nombre de la carpeta cumple la regex de T2.2;
- no hay llamadas a `sudo` (stub de `sudo` que falla si se invoca).

---

### T2.4 — Restore v2 + compatibilidad v1 + sin sudo por defecto

**Objetivo:** corregir B1 y B5 en el lado del restore (ADR-002 D6).

**Archivos:** `src/modules/restore.sh`, `src/main.sh` (`parse_restore_args`), `src/lib/common.sh` (`parse_user_ids` puede seguir igual), `tests/test_backup_roundtrip.sh` (ampliar), `tests/test_restore_v1.sh` (nuevo), `tests/fixtures/backup-v1/` (nuevo, generado a mano: estructura mínima de un backup antiguo con `configs/Code/…` y `logs/backup_selection.txt`), `README.md`, `README.en.md`.

**Especificación:**
- `read_backup_manifest <dir>` → rellena las variables `BM_FORMAT_VERSION`, `BM_HOST_LABEL`, `BM_CREATED_AT`… (prefijo `BM_`, parser sin `source`). Si no existe el manifest pero sí `user_ids.conf`, fija `BM_FORMAT_VERSION=1`. Si no hay ninguno de los dos, `return 1`.
- Si `BM_FORMAT_VERSION > 2`, sale con `[ERROR] Formato de backup no soportado: <v>` sin tocar nada.
- **v2**:
  - `configs/` → `$HOME/` (ahora correcto, porque las rutas son relativas);
  - `repos/` → `$HOME/`;
  - `data/home/` → `$HOME/`;
  - `data/external/<p>` → `$HOME/restored-external/<p>`, o `/<p>` con `--external-to-original` si su padre existe y es escribible (si no, se usa el destino por defecto con `log_warn`).
- **v1**:
  - configs según ADR-002 D6 (mapeo por `backup_selection.txt`; sin él, comportamiento antiguo con `log_warn`);
  - `repos` igual que antes;
  - `data` con el comportamiento antiguo y `log_warn`.
- `restore_conflicts_exist` se adapta: en v2 recorre los items reales (rutas relativas bajo `configs/`, hasta el nivel del item según `backup_selection.txt`); en v1 usa el mapeo.
- Ownership:
  - se elimina `ensure_sudo_session` y el `sudo chown` incondicional;
  - `find "$HOME/.ssh" "$HOME/.codex" "$HOME/.claude" ! -user "$(id -u)" -print -quit 2>/dev/null` → si devuelve algo y no se pasó `--fix-ownership`, `log_warn` con el comando exacto `sudo chown -R "$(id -un):$(id -gn)" <ruta>`;
  - con `--fix-ownership`: `ensure_sudo_session` y `run_cmd sudo chown -R …`.
- Se mantienen la normalización de permisos (`restore_rsync`, `--preserve-permissions`), los `chmod` de `.ssh` y `normalize_restored_git_repository_permissions`.
- `verify_rsync_restored_tree` se llama con los pares origen→destino reales de v2/v1.

**Tests:**
- roundtrip (amplía T2.3): restaura en otro `HOME2` vacío con `--force` y comprueba `HOME2/.config/Code/User/settings.json`, que `HOME2/Code` **no** existe, `HOME2/Documents/notes.txt`, `HOME2/restored-external/<…>/f.txt`, el fichero `a\b c.txt`, el modo `600` de la clave SSH y que `sudo` no se llamó;
- v1: el fixture restaura `configs/Code` en `$HOME/.config/Code`;
- v1 sin `backup_selection.txt`: comportamiento antiguo + aviso en la salida;
- `FORMAT_VERSION=3` → error y `HOME` intacto.

---

### T2.5 — Descubrimiento y verificación v2 en las TUI

**Archivos:** `src/lib/tui.sh` (`_tui_is_backup_dir`, `tui_find_restore_backups`), `src/lib/tui.py` (`_extract_backup_destination`, `_verify_backup_selection` y cualquier referencia a `user_ids.conf` o `linux_backup_` encontrada con Grep), `tests/test_tui_discovery.sh` (nuevo), `tests/test_tui_py.py` (nuevo; se ejecuta desde `tests/run.sh` con `python3 -m unittest` si existe `python3`).

**Especificación:**
- Un directorio es backup si contiene `metadata/manifest.env` **o** `metadata/user_ids.conf`.
- `tui_find_restore_backups` busca ambos ficheros (`-maxdepth 5`, como hoy), elimina duplicados y ordena por `CREATED_AT` del manifest de forma descendente; los v1 se ordenan por `mtime` de `user_ids.conf` y van después de los v2 con la misma fecha. Para cada uno imprime la ruta (formato de salida sin cambios).
- `_extract_backup_destination` prefiere la línea siguiente a `Destino:` (como hoy). Su fallback acepta la regex v1 y la v2 (`/<host>_DD_MM_AAAA-HH[:h]mm(_N)?$`).
- `_verify_backup_selection` usa el layout v2: `configs/<item>`, `data/home/<rel>` y `data/external/<abs sin />`.
- Los listados que muestran backups al usuario añaden el host (`HOST_LABEL`) cuando existe manifest.

**Tests:** árboles temporales con dos v2 (fechas distintas, nombres cuyo orden alfabético es el inverso del cronológico) y un v1 → el orden de salida es correcto; prueba unitaria Python de `_verify_backup_selection` sobre un backup v2 generado en un directorio temporal.

---

### T2.6 — CI roundtrip en Arch, Debian y Fedora

**Archivos:** `.github/workflows/ci.yml`.

**Especificación:** añade un job `roundtrip` con matriz `container: [archlinux:latest, debian:stable, fedora:latest]`. Pasos:
1. instalar `bash rsync git python3 findutils util-linux coreutils` con el gestor del contenedor (`pacman -Sy --noconfirm`, `apt-get update && apt-get install -y`, `dnf install -y`);
2. crear un usuario no root y ejecutar como ese usuario `bash tests/test_backup_roundtrip.sh` y `bash tests/test_restore_v1.sh`.

El job existente `test` no cambia.

**Verificación:** el workflow pasa `actionlint` si está disponible localmente; si no, revisión de sintaxis YAML con `python3 -c 'import yaml'` solo si PyYAML existe (si no, indícalo en el resumen).

---

### T2.7 — Restic portable + mantenimiento separado

**Objetivo:** corregir B8 (ADR-002 D7).

**Archivos:** `src/modules/restic_backup.sh`, `src/modules/bootstrap.sh` (`install_restic_package`), `assets/systemd/user/restic-maintenance.service` (nuevo), `assets/systemd/user/restic-maintenance.timer` (nuevo), `assets/templates/backup-restic.env.example`, `assets/templates/restic-excludes.txt`, `docs/backup-sftp-restic.md`, `tests/test_restic_runner.sh` (nuevo).

**Especificación:**
- `install_restic_package`:
  - en familia `arch`, como hoy;
  - en `debian` / `fedora` / `suse`, con `run_cmd sudo <apt-get install -y|dnf install -y|zypper --non-interactive install> restic`;
  - en `unknown`, `[ERROR]` con instrucciones y `return 1`.
- `restic_backup_install_runtime_script` instala además `src/lib/inventory.sh` en `~/.local/lib/cachyos-migration-tool/inventory.sh`. El runner generado lo carga con `source` y su `update_system_state` llama a `inventory_write "$SYSTEM_STATE_DIR"` más los manifiestos que no son de paquetes (unidades, mounts, lsblk, uname).
- Runner:
  - `backup` con `--host "$HOST_LABEL" --one-file-system --exclude-caches --tag workstation --tag automatic`. `HOST_LABEL` sale de `BACKUP_HOST_LABEL` o del mismo cálculo que `backup_host_label` (función duplicada mínima dentro del runner, documentada como tal);
  - `forget --host "$HOST_LABEL"` con la política actual, **sin** `--prune`;
  - subcomando nuevo `maintenance`: `forget --host … --prune --retry-lock 30m` + `check --read-data-subset=5% --retry-lock 30m`;
  - rotación: borra `$STATE_ROOT/*.log` con antigüedad mayor que `BACKUP_LOG_RETENTION_DAYS` (por defecto 14) al principio de cada ejecución. `latest.log` no se borra.
- `restic-maintenance.timer`: `OnCalendar=Sun *-*-* 12:00:00`, `Persistent=true`, `RandomizedDelaySec=30min`. `install-timer` y `disable-timer` gestionan ambos timers.
- `init` (al terminar) y `status` (siempre) imprimen: `AVISO: guarda una copia de la contraseña de Restic fuera de este equipo (gestor de contraseñas). Ruta local: <ruta>`.
- Excludes: se añaden `/home/*/Downloads`; se **eliminan** `**/build`, `**/dist` y `**/target` (pueden ser datos de usuario); `node_modules`, `venv`, cachés, etc. se mantienen.

**Tests:** genera el runner en un `HOME` temporal con stubs de `restic`, `sftp`, `systemctl` y `uname`; comprueba los argumentos de `backup` y de `forget` (sin `--prune`), los de `maintenance` (`--prune`, `--retry-lock`), que un log de 20 días se borra y uno de 1 día no, y el aviso de la contraseña en `status`.

---

### T2.8 — Guarda de distribución para `bootstrap`

**Archivos:** `src/main.sh`, `tests/test_os_guard.sh` (nuevo).

**Especificación:** antes de despachar `bootstrap`, `tui-bootstrap-run`, `configure-vaapi-brave`, `install-mbp-watch`, `install-talk2ai`, `install-codexbar-tray` y `install-youtube-force-h264`, si `os_family` no es `arch`: `[ERROR] Este comando solo está soportado en Arch/CachyOS (detectado: <ID>).` y `exit 1`. `backup`, `restore`, `restic-backup`, `postcheck`, `test` y los comandos de plasmoid (incluido `install-codexbar-plasma`) no se bloquean.

**Tests:** `OS_RELEASE_FILE` con el fixture `debian` → `bootstrap --dry-run` sale con 1 y el mensaje; `backup --dry-run` con `--target` temporal no se bloquea.

---

## 7. Fase 3 — CodexBar Plasma

### T3.1 — Bloque e instalación verificada de CodexBar Plasma

**Objetivo:** añadir `Lucenx9/codexbar-plasma` como opción de instalación (ADR-001 D5).

**Archivos:** `src/modules/codexbar_plasma.sh` (nuevo; cargado desde `main.sh`), `src/core/blocks.sh`, `src/lib/common.sh` (`get_bootstrap_checklist_items`), `src/modules/bootstrap.sh` (extraer `install_codexbar_cli` desde `install_codexbar_tray_dependencies` sin cambiar su comportamiento; `post_bootstrap_checks`), `src/main.sh` (comandos y `usage`), `src/lib/tui.py` y `src/lib/tui.sh` **solo** si el menú de plasmoids necesita la entrada nueva, `tests/test_codexbar_plasma.sh` (nuevo), `tests/test_bootstrap_catalog.sh` (añadir una aserción), `README.md`, `README.en.md`, `tech_docs/pendientes.md`.

**Constantes:**
~~~bash
CODEXBAR_PLASMA_ID="app.codexbar.plasma"
CODEXBAR_PLASMA_REPO="Lucenx9/codexbar-plasma"
CODEXBAR_PLASMA_ASSET="codexbar-plasma.plasmoid"
CODEXBAR_PLASMA_VERSION="${CODEXBAR_PLASMA_VERSION:-latest}"   # o vX.Y.Z
~~~

**URLs:**
- `latest` → `https://github.com/Lucenx9/codexbar-plasma/releases/latest/download/<asset>` y `…/<asset>.sha256`;
- `vX.Y.Z` → `https://github.com/Lucenx9/codexbar-plasma/releases/download/vX.Y.Z/<asset>` y `….sha256`;
- la versión debe cumplir `^(latest|v[0-9]+\.[0-9]+\.[0-9]+)$`; si no, `[ERROR]` y `return 2`.

**`install_codexbar_plasma [--version V] [--with-cli]`:**
1. Si `id -u` es 0 → `[ERROR] Instala CodexBar Plasma como tu usuario de escritorio, no como root.`, `return 1`. (Usa una función `current_uid` para poder simularla en los tests.)
2. `require_commands kpackagetool6 curl sha256sum python3`.
3. `DRY_MODE` → registra las dos URLs, la verificación y el comando `kpackagetool6` previsto, y `return 0` sin descargar.
4. Crea un directorio temporal con `trap` de limpieza en `RETURN`. Descarga ambos ficheros con `curl -fsSL --proto '=https' --tlsv1.2 --max-time 120 -o <fichero> <url>`.
5. El `.sha256` debe cumplir la regex de la sección 2. Después, `(cd "$TMP" && sha256sum --check --strict --status "$ASSET.sha256")`. Si falla, `[ERROR] Checksum de CodexBar Plasma no válido; no se instala.` y `return 1`.
6. Lee `metadata.json` del zip con `python3` (stdlib `zipfile`, `json`) e imprime `Id<TAB>Version`. Si `Id` ≠ `app.codexbar.plasma`, `[ERROR]` y `return 1`.
7. Si `kpackagetool6 -t Plasma/Applet -l` contiene el id, ejecuta `run_cmd kpackagetool6 -t Plasma/Applet -u <fichero>`; si no, `run_cmd kpackagetool6 -t Plasma/Applet -i <fichero>`. Sin `sudo`.
8. Verifica que el id aparece en `kpackagetool6 -t Plasma/Applet -l`; si no, `return 1`.
9. CLI `codexbar`:
   - si `command -v codexbar` existe, `log_success`;
   - si no y se pasó `--with-cli` en familia `arch`, `install_codexbar_cli` (comportamiento actual: AUR `codexbar-cli`);
   - en cualquier otro caso, `log_warn` explicando que el widget necesita la CLI y que puede usarse **General → Managed CLI → Use managed CLI** desde la configuración del widget.
10. Si `systemctl --user is-enabled codexbar-tray.service` responde `enabled`, `log_info` avisando de que tendrá dos indicadores de CodexBar (no se desactiva nada).
11. Mensaje final: `Añade "CodexBar" desde Añadir widgets del panel.` Si fue una actualización (`-u`), añade `Para recargarlo: systemctl --user restart plasma-plasmashell.service`. **No** se reinicia plasmashell automáticamente ni se añade el widget al panel.

**`uninstall_codexbar_plasma`:** si está instalado, `run_cmd kpackagetool6 -t Plasma/Applet -r app.codexbar.plasma`; si no, `log_info` y `return 0`. No toca la CLI.

**Catálogo:**
- línea `codexbar_plasma|CodexBar Plasma (widget panel KDE 6, release verificada)|OFF`, visible solo si existe `kpackagetool6`;
- en `BLOCK_IDS`, justo después de `codexbar_tray`;
- `BLOCK_FN[codexbar_plasma]=block_codexbar_plasma`, que llama a `install_codexbar_plasma --with-cli`.

**CLI:**
- `./migration.sh install-codexbar-plasma [--version vX.Y.Z|latest] [--with-cli] [--dry-run]`;
- `./migration.sh uninstall-codexbar-plasma [--dry-run]`;
- documentar ambos en `usage` y en los README.

**Postcheck:** una línea `CodexBar Plasma: instalado (<versión>)` o `no instalado` (informativa, nunca error).

**Tests (`tests/test_codexbar_plasma.sh`)** con stubs de `curl` (copia ficheros fixture según la URL y registra la URL), `kpackagetool6` (registra los argumentos; `-l` lee un fichero de estado) y `systemctl`. El `.plasmoid` de prueba se genera en el test con `python3 -m zipfile` o `zipfile` desde un `metadata.json` temporal:
- instalación nueva → `-i`; ya instalado → `-u`;
- checksum alterado → sin llamada `-i`/`-u` y retorno ≠0;
- `Id` distinto → sin instalación y retorno ≠0;
- `--version 0.2` → retorno 2 sin llamar a `curl`;
- `--version v0.2.43` → URL con `/releases/download/v0.2.43/`;
- `DRY_MODE=true` → `curl` no se llama;
- `current_uid` simulado a 0 → retorno 1;
- catálogo: con `kpackagetool6` en el PATH aparece `codexbar_plasma`; sin él, no.

---

## 8. Fases 4-10 (estado `Refinar`)

El agente **no** implementa estas fases directamente. Para cada una debe:
1. leer el código afectado;
2. proponer subtareas `T<n>.1…T<n>.k` con el mismo formato que las secciones 5-7 (objetivo, archivos, especificación, tests, verificación);
3. añadirlas a este SDD en una rama `docs/T<n>-refine`;
4. esperar aprobación humana.

### T4.x — Hardware probe

- **Entregables:** `src/hardware/{detect,platform,cpu,gpu,network,storage}.sh` y el comando `probe` (salida humana; `--format env` opcional).
- **Hechos mínimos:**
  - `platform.vendor`, `platform.product`;
  - `platform.form_factor` desde `/sys/class/dmi/id/chassis_type`: 8, 9, 10, 14, 30, 31, 32 → `portable`; 3-7, 13, 15, 16, 35, 36 → `desktop`; resto → `unknown`;
  - `battery.present` (`/sys/class/power_supply/BAT*`);
  - `cpu.vendor` (`vendor_id` de `/proc/cpuinfo`), `cpu.model`, `cpu.arch` (`uname -m`);
  - `gpu.intel`, `gpu.amd` y `gpu.nvidia` por vendor PCI `8086`/`1002`/`10de` en las clases `0300`, `0302` y `0380` (`lspci -nn`); `gpu.hybrid`;
  - `wifi.present`, `wifi.vendor`, `wifi.device_id` (`/sys/class/net/*/wireless` + `lspci -nn`); `bluetooth.present`;
  - `storage.root_fs` (`findmnt -no FSTYPE /`);
  - `bootloader.type` (reutiliza `detect_bootloader` de T1.5);
  - `desktop.session`, `desktop.kde`, `desktop.hyprland`;
  - `os.family` (reutiliza T2.1).
- Todas las fuentes se pueden sobrescribir con variables de entorno (`HW_SYSFS_ROOT`, `HW_LSPCI_FILE`, `HW_CPUINFO_FILE`) para los fixtures.
- **Aceptación:** un PC no Apple obtiene información útil y no solo `generic`.

### T5.x — Modelo de capacidades

- `get_bootstrap_checklist_items` decide la visibilidad por capacidades (`gpu.*`, `storage.root_fs`, `desktop.kde`, `wifi.present`, `battery.present`), no por `MACBOOK_MODEL`, salvo los bloques Apple (`mbpwatch`, `plasmoid`, `apple`, `facetime`).
- Considerar `chwd -a` como bloque `gpu_drivers` (ADR-001 D3).
- **Aceptación:** los tests de catálogo existentes siguen en verde y se añaden casos `AMD desktop` e `Intel+NVIDIA laptop`.

### T6.x — Perfiles Apple aislados

- Mover Broadcom, FaceTime HD, MBP Watch, el plasmoid MBP y los ajustes Apple a `src/hardware/profiles/apple/`.
- Renombrar la cara visible de MBP Watch a `hw-watch` (manteniendo alias `*-mbp-*` en la CLI).
- **Aceptación:** el core funciona sin conocer BCM43602, FaceTime HD ni MBP Watch.

### T7.x — Modularización de `bootstrap.sh`

- Dividir en `src/modules/{packages,kde,docker,node,zsh,ai_tools,browsers,wifi,btrfs}.sh` con el contrato de la sección 9.
- Mover las listas de paquetes a ficheros de datos `packages/<grupo>.txt`.
- **Aceptación:** `bootstrap.sh` queda como fachada de menos de 300 líneas y no se añaden funciones nuevas al monolito.

### T8.x — Configuración declarativa

- TOML leído con `tomllib` (Python ≥ 3.11) y exportado a bash como `KEY=VALUE` validado.
- Migración desde `linux-migration-tool.conf` (`source`) con aviso legacy; retirada del `source` solo en una versión que lo anuncie.
- Incluye overrides por equipo: `hosts/<HOST_LABEL>.toml` con bloques y paquetes extra.

### T9.x — Instaladores reproducibles

- Inventario de `curl | bash` (Oh My Zsh, NVM, bun, Claude, Antigravity).
- Sustitución por paquete o artefacto versionado cuando exista; documentación de las excepciones.
- Las URLs de Antigravity con build fija pasan a variables configurables con aviso si devuelven 404.

### T10.x — Fixtures hardware en CI

- Fixtures: MacBookPro12,1, MacBookPro8,1, Intel desktop, AMD desktop, NVIDIA desktop, Intel+NVIDIA laptop, Intel+AMD laptop.
- Cada fixture incluye DMI, `lspci -nn`, `findmnt`, batería e interfaces de red.

---

## 9. Contrato de módulos (aplica desde T7.x)

Cada módulo migrado expone, cuando aplique:

| Función | Responsabilidad | Restricciones |
|---|---|---|
| `<mod>_detect` | estado actual | no modifica el sistema |
| `<mod>_plan` | qué cambiaría y por qué (`acción<TAB>motivo`) | sin privilegios si es posible |
| `<mod>_apply` | aplica | idempotente, usa `run_cmd`, falla explícitamente |
| `<mod>_verify` | comprueba el resultado | no asume éxito por el código 0 de `apply` |

---

## 10. Comandos CLI objetivo

| Comando | Introducido en |
|---|---|
| `bootstrap --blocks a,b --list-blocks` | T1.3 |
| `backup` (formato v2, nombre con host) | T2.2 / T2.3 |
| `restore --external-to-original --fix-ownership` | T2.4 |
| `restic-backup maintenance` | T2.7 |
| `install-codexbar-plasma`, `uninstall-codexbar-plasma` | T3.1 |
| `probe` | T4.x |
| `plan`, `verify` | T7.x |

---

## 11. Seguridad (aplica a todas las tareas)

- Sin `eval`; sin `bash -c` con datos interpolados si existe alternativa con `run_cmd`.
- No registrar secretos: contraseñas, tokens y contenido de `restic-password` nunca van al log.
- No pasar contraseñas por argumentos de proceso.
- `rm -rf` solo sobre rutas construidas por el propio código y validadas (no vacías, no `/`, no `$HOME`).
- Las descargas de terceros siguen ADR-001 D5.

---

## 12. Idempotencia

Un segundo `apply` del mismo bloque no debe:
- reinstalar paquetes (`--needed`);
- duplicar líneas en ficheros de configuración (usar marcadores y comprobar antes de añadir);
- duplicar unidades systemd ni plasmoids;
- volver a descargar artefactos ya verificados e instalados con la misma versión.

Cada tarea que toca un bloque añade al menos un test de segunda ejecución cuando sea razonable.

---

## 13. Rollback

No hay rollback transaccional. Para cambios en ficheros de sistema o de usuario que la herramienta sobrescribe:
- copia `<fichero>.bak.<YYYYmmddHHMMSS>` antes de modificar (ya se hace en `limine.conf`; T1.4 lo aplica a `brave-flags.conf`);
- el log indica cómo revertir;
- los módulos con `uninstall` existente lo mantienen (MBP Watch, plasmoid MBP, CodexBar Plasma).

---

## 14. Criterios globales de aceptación

La refactorización se considera completa cuando:

1. un equipo CachyOS no Apple usa `bootstrap` sin depender de perfiles MacBook y sin instalar nada específico de Apple;
2. la CLI y las tres interfaces ejecutan exactamente los mismos bloques para la misma selección;
3. Intel/AMD/NVIDIA/híbridos se representan y se tratan correctamente (VA-API incluido);
4. un backup hecho en Debian o Fedora se restaura correctamente en CachyOS, y al revés (CI T2.6 en verde);
5. los backups se nombran `<equipo>_DD_MM_AAAA-HH:mm` (con el fallback documentado) y se listan por fecha real;
6. las configuraciones anidadas y los datos externos se restauran en la ruta correcta;
7. Restic funciona en las cuatro familias, con mantenimiento separado y rotación de logs;
8. CodexBar Plasma se instala desde una release verificada y se puede desinstalar;
9. existen `probe`, `plan` y `verify`;
10. la configuración no ejecuta shell arbitrario;
11. el CI cubre tests, sintaxis, ShellCheck, `tui.py`, roundtrip multi-distro y fixtures hardware;
12. CHANGELOG y README reflejan los cambios incompatibles.

---

## 15. Regla de mantenimiento de este SDD

- El diseño precede al código: si una tarea necesita cambiar el diseño, primero se actualiza este SDD (o el ADR) en la misma rama, en un commit separado `docs: update SDD-001 for T<id>`, y se detiene para revisión humana.
- Al completar una tarea, se marca en la tabla de la sección 4 con `Hecha (PR #N)`.
