# Firmware Wi-Fi BCM43602 (MacBookPro12,1)

El directorio `firmware/brcm/` contiene el bundle local del firmware Broadcom BCM43602 necesario para el adaptador Wi-Fi del MacBook Pro Retina 13" 2015.

## Por qué existe

El objetivo es no depender de conexión Wi-Fi durante el post-install de CachyOS. Si el firmware no estuviera empaquetado aquí, el bootstrap no podría descargar nada hasta tener red, creando un huevo/gallina.

## Archivos del bundle

```text
firmware/brcm/
├── brcmfmac43602-pcie.bin                          # driver binario principal
├── brcmfmac43602-pcie.bin.zst                      # ídem comprimido (kernels modernos)
├── brcmfmac43602-pcie.txt                          # NVRAM genérico
└── brcmfmac43602-pcie.Apple Inc.-MacBookPro12,1.txt  # NVRAM específico del modelo
```

Los blobs `clm_blob` y `txcap_blob` no están incluidos en el repo (tamaño/licencia). Si faltan, el chip funciona con limitaciones de canales y cobertura.

## Suspensión y pérdida del escaneo

En el MacBookPro12,1 el BCM43602 puede fallar al suspender. La evidencia observada
en `journalctl -k` es:

```text
brcm_pcie_pm_enter_D3 returns -5
Failed to reserve space in commonring
brcmf_cfg80211_scan: scan error (-12)
```

Después de este fallo, NetworkManager puede seguir mostrando `wlan0`, pero el
driver ya no responde a escaneos ni a comandos del firmware. Un reinicio recupera
el dispositivo porque reinicializa el chip.

El bootstrap instala el hook:

```text
/usr/lib/systemd/system-sleep/brcmfmac-apple
```

Este hook apaga el Wi-Fi y descarga `brcmfmac` antes de suspender, y lo vuelve a
cargar al reanudar. La corrección debe validarse suspendiendo y reanudando, y
después ejecutando:

```bash
nmcli device wifi list --rescan yes
```

No se debe recargar `brcmfmac` mientras NetworkManager está gestionando `wlan0`
fuera de este flujo, porque puede producir el mismo estado bloqueado.

## Cómo se actualiza el bundle

```bash
sudo bash src/tools/extract_bcm43602_bundle.sh [MODELO_APPLE]
```

El script (`src/tools/extract_bcm43602_bundle.sh`) copia desde el sistema actual los archivos que encuentre bajo `/usr/lib/firmware/brcm/` o `/lib/firmware/brcm/`. También acepta rutas de macOS (`/System/Library/Extensions/IO80211Family.kext/...`).

El modelo por defecto es `MacBookPro12,1`. Se puede pasar otro como argumento:

```bash
bash src/tools/extract_bcm43602_bundle.sh MacBookPro11,4
```

Al terminar imprime un resumen de archivos copiados, ya presentes y faltantes.

## Integración con el bootstrap

El módulo de backup (`src/modules/backup.sh`) intenta enriquecer este directorio en silencio cuando detecta archivos compatibles en el sistema origen. El bootstrap los copia a `/usr/lib/firmware/brcm/` en el sistema nuevo.
