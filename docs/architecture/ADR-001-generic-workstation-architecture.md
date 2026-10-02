# ADR-001 — Arquitectura genérica para workstations CachyOS

**Estado:** Accepted (revisado 2026-10-02)  
**Fecha original:** 2026-10-02  
**Ámbito:** bootstrap, catálogo de bloques, soporte hardware, instaladores remotos  
**Relacionados:** ADR-002 (formato de backup portable), SDD-001 (plan de implementación)

## Contexto

CachyOS Migration Tool nació para un MacBook Pro 2015 (`MacBookPro12,1`) y creció hasta incluir backup/restore, bootstrap de desarrollo, herramientas IA, Docker, KDE/Hyprland, Restic y soporte Apple específico.

El objetivo ahora es usar la misma herramienta en cualquier PC con CachyOS. Hoy eso no es posible de forma segura porque:

1. **Las decisiones dependen del nombre del modelo** (`MACBOOK_MODEL`). Cualquier equipo que no sea uno de los dos MacBook cae en un perfil `generic` que no distingue Intel/AMD/NVIDIA/híbridas, portátil/sobremesa, bootloader ni sistema de ficheros.
2. **El catálogo de bloques existe en tres sitios** que ya divergen:
   - `get_bootstrap_checklist_items` (`src/lib/common.sh`) — lo que la TUI muestra;
   - `tui_bootstrap_run` (`src/lib/tui.sh`) — lo que la TUI ejecuta;
   - `bootstrap_cachyos` (`src/modules/bootstrap.sh`) — lo que ejecuta la CLI.
   Consecuencia: `./migration.sh bootstrap` instala MBP Watch (daemon root) y todas las herramientas IA en cualquier PC, ignorando el catálogo filtrado por hardware.
3. **Algunas reglas hardware son incorrectas fuera del MacBook**, por ejemplo VA-API: para cualquier Intel se fuerza `libva-intel-driver` (i965) con `LIBVA_DRIVER_NAME=i965`. Intel archivó i965 el 31-01-2025; `intel-media-driver` (iHD) cubre de Broadwell en adelante.
4. **Snapshots BTRFS** instalan `grub-btrfs` sin mirar el bootloader, mientras el propio código edita `/boot/limine.conf`.

## Decisión

### D1 — Modelo por capacidades

El núcleo pasa de "perfil por modelo" a:

~~~text
probe (hechos detectados)
        ↓
capacidades normalizadas
        ↓
perfiles hardware opcionales (solo excepciones)
        ↓
catálogo de bloques compatible
        ↓
plan → apply → verify
~~~

Los perfiles concretos (`mbp12_1`, `mbp8_1`, futuros) solo se usan para workarounds de modelo, firmware específico, drivers no genéricos y ajustes conocidos. **Nunca** como mecanismo principal del bootstrap general.

### D2 — Una única fuente de verdad para los bloques

Existirá un único registro de bloques (id, etiqueta, valor por defecto, regla de visibilidad, función). La TUI Python, la TUI whiptail, el menú de texto y la CLI **leen y ejecutan** desde ese registro. Ninguna interfaz replica reglas hardware ni listas de bloques.

Cambio de comportamiento aceptado: `./migration.sh bootstrap` sin `--blocks` ejecutará los bloques **visibles y marcados por defecto** del catálogo, no "todo". Se documenta como cambio incompatible en CHANGELOG.

### D3 — Delegar drivers genéricos en CachyOS

Para drivers de GPU genéricos se prefiere la herramienta de la distribución (`chwd -a`) frente a reimplementar la lógica. La herramienta solo gestiona lo que `chwd` no cubre (workarounds Apple, Broadcom, FaceTime HD, flags de navegador, VA-API específico de perfil).

### D4 — Alcance por distribución

- **Bootstrap**: solo Arch/CachyOS (pacman + AUR). En otras distribuciones el comando falla con un mensaje claro, sin ejecutar nada.
- **Backup, restore y Restic**: portables (Arch, Debian/Ubuntu, Fedora/RHEL, openSUSE y derivadas). Ver ADR-002.
- **Integraciones de escritorio por usuario** que no usan el gestor de paquetes (p. ej. un plasmoid instalado con `kpackagetool6`) pueden funcionar en cualquier distro con KDE Plasma 6.

### D5 — Política de instaladores remotos

Orden de preferencia para instalar software de terceros:

1. paquete del repositorio oficial;
2. AUR conocido;
3. artefacto de release **versionado y verificado** (checksum publicado por el proyecto + validación del contenido);
4. `curl | bash` solo si no existe alternativa razonable, documentado como excepción.

Primer caso que aplica el nivel 3: **CodexBar Plasma** (`Lucenx9/codexbar-plasma`), instalado desde el asset `codexbar-plasma.plasmoid` de la release, verificando `codexbar-plasma.plasmoid.sha256` y el `KPlugin.Id` del paquete antes de llamar a `kpackagetool6`. No se usa el instalador `curl … | bash` del README del proyecto.

### D6 — Mínimo privilegio

No se pide sudo si la operación puede completarse como usuario: backup de HOME, inventario de paquetes, restore en HOME, plasmoids y unidades systemd `--user` se ejecutan sin sudo.

## Consecuencias

### Positivas

- PCs no Apple soportados sin tratarlos como un único `generic`;
- detección correcta de GPU Intel/AMD/NVIDIA e híbridas;
- la CLI y las TUI hacen exactamente lo mismo;
- menos acoplamiento hardware ↔ módulos de software;
- tests reproducibles mediante fixtures (DMI, `lspci`, `os-release`, etc.);
- el backup sirve para migrar desde/hacia equipos no Arch.

### Costes

- migración incremental con APIs antiguas y nuevas coexistiendo;
- cambio incompatible en la CLI `bootstrap` (D2);
- necesidad de mantener fixtures hardware y de distribución;
- más contratos internos que documentar y validar.

## Compatibilidad

Se conserva durante la transición:

- todos los comandos CLI existentes (la semántica de `bootstrap` cambia según D2);
- `get_macbook_*` como adaptadores;
- perfiles `MacBookPro12,1` y `MacBookPro8,1` con su comportamiento actual;
- lectura de backups en formato antiguo (v1, `linux_backup_*`), según ADR-002;
- TUI Python, whiptail y modo texto.

Los wrappers legacy se retiran solo cuando ningún consumidor los use y se anuncie en CHANGELOG.

## Referencias

- Plan, contratos, tareas y criterios de aceptación: `docs/architecture/SDD-001-generic-workstation-refactor.md`
- Formato de backup portable y nombre de carpetas: `docs/architecture/ADR-002-portable-backup-format.md`
