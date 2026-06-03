# Contexto post-instalación para IA

El comando `export-ai-context` genera un resumen local del estado del sistema tras el bootstrap, pensado para pegarlo en un agente IA y acelerar diagnóstico o revisión final.

## Comando

```bash
./migration.sh export-ai-context
```

`postcheck` también lo genera automáticamente al final.

## Ficheros generados

Se escriben fuera del repositorio, en:

```text
~/.local/state/linux-migration-tool/
```

Ficheros:

- `postinstall-ai-context.txt` — versión completa
- `postinstall-ai-context.redacted.txt` — versión saneada para compartir con menos riesgo

## Qué incluye

- hostname y perfil hardware detectado
- kernel y tipo de sesión
- gateway por defecto, interfaz y DNS
- SSID actual y perfiles Wi-Fi guardados por NetworkManager
- estado de servicios como `docker`, `syncthing`, `talk2ai` y `codexbar-tray`
- presencia de paquetes relevantes como `markdownpart`, `filezilla` y `handy-bin`
- contenido en una sola línea de configuraciones útiles como:
  - `/etc/NetworkManager/conf.d/wifi_backend.conf`
  - `/etc/conf.d/wireless-regdom`
  - `~/.config/brave-flags.conf`
  - `~/.config/environment.d/vaapi.conf`

## Privacidad

El fichero completo contiene identificadores locales reales como hostname, DNS, gateway y SSIDs.

Si vas a pegarlo en una IA externa o compartirlo fuera de la máquina, usa preferentemente:

```text
postinstall-ai-context.redacted.txt
```
