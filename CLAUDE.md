# Claude Instructions

This file mirrors the mandatory publish policy in `AGENTS.md`; keep that
section synchronized with any future policy changes.

## Mandatory Publish Rule

- A partir de ahora esto es obligatorio: cuando un cambio ya esté validado y el usuario lo dé por bueno, no debe quedarse pendiente en el worktree "para luego" salvo que exista un acuerdo explícito de agruparlo con otros cambios inmediatos.
- Si no hay más cambios acordados para agrupar en ese mismo bloque de trabajo, el flujo obligatorio es: actualizar documentación necesaria, decidir bump de versión, `commit`, `push`, abrir `PR`, `merge`, crear `tag` y publicar `release`.
- Si el worktree contiene cambios mezclados de varios temas, primero hay que separar el alcance publicable y no publicar nada ambiguo o parcialmente revisado.
- `AGENTS.md` y `CLAUDE.md` deben mantenerse alineados en esta política. Cualquier cambio futuro en esta regla debe reflejarse en ambos archivos dentro del mismo trabajo.
