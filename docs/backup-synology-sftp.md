# Synology SFTP para backups Restic

Guia generica para preparar un Synology DSM como destino SFTP/SSH para backups cifrados con Restic desde una workstation Linux.

No guarda contrasenas SFTP en el PC. La autenticacion recomendada es con clave SSH dedicada y un usuario DSM con permisos limitados.

## Modelo

```text
Workstation Linux
  ~/.ssh/backup_sftp_ed25519
  ~/.ssh/config

Synology DSM
  usuario dedicado: backup_workstation
  carpeta compartida: backups
  subcarpeta Restic: backups/workstation-linux/restic
  authorized_keys: /var/services/homes/backup_workstation/.ssh/authorized_keys
```

En SFTP, la ruta visible puede ser distinta a la ruta real de DSM. Por ejemplo, una carpeta compartida puede verse como:

```text
/backups/workstation-linux/restic
```

aunque internamente viva bajo `/volume1/backups/...`.

## 1. Activar SFTP

En DSM:

```text
Control Panel > File Services > FTP > SFTP
Enable SFTP service
Port: 22 o un puerto dedicado
```

Recomendacion:

```text
LAN/VPN: permitido
Internet publico: evitar si es posible
```

Si se usa firewall de DSM, permitir ese puerto solo desde redes de confianza.

## 2. Activar home de usuarios

En DSM:

```text
Control Panel > User & Group > Advanced
Enable user home service
```

Esto crea homes bajo una ruta equivalente a:

```text
/var/services/homes/USER
```

En Synology suele ser un symlink hacia:

```text
/volume1/homes/USER
```

## 3. Crear usuario dedicado

En DSM:

```text
Control Panel > User & Group > User > Create
Username: backup_workstation
Description: Backup workstation Linux
Password: larga y unica
Group: users
```

Permisos recomendados:

```text
Shared folders:
  backups: Read/Write
  homes: default
  resto: No access

Applications:
  SFTP/FTP: Allow
  DSM admin apps: Deny si DSM lo permite
```

No usar un usuario personal ni un admin principal para backups automaticos.

## 4. Crear carpeta de backup

En DSM:

```text
Control Panel > Shared Folder > Create
Name: backups
Filesystem: Btrfs si esta disponible
Recycle Bin: opcional
Encryption: opcional; Restic ya cifra el contenido
```

Dentro de la carpeta compartida, crear una subcarpeta para el equipo:

```text
backups/workstation-linux/restic
```

Permisos:

```text
backup_workstation: Read/Write
otros usuarios: No access
admins: Read/Write opcional
```

Si DSM ofrece snapshots o snapshots inmutables, activarlos para la carpeta `backups`. Para este uso suele bastar una retencion corta y frecuente:

```text
cada 1h o 2h
24-48 snapshots recientes
```

## 5. Generar clave SSH en el PC

En la workstation:

```bash
ssh-keygen -t ed25519 -f ~/.ssh/backup_sftp_ed25519 -C "backup_workstation@workstation-linux"
chmod 700 ~/.ssh
chmod 600 ~/.ssh/backup_sftp_ed25519
chmod 644 ~/.ssh/backup_sftp_ed25519.pub
```

La clave privada se queda en el PC. En DSM solo se copia la clave publica.

## 6. Instalar authorized_keys en Synology

Entrar en DSM por SSH con un usuario administrador y preparar el home del usuario de backup:

```bash
sudo -i
mkdir -p /var/services/homes/backup_workstation/.ssh
touch /var/services/homes/backup_workstation/.ssh/authorized_keys
```

Pegar la clave publica del PC en:

```text
/var/services/homes/backup_workstation/.ssh/authorized_keys
```

El archivo debe contener una linea tipo:

```text
ssh-ed25519 AAAA... backup_workstation@workstation-linux
```

Corregir propietario y permisos:

```bash
chown backup_workstation:users /var/services/homes/backup_workstation
chown -R backup_workstation:users /var/services/homes/backup_workstation/.ssh

chmod 755 /var/services/homes/backup_workstation
chmod 700 /var/services/homes/backup_workstation/.ssh
chmod 600 /var/services/homes/backup_workstation/.ssh/authorized_keys
```

## 7. Validacion critica en Synology

Este paso es importante. El propio usuario de backup debe poder leer su `authorized_keys`:

```bash
sudo -u backup_workstation sh -c 'id; ls -l /var/services/homes/backup_workstation/.ssh/authorized_keys; test -r /var/services/homes/backup_workstation/.ssh/authorized_keys; echo exit=$?'
```

Resultado correcto:

```text
exit=0
```

Si devuelve `Permission denied` o `exit=1`, SSH no aceptara la clave aunque root vea permisos aparentemente correctos.

Comprobar ruta real y permisos:

```bash
id backup_workstation
grep '^backup_workstation:' /etc/passwd /etc/passwd- 2>/dev/null || true

ls -ld /var/services
ls -ld /var/services/homes
ls -ld /var/services/homes/backup_workstation
ls -ld /var/services/homes/backup_workstation/.ssh
ls -l /var/services/homes/backup_workstation/.ssh/authorized_keys

ls -ld /volume*/homes 2>/dev/null
ls -ld /volume*/homes/backup_workstation 2>/dev/null
ls -ld /volume*/homes/backup_workstation/.ssh 2>/dev/null
ls -l /volume*/homes/backup_workstation/.ssh/authorized_keys 2>/dev/null
```

Si DSM aplica ACL raras, revisar:

```bash
synoacltool -get /var/services/homes/backup_workstation 2>/dev/null
synoacltool -get /var/services/homes/backup_workstation/.ssh 2>/dev/null
synoacltool -get /var/services/homes/backup_workstation/.ssh/authorized_keys 2>/dev/null
```

## 8. Correccion si el usuario no puede leer authorized_keys

Si esta prueba:

```bash
sudo -u backup_workstation sh -c 'test -r /var/services/homes/backup_workstation/.ssh/authorized_keys; echo exit=$?'
```

devuelve:

```text
exit=1
```

o aparece `Permission denied`, aplicar la correccion sobre la ruta real de homes de Synology. Normalmente `/var/services/homes` apunta a `/volume1/homes`, pero puede ser otro volumen.

Primero localizar la ruta:

```bash
ls -ld /var/services/homes
ls -ld /volume*/homes 2>/dev/null
ls -ld /volume*/homes/backup_workstation 2>/dev/null
```

Luego corregir permisos sobre la ruta real:

```bash
sudo -i

chown backup_workstation:users /volume1/homes/backup_workstation
chown -R backup_workstation:users /volume1/homes/backup_workstation/.ssh

chmod 711 /volume1/homes
chmod 755 /volume1/homes/backup_workstation
chmod 700 /volume1/homes/backup_workstation/.ssh
chmod 600 /volume1/homes/backup_workstation/.ssh/authorized_keys
```

Si el home esta en otro volumen, cambiar `/volume1/homes` por la ruta detectada.

Volver a validar:

```bash
sudo -u backup_workstation sh -c 'id; ls -l /var/services/homes/backup_workstation/.ssh/authorized_keys; cat /var/services/homes/backup_workstation/.ssh/authorized_keys >/dev/null; test -r /var/services/homes/backup_workstation/.ssh/authorized_keys; echo exit=$?'
```

Resultado correcto:

```text
exit=0
```

Despues probar desde el PC:

```bash
printf 'pwd\nls\nbye\n' | sftp -o BatchMode=yes backup-sftp-lan
```

## 9. Config SSH en el PC

Editar `~/.ssh/config`:

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
Port
User
IdentityFile
```

## 10. Aceptar host key

Primera conexion:

```bash
ssh-keyscan -p PORT SFTP_LAN_HOST >> ~/.ssh/known_hosts
chmod 600 ~/.ssh/known_hosts
```

Alternativamente, conectar una vez de forma interactiva y aceptar la huella si coincide con el servidor esperado.

## 11. Probar SFTP por clave

Desde el PC:

```bash
printf 'pwd\nls\nbye\n' | sftp -o BatchMode=yes backup-sftp-lan
```

Resultado esperado:

```text
Connected to backup-sftp-lan.
sftp> pwd
Remote working directory: /
sftp> ls
...
```

Probar la carpeta Restic:

```bash
printf 'ls backups/workstation-linux/restic\nbye\n' | sftp -o BatchMode=yes backup-sftp-lan
```

La ruta exacta depende de como DSM exponga la carpeta compartida por SFTP. Usar la ruta que aparezca en `ls`.

## Nota sobre SSH shell

Puede ocurrir que:

```bash
ssh backup-sftp-lan 'echo ok'
```

falle, pero:

```bash
sftp backup-sftp-lan
```

funcione. Para Restic por SFTP esto es suficiente. Lo importante es que SFTP conecte por clave y pueda listar/escribir la carpeta del repositorio.

## Checklist

- [ ] SFTP habilitado en DSM.
- [ ] User Home Service habilitado.
- [ ] Usuario dedicado creado.
- [ ] Carpeta compartida de backups creada.
- [ ] Subcarpeta `workstation-linux/restic` creada.
- [ ] Usuario dedicado tiene Read/Write en la carpeta de backups.
- [ ] Clave publica instalada en `authorized_keys`.
- [ ] `authorized_keys` es legible por el propio usuario (`exit=0`).
- [ ] `~/.ssh/config` tiene aliases LAN/remoto.
- [ ] `sftp -o BatchMode=yes backup-sftp-lan` conecta.
- [ ] La ruta del repo Restic es visible desde SFTP.
