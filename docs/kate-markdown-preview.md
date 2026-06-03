# Kate y vista previa Markdown

`markdownpart` añade a Kate el componente necesario para renderizar la vista previa de documentos Markdown dentro del propio editor.

El bootstrap lo instala dentro del bloque `kde`, junto con `kate`.

## Instalación manual

En CachyOS / Arch:

```bash
sudo pacman -S markdownpart
```

También puede instalarse desde Discover.

## Activar la vista previa en Kate

1. Abre `Kate`.
2. Ve a `Preferencias` -> `Configurar Kate`.
3. En la barra lateral, entra en `Complementos`.
4. Marca `Vista previa del documento`.
5. Reinicia `Kate`.

Después de reiniciar, aparecerá en el lado derecho de la ventana un botón con un folio y una lupa. Al pulsarlo, Kate abrirá un panel lateral con el renderizado del Markdown.

## Uso recomendado

- Edita el `.md` en el panel principal.
- Activa la vista previa lateral para revisar títulos, listas, tablas y bloques de código.
- Si no aparece el botón tras instalar `markdownpart`, comprueba primero que el complemento siga marcado y reinicia Kate otra vez.
