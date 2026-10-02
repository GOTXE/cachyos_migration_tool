# ADR-001 — Arquitectura genérica para workstations CachyOS

**Estado:** Accepted  
**Fecha:** 2026-10-02  
**Ámbito:** arquitectura de bootstrap, migración y soporte hardware

## Contexto

CachyOS Migration Tool nació como una herramienta orientada al MacBook Pro 2015 y fue creciendo hasta incorporar backup/restore, bootstrap de desarrollo, herramientas IA, Docker, KDE/Hyprland, Restic y soporte específico Apple.

El objetivo actual es utilizar la misma herramienta en cualquier PC donde se instale CachyOS. El modelo actual basado principalmente en `MACBOOK_MODEL` no representa adecuadamente equipos Intel, AMD, NVIDIA, configuraciones híbridas, sobremesas, portátiles ni periféricos opcionales.

## Decisión

El núcleo evolucionará desde un modelo centrado en perfiles de equipos concretos hacia un modelo de:

```text
detección de sistema
        ↓
capacidades normalizadas
        ↓
perfiles específicos opcionales
        ↓
catálogo de acciones compatible
        ↓
plan / apply / verify
```

Los perfiles de hardware concretos seguirán existiendo únicamente para:

- workarounds de un modelo concreto;
- firmware específico;
- drivers no genéricos;
- ajustes de compatibilidad conocidos.

No se usarán como mecanismo principal para decidir el bootstrap general.

## Consecuencias

### Positivas

- soporte de PCs no Apple sin tratarlos como un único perfil `generic`;
- detección correcta de GPU Intel/AMD/NVIDIA e híbridas;
- menor acoplamiento entre hardware y módulos de software;
- tests reproducibles mediante fixtures;
- crecimiento del catálogo sin ampliar un único `bootstrap.sh`;
- posibilidad de ejecutar `probe`, `plan`, `apply` y `verify` de forma independiente.

### Costes

- migración incremental del código actual;
- periodo temporal con APIs antiguas y nuevas coexistiendo;
- necesidad de fixtures hardware;
- más contratos internos que documentar y validar.

## Compatibilidad

La transición conservará inicialmente:

- la CLI existente;
- `get_macbook_*`;
- perfiles `MacBookPro12,1` y `MacBookPro8,1`;
- backup/restore actuales;
- TUI Python, whiptail y modo texto.

Los wrappers legacy se retirarán sólo tras migrar todos sus consumidores y documentarlo en CHANGELOG.

## Decisiones relacionadas

El diseño detallado, contratos, fases, rollback y criterios de aceptación están definidos en:

`docs/architecture/SDD-001-generic-workstation-refactor.md`
