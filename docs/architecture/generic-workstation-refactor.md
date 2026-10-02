# ADR: Generalizar CachyOS Migration Tool a workstations heterogéneas

**Estado:** Accepted for implementation  
**Fecha:** 2026-10-02

## Contexto

El proyecto nació para migrar y mantener un MacBook Pro 2015 con CachyOS. Con el tiempo ha incorporado backup/restore, bootstrap de desarrollo, herramientas IA, Docker, KDE/Hyprland, Restic y soporte específico Apple.

El objetivo actual es reutilizar la misma herramienta en cualquier PC donde se instale CachyOS. El diseño basado principalmente en `MACBOOK_MODEL` no representa correctamente equipos Intel, AMD, NVIDIA, híbridos, sobremesa/portátil ni periféricos opcionales.

## Decisión

El núcleo evolucionará desde perfiles centrados en un modelo concreto hacia **detección de capacidades + perfiles opcionales**.

Los perfiles específicos de hardware seguirán existiendo para workarounds que realmente dependan de un modelo, pero no decidirán la configuración general del sistema.

### Modelo objetivo

```text
system probe
    |
    +-- platform: vendor, product, laptop/desktop
    +-- cpu: vendor/family
    +-- gpu: intel, amd, nvidia, hybrid
    +-- network: wifi chipset/capabilities
    +-- storage: filesystem
    +-- desktop/session
    +-- special capabilities
            |
            v
      capability set
            |
            v
      bootstrap catalog
            |
            v
       plan / apply
            |
            v
          verify
```

Ejemplo conceptual:

```text
platform.vendor=GEEKOM
platform.product=Mini IT13
platform.form_factor=desktop
cpu.vendor=intel
gpu.intel=true
gpu.amd=false
gpu.nvidia=false
battery=false
wifi=true
filesystem=btrfs
profile.apple=false
```

## Principios

1. Las funciones genéricas no deben depender de nombres MacBook.
2. Las opciones del bootstrap se muestran por capacidad detectada.
3. Los workarounds de un modelo permanecen aislados en perfiles específicos.
4. Todas las operaciones deben ser idempotentes cuando sea razonable.
5. `sudo` se solicita únicamente para la operación que lo necesita.
6. `dry-run` debe seguir siendo una ruta de primer nivel.
7. La detección hardware debe poder probarse mediante fixtures sin hardware físico.
8. Los instaladores remotos deben tender a versiones verificables/reproducibles.
9. Configuración, estado detectado y lógica ejecutable deben quedar separados.

## Estructura objetivo

```text
src/
├── core/
│   ├── commands.sh
│   ├── config.sh
│   ├── logging.sh
│   └── preflight.sh
├── hardware/
│   ├── detect.sh
│   ├── cpu.sh
│   ├── gpu.sh
│   ├── network.sh
│   ├── storage.sh
│   └── profiles/
│       └── apple/
├── modules/
│   ├── packages.sh
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

No se hará un rewrite completo. La migración será incremental para conservar el comportamiento validado.

## Fases

### Fase 1 — Correcciones y red de seguridad

- corregir detección del catálogo para `amd-only` y `nvidia-only`
- representar correctamente GPU híbrida
- eliminar `eval` evitable
- evitar refresh completo `pacman -Syyu` cuando `-Syu` es suficiente
- eliminar sudo global del backup
- exportar inventario Arch desde el backup normal
- restaurar ownership usando el grupo primario real
- añadir CI y tests de perfiles GPU

### Fase 2 — Hardware probe

Crear API estable de detección:

```text
get_system_vendor
get_system_product
detect_form_factor
has_battery
detect_cpu_vendor
detect_gpu_capabilities
detect_wifi_device
detect_root_filesystem
```

Mantener temporalmente las funciones `get_macbook_*` como compatibilidad.

### Fase 3 — Perfiles específicos

Mover Apple/MBP a perfiles específicos y evitar referencias MBP desde el core.

El perfil `MacBookPro12,1` conservará:

- BCM43602
- FaceTime HD
- Broadwell VA-API
- MBP Watch/plasmoid cuando se seleccione

### Fase 4 — Modularización del bootstrap

Dividir `src/modules/bootstrap.sh` en módulos funcionales manteniendo la CLI actual.

Cada módulo nuevo deberá separar:

```text
detect
plan
apply
verify
```

cuando resulte aplicable.

### Fase 5 — Configuración declarativa

Sustituir progresivamente el `source` directo de `linux-migration-tool.conf` por una configuración tratada como datos y validada.

Se mantendrá una transición compatible para instalaciones existentes.

### Fase 6 — Instalaciones reproducibles

Revisar los flujos `curl | bash` y clasificarlos:

- paquete oficial/AUR preferente
- descarga versionada/verificada
- instalador remoto sólo cuando no exista alternativa razonable

Registrar versiones instaladas en el inventario.

### Fase 7 — Fixtures hardware

Añadir fixtures para, al menos:

- MacBookPro12,1
- MacBookPro8,1
- Intel desktop
- AMD desktop
- NVIDIA desktop
- Intel + NVIDIA laptop
- Intel + AMD laptop

## Cambios aplicados en la Fase 1

Esta rama comienza la transición sin cambiar la interfaz pública:

- el catálogo reconoce `amd-only` y `nvidia-only`
- equipos híbridos muestran las capacidades relevantes de Intel y GPU discreta
- el HOME de usuarios Plasma se resuelve mediante `getent`, sin `eval`
- la actualización normal usa `pacman -Syu`
- el backup normal deja de requerir una sesión sudo global
- el backup exporta `pacman -Qqe` y `pacman -Qqm`
- restore usa `id -un` + `id -gn`
- CI ejecuta tests, validación sintáctica y ShellCheck a severidad error

## Compatibilidad

La CLI actual y los perfiles MacBook existentes permanecen disponibles durante la refactorización. Los cambios incompatibles requerirán ADR/CHANGELOG y una transición explícita.
