# Backup Restic por SFTP/SSH

Guia para preparar un destino de backup accesible por SFTP/SSH antes de instalar la logica de backup en el PC.

El destino puede ser un NAS, un servidor Linux, un mini PC, una VM o cualquier equipo que admita SFTP/SSH. El objetivo es usar un usuario dedicado, una clave SSH generada en el PC y un repositorio Restic cifrado en una ruta remota.

## Modelo recomendado

```text
PC CachyOS
  ~/.ssh/backup_sftp_ed25519
  ~/.ssh/config
  ~/.config/cachyos-migration-tool/backup.env
  ~/.config/cachyos-migration-tool/restic-password

Servidor SFTP/SSH
  usuario: backup_workstation
  ruta base: /srv/backups/workstation-linux
  repositorio: /srv/backups/workstation-linux/restic
  clave publica: ~/.ssh/authorized_keys
```

La clave privada no sale del PC. El servidor remoto solo recibe la clave publica.

## 1. Crear ruta remota de backup

En un servidor Linux generico:

```bash
sudo mkdir -p /srv/backups/workstation-linux/restic
sudo chown -R backup_workstation:backup_workstation /srv/backups/workstation-linux
sudo chmod -R 700 /srv/backups/workstation-linux
```

En un NAS, crea una carpeta compartida o directorio equivalente y deja que el usuario dedicado tenga lectura/escritura solo sobre esa ubicacion. Ejemplo conceptual:

```text
Name: backups
Path: /srv/backups/workstation-linux/restic
Access: backup_workstation Read/Write
Other users: No access
Encryption: opcional; Restic ya cifra el contenido antes de enviarlo
```

Si el destino permite snapshots o proteccion inmutable, activarlo sobre la carpeta/ruta de backups:

```text
Schedule: cada 1h o cada 2h
Retention: 24-48 snapshots recientes
```

Esta capa protege contra borrado o corrupcion del repositorio de backup desde el PC.

## 2. Crear usuario dedicado

En un servidor Linux:

```bash
sudo useradd --create-home --shell /bin/bash backup_workstation
sudo passwd backup_workstation
```

En un NAS, crea un usuario equivalente:

```text
Username: backup_workstation
Description: Backup workstation Linux
Password: larga y unica
```

Permisos:

```text
Ruta de backup: Read/Write
Resto de carpetas: No access
SFTP/SSH: Allow
Otros servicios: Deny si el sistema permite limitarlo
```

No meter `backup_workstation` en grupos administradores salvo que sea imprescindible para que el servidor permita SFTP/SSH en esa instalacion concreta.

## 3. Generar la clave SSH en el PC

En CachyOS:

```bash
ssh-keygen -t ed25519 -f ~/.ssh/backup_sftp_ed25519 -C "backup_workstation@workstation-linux"
chmod 700 ~/.ssh
chmod 600 ~/.ssh/backup_sftp_ed25519
chmod 644 ~/.ssh/backup_sftp_ed25519.pub
```

Para backups automaticos con `systemd`, lo mas simple es generar esta clave sin passphrase y limitar mucho el usuario remoto. Si se usa passphrase, habra que gestionar `ssh-agent` o desbloqueo manual.

## 4. Instalar la clave publica en el usuario remoto

Primero prueba login por contrasena:

```bash
ssh backup_workstation@SFTP_LAN_HOST
```

Si entra como `backup_workstation`, ejecuta en el servidor remoto:

```bash
mkdir -p ~/.ssh
chmod 700 ~/.ssh
touch ~/.ssh/authorized_keys
chmod 600 ~/.ssh/authorized_keys
```

Desde el PC, copia la clave publica:

```bash
cat ~/.ssh/backup_sftp_ed25519.pub | ssh backup_workstation@SFTP_LAN_HOST 'cat >> ~/.ssh/authorized_keys'
```

Vuelve a confirmar permisos dentro del servidor remoto:

```bash
chmod 700 ~/.ssh
chmod 600 ~/.ssh/authorized_keys
```

Si `backup_workstation` no puede abrir shell pero si existe el usuario, entra con un usuario administrador y prepara el home manualmente segun la ruta de homes del sistema:

```bash
sudo -i
mkdir -p ~backup_workstation/.ssh
printf '%s\n' 'PEGAR_AQUI_LA_CLAVE_PUBLICA' >> ~backup_workstation/.ssh/authorized_keys
chown -R backup_workstation:backup_workstation ~backup_workstation/.ssh
chmod 700 ~backup_workstation/.ssh
chmod 600 ~backup_workstation/.ssh/authorized_keys
```

## 5. Crear la carpeta del repositorio Restic

En el servidor remoto:

```bash
mkdir -p /srv/backups/workstation-linux/restic
chown -R backup_workstation:backup_workstation /srv/backups/workstation-linux
chmod -R 700 /srv/backups/workstation-linux
```

Si el destino es un NAS, puede crearse desde su gestor de archivos:

```text
backups/workstation-linux/restic
```

Despues revisa que `backup_workstation` tenga lectura y escritura sobre esa ruta.

## 6. Configurar aliases SSH en el PC

Editar `~/.ssh/config` y anadir:

```sshconfig
Host backup-sftp-lan
    HostName SFTP_LAN_HOST
    User backup_workstation
    Port 22
    IdentityFile ~/.ssh/backup_sftp_ed25519
    IdentitiesOnly yes
    BatchMode yes
    ConnectTimeout 8
    ServerAliveInterval 30
    ServerAliveCountMax 3

Host backup-sftp-remote
    HostName SFTP_REMOTE_HOST
    User backup_workstation
    Port 22
    IdentityFile ~/.ssh/backup_sftp_ed25519
    IdentitiesOnly yes
    BatchMode yes
    ConnectTimeout 8
    ServerAliveInterval 30
    ServerAliveCountMax 3
```

Cambiar:

```text
SFTP_LAN_HOST
SFTP_REMOTE_HOST
Port 22 si el SFTP usa otro puerto
```

Recomendacion: el host remoto deberia ser una IP/hostname accesible por VPN, Tailscale o WireGuard. Evitar exponer SSH/SFTP directamente a Internet.

## 7. Probar SFTP por clave

Desde el PC:

```bash
ssh backup-sftp-lan 'echo ok'
sftp backup-sftp-lan
```

Dentro de `sftp`:

```sftp
ls /srv/backups/workstation-linux/restic
quit
```

Probar tambien el fallback remoto cuando la VPN este activa:

```bash
ssh backup-sftp-remote 'echo ok'
sftp backup-sftp-remote
```

## 8. Variables de entorno para el futuro script

Usar la plantilla:

```bash
mkdir -p ~/.config/cachyos-migration-tool
cp docs/backup-restic.env.example ~/.config/cachyos-migration-tool/backup.env
chmod 600 ~/.config/cachyos-migration-tool/backup.env
```

Editar:

```bash
$EDITOR ~/.config/cachyos-migration-tool/backup.env
```

El archivo define:

```text
BACKUP_SFTP_HOST_LAN
BACKUP_SFTP_HOST_REMOTE
BACKUP_SFTP_REPOSITORY_PATH
RESTIC_REPOSITORY_LAN
RESTIC_REPOSITORY_REMOTE
RESTIC_PASSWORD_FILE
BACKUP_EXCLUDES_FILE
RESTIC_KEEP_HOURLY
RESTIC_KEEP_DAILY
RESTIC_KEEP_WEEKLY
RESTIC_KEEP_MONTHLY
```

No guardar contrasenas SFTP en `.env`.

## 9. Password de cifrado Restic

Cuando Restic este instalado en el PC:

```bash
mkdir -p ~/.config/cachyos-migration-tool
openssl rand -base64 32 > ~/.config/cachyos-migration-tool/restic-password
chmod 600 ~/.config/cachyos-migration-tool/restic-password
```

Guardar esta password fuera del PC, por ejemplo en un gestor de contrasenas. Sin ella no se puede restaurar el backup.

## 10. Logica LAN/remoto esperada

El futuro script del PC deberia:

```text
1. Cargar ~/.config/cachyos-migration-tool/backup.env
2. Probar backup-sftp-lan con ssh -o BatchMode=yes
3. Si responde, usar RESTIC_REPOSITORY_LAN
4. Si no responde, probar backup-sftp-remote
5. Si responde, usar RESTIC_REPOSITORY_REMOTE
6. Si ninguno responde, salir sin backup y dejar log claro
```

Comandos de prueba:

```bash
ssh -o BatchMode=yes backup-sftp-lan 'echo lan-ok'
ssh -o BatchMode=yes backup-sftp-remote 'echo remote-ok'
```

## Checklist antes de volver al PC

- [ ] SFTP/SSH habilitado en el destino remoto.
- [ ] Usuario `backup_workstation` creado.
- [ ] Ruta de backup creada.
- [ ] Ruta `/srv/backups/workstation-linux/restic` creada o adaptada al destino.
- [ ] `backup_workstation` tiene Read/Write solo en la ruta de backup.
- [ ] Clave publica del PC instalada en `authorized_keys`.
- [ ] Permisos `.ssh` revisados: directorio `700`, archivo `600`.
- [ ] `~/.ssh/config` del PC tiene `backup-sftp-lan` y `backup-sftp-remote`.
- [ ] `ssh backup-sftp-lan 'echo ok'` funciona.
- [ ] `sftp backup-sftp-lan` lista la ruta del repo.
- [ ] Snapshots o proteccion inmutable configurada en el destino, si esta disponible.
