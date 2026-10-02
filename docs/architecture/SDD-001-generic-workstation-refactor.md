# SDD-001 — Refactor genérico de CachyOS Migration Tool

**Estado:** Approved for phased implementation  
**Fecha:** 2026-10-02  
**ADR relacionado:** ADR-001  
**Objetivo:** convertir la herramienta actual en un bootstrap/migration tool reutilizable en workstations CachyOS heterogéneas sin rehacer el proyecto desde cero.

---

## 1. Objetivos

La implementación deberá:

1. detectar el hardware y estado del sistema de forma genérica;
2. expresar ese estado mediante capacidades normalizadas;
3. decidir qué bloques son compatibles según capacidades, no según nombres de modelo;
4. mantener perfiles específicos para excepciones reales de hardware;
5. conservar compatibilidad con la CLI actual durante la migración;
6. mantener `dry-run` como ruta de primer nivel;
7. mejorar idempotencia, testabilidad y trazabilidad;
8. reducir privilegios innecesarios;
9. separar configuración, detección, planificación y ejecución;
10. permitir validar lógica hardware sin disponer físicamente de cada equipo.

## 2. Fuera de alcance inicial

No forman parte de esta primera refactorización:

- soporte para distribuciones no Arch/CachyOS;
- sustitución completa de Bash por Python;
- gestión declarativa completa al estilo Ansible/Nix;
- automatización de particionado;
- instalación desatendida de CachyOS;
- gestión centralizada de múltiples PCs;
- inventario remoto;
- rollback transaccional completo de cambios de sistema.

Estas capacidades podrán abordarse después sin condicionar el diseño base.

---

## 3. Arquitectura objetivo

```text
                  ┌─────────────────┐
                  │   CLI / TUI      │
                  └────────┬────────┘
                           │
                  ┌────────▼────────┐
                  │  system probe    │
                  └────────┬────────┘
                           │
                ┌──────────▼──────────┐
                │ capability model     │
                └──────────┬──────────┘
                           │
             ┌─────────────▼─────────────┐
             │ optional hardware profiles │
             └─────────────┬─────────────┘
                           │
                    ┌──────▼──────┐
                    │   planner    │
                    └──────┬──────┘
                           │
                 ┌─────────▼─────────┐
                 │ selected modules   │
                 └─────────┬─────────┘
                           │
              ┌────────────▼────────────┐
              │ apply + per-module verify│
              └─────────────────────────┘
```

---

## 4. Estructura de código prevista

```text
src/
├── core/
│   ├── commands.sh
│   ├── config.sh
│   ├── logging.sh
│   ├── preflight.sh
│   └── planner.sh
├── hardware/
│   ├── detect.sh
│   ├── platform.sh
│   ├── cpu.sh
│   ├── gpu.sh
│   ├── network.sh
│   ├── storage.sh
│   └── profiles/
│       └── apple/
│           ├── mbp12_1.sh
│           └── mbp8_1.sh
├── modules/
│   ├── packages.sh
│   ├── kde.sh
│   ├── docker.sh
│   ├── node.sh
│   ├── zsh.sh
│   ├── ai_tools.sh
│   ├── browsers.sh
│   ├── wifi.sh
│   ├── btrfs.sh
│   └── backup/
└── main.sh
```

La migración será incremental. No es obligatorio alcanzar esta estructura de una sola vez.

---

## 5. Modelo de capacidades

### 5.1 Contrato conceptual

El sistema deberá poder representar como mínimo:

```text
platform.vendor
platform.product
platform.form_factor

cpu.vendor
cpu.model
cpu.arch

gpu.intel
gpu.amd
gpu.nvidia
gpu.hybrid

battery.present

wifi.present
wifi.vendor
wifi.device_id

bluetooth.present

storage.root_fs
storage.btrfs

desktop.session
desktop.kde
desktop.hyprland

bootloader.type

profile.apple
profile.id
```

### 5.2 Reglas

- Las capacidades deben representar hechos detectados, no decisiones de instalación.
- Una capacidad desconocida debe expresarse explícitamente como desconocida o ausente de forma segura.
- No se inferirá una capacidad crítica sólo por el nombre comercial del equipo.
- Los perfiles podrán añadir traits específicos, pero no sobrescribirán silenciosamente hechos detectados.
- Las funciones legacy `get_macbook_profile_*` actuarán como adaptadores durante la transición.

---

## 6. API interna prevista

### Plataforma

```text
get_system_vendor
get_system_product
detect_form_factor
has_battery
```

### CPU

```text
detect_cpu_vendor
detect_cpu_model
detect_cpu_arch
```

### GPU

```text
detect_gpu_capabilities
has_intel_gpu
has_amd_gpu
has_nvidia_gpu
has_hybrid_gpu
```

### Red

```text
detect_wifi_device
detect_wifi_vendor
detect_wifi_pci_id
has_bluetooth
```

### Storage/sistema

```text
detect_root_filesystem
detect_bootloader
detect_desktop_session
```

Estas funciones deberán ser puras o casi puras siempre que sea viable, para facilitar tests.

---

## 7. Perfiles específicos

Los perfiles específicos se usarán para excepciones.

### MacBookPro12,1

Conservará soporte para:

- Broadcom BCM43602;
- FaceTime HD PCIe;
- VA-API Broadwell;
- suspend workaround;
- MBP Watch;
- plasmoid KDE;
- ajustes Apple laptop.

### MacBookPro8,1

Conservará:

- ajustes Apple laptop;
- VA-API Sandy Bridge;
- compatibilidad específica ya documentada.

### Equipos genéricos

No tendrán un perfil obligatorio. El sistema utilizará capacidades detectadas.

---

## 8. Planner

Se introducirá progresivamente un planner que diferencie:

```text
detectado
compatible
seleccionado
pendiente
aplicado
verificado
```

Ejemplo:

```text
module: vaapi
compatible: true
reason: intel_gpu=true
selected: false
state: available
```

Esto permitirá que la TUI no replique reglas de hardware.

---

## 9. Contrato de módulos

Cuando un módulo se migre a la nueva arquitectura deberá, cuando sea aplicable, separar:

```text
detect()
plan()
apply()
verify()
```

### detect

Determina el estado actual.

No debe modificar el sistema.

### plan

Devuelve qué cambiaría y por qué.

Debe poder ejecutarse sin privilegios siempre que sea posible.

### apply

Realiza el cambio.

Debe:

- ser idempotente cuando sea razonable;
- solicitar privilegios sólo cuando sean necesarios;
- registrar lo ejecutado;
- fallar de forma explícita.

### verify

Comprueba que el resultado esperado existe.

No debe asumir que `apply` tuvo éxito sólo porque el comando devolvió 0.

---

## 10. CLI objetivo

La CLI existente se mantiene.

Se añadirán progresivamente:

```bash
./migration.sh probe
./migration.sh plan
./migration.sh verify
```

### probe

Salida humana por defecto y formato máquina opcional en una fase posterior.

### plan

Mostrará:

- capacidades detectadas;
- módulos compatibles;
- módulos seleccionados;
- cambios previstos;
- operaciones con sudo;
- operaciones de red.

### verify

Ejecutará verificaciones post-bootstrap y por módulo.

---

## 11. Configuración

### Estado actual

`linux-migration-tool.conf` se carga actualmente como código shell.

### Estado objetivo

La configuración debe tratarse como datos.

Se propone usar TOML por disponibilidad de `tomllib` en Python moderno.

Ejemplo:

```toml
country = "ES"

[features]
docker = true
node = true
restic = true
ai_tools = false

[backup]
include_repos = true
```

### Migración

1. mantener temporalmente el formato actual;
2. introducir lector declarativo;
3. advertir cuando se use configuración legacy;
4. documentar equivalencias;
5. retirar el `source` directo sólo en una versión que lo anuncie expresamente.

---

## 12. Privilegios

Regla principal:

> No se adquirirá una sesión sudo si la operación solicitada puede completarse como usuario.

Ejemplos:

- backup de HOME: sin sudo;
- inventario pacman: sin sudo;
- instalación de paquetes: sudo;
- escritura en `/etc`: sudo;
- systemd system: sudo;
- systemd user: usuario.

La aplicación debe evitar mantener sudo vivo durante acciones que no lo necesitan.

---

## 13. Seguridad

### Requisitos

- eliminar `eval` salvo necesidad demostrable;
- reducir uso de `bash -c` / `bash -lc`;
- evitar interpolación insegura de datos externos;
- no registrar secretos;
- no guardar contraseñas en argumentos de proceso cuando exista alternativa;
- validar rutas antes de operaciones destructivas;
- mantener `rm -rf` limitado a rutas construidas y verificadas;
- revisar progresivamente instaladores `curl | bash`.

### Instaladores remotos

Clasificación preferida:

1. paquete oficial;
2. AUR conocido;
3. descarga versionada/verificada;
4. instalador remoto sólo si no existe alternativa razonable.

---

## 14. Backup e inventario

Se unificará la generación de inventario del sistema.

Salida objetivo:

```text
metadata/
├── system.json
├── hardware.json
├── pacman-explicit.txt
├── aur-foreign.txt
├── flatpak.txt
├── vscode-extensions.txt
├── system-enabled-units.txt
└── user-enabled-units.txt
```

La misma lógica deberá reutilizarse desde:

- backup clásico;
- Restic;
- diagnóstico;
- contexto postinstall.

No deben existir implementaciones divergentes del mismo inventario.

---

## 15. Restore

### Requisitos

- no asumir que nombre de usuario == nombre de grupo;
- preservar/restablecer ownership de manera explícita;
- mantener normalización de permisos actual;
- conservar opción `--preserve-permissions`;
- validar backup antes de aplicar;
- registrar diferencias verificadas al terminar.

A medio plazo se añadirá un manifest versionado del formato de backup.

---

## 16. Logging y observabilidad

Todo cambio importante debe quedar registrado con:

- módulo;
- acción;
- comando cuando sea seguro mostrarlo;
- resultado;
- warning/error;
- ubicación del log.

No deben escribirse secretos en logs.

El formato humano actual puede mantenerse. Un formato estructurado será una mejora posterior.

---

## 17. Tests

### Unitarios shell

Cobertura mínima:

- detección GPU;
- catálogo por capacidades;
- perfiles MacBook legacy;
- permisos restore;
- selección de módulos;
- parsing de configuración;
- preflight.

### Fixtures

Se crearán fixtures para:

```text
MacBookPro12,1
MacBookPro8,1
Intel desktop
AMD desktop
NVIDIA desktop
Intel + NVIDIA laptop
Intel + AMD laptop
```

Cada fixture deberá describir entradas simuladas de:

- DMI;
- lspci;
- lsblk/findmnt;
- batería;
- interfaces de red.

### CI

Debe ejecutar como mínimo:

- tests del proyecto;
- `bash -n`;
- ShellCheck de severidad error.

Posteriormente:

- shfmt check;
- tests Python;
- fixtures hardware.

---

## 18. Idempotencia

Un segundo `apply` no debe:

- reinstalar innecesariamente paquetes;
- duplicar líneas de configuración;
- duplicar servicios;
- duplicar módulos systemd;
- romper archivos existentes;
- repetir descargas si el artefacto válido ya está presente.

Las excepciones se documentarán por módulo.

---

## 19. Manejo de errores

### Regla

Un módulo no debe convertir silenciosamente un error importante en éxito.

Se permitirá `|| true` únicamente para:

- consultas opcionales;
- limpieza best-effort;
- ausencia esperable;
- compatibilidad no crítica.

En operaciones de instalación/configuración, el fallo deberá propagarse o convertirse en warning explícito con estado no verificado.

---

## 20. Rollback

No habrá rollback transaccional general en esta fase.

Para cambios críticos:

- archivos de sistema modificados deberán tener backup previo cuando aplique;
- la operación deberá documentar cómo revertirse;
- módulos complejos deberán incluir función `uninstall` o `rollback` cuando ya exista soporte;
- restauraciones deberán seguir usando `dry-run` y verificación.

---

## 21. Fases de implementación

### Fase 1 — Correcciones y red de seguridad

Criterios:

- corregir catálogo GPU;
- sustituir `Syyu` por `Syu`;
- eliminar `eval` evitable;
- backup sin sudo global;
- inventario Arch en backup;
- ownership restore usando grupo real;
- CI;
- tests GPU.

**Estado:** implementado en la rama actual.

### Fase 2 — Hardware probe

Entregables:

- nuevo módulo `src/hardware/`;
- detección genérica de plataforma, CPU, GPU, batería, Wi-Fi y filesystem;
- comando `probe`;
- tests unitarios de cada detector.

Criterio de aceptación:

un PC no Apple debe obtener información útil sin caer únicamente en `generic`.

### Fase 3 — Capability model

Entregables:

- funciones de capacidades;
- adaptación del catálogo;
- compatibilidad con perfiles legacy.

Criterio:

las decisiones de catálogo ya no dependen directamente de `MACBOOK_MODEL`, salvo extensiones Apple específicas.

### Fase 4 — Perfiles hardware aislados

Entregables:

- mover lógica Apple específica a perfiles;
- mantener comportamiento MBP actual.

Criterio:

el core puede funcionar sin conocer BCM43602, FaceTime HD o MBP Watch.

### Fase 5 — Modularización de bootstrap

Entregables:

- dividir `bootstrap.sh`;
- reducir dependencias cruzadas;
- contratos detect/plan/apply/verify.

Criterio:

ningún módulo funcional nuevo importante se añade al monolito original.

### Fase 6 — Configuración declarativa

Entregables:

- TOML;
- parser/validador;
- compatibilidad legacy;
- tests.

### Fase 7 — Instaladores reproducibles

Entregables:

- inventario de `curl | bash`;
- alternativa por paquete o descarga versionada cuando exista;
- documentación de excepciones.

### Fase 8 — Fixtures hardware

Entregables:

- fixtures mínimos definidos en la sección de tests;
- CI sobre esos fixtures.

---

## 22. Criterios globales de aceptación

La refactorización se considerará completada cuando:

1. un equipo CachyOS no Apple pueda usar bootstrap sin depender de perfiles MacBook;
2. Intel/AMD/NVIDIA/híbridos se representen correctamente;
3. Apple siga funcionando mediante perfiles específicos;
4. el catálogo se derive de capacidades;
5. `probe`, `plan` y `verify` existan;
6. configuración ya no ejecute shell arbitrario;
7. inventario de backup/Restic esté unificado;
8. CI cubra sintaxis, ShellCheck y fixtures principales;
9. el bootstrap esté dividido en módulos mantenibles;
10. la documentación y CHANGELOG reflejen cambios incompatibles.

---

## 23. Regla de ejecución para próximas fases

Antes de modificar código de una fase nueva:

1. revisar este SDD;
2. actualizarlo si cambia el diseño;
3. añadir tests que expresen el comportamiento esperado;
4. implementar;
5. validar CI;
6. documentar la fase completada.

El diseño precede a cambios estructurales del código.
