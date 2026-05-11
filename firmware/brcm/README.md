[Read in English 🇬🇧](README.en.md)

## Broadcom BCM43602 bundle

Este directorio contiene el bundle local que `Bootstrap CachyOS` puede copiar a:

```text
/usr/lib/firmware/brcm/
```

Objetivo:

- no depender de Wi-Fi durante el post-install
- conservar firmware/NVRAM util para `MacBookPro12,1`

Ficheros tipicos:

```text
brcmfmac43602-pcie.bin
brcmfmac43602-pcie.bin.zst
brcmfmac43602-pcie.clm_blob
brcmfmac43602-pcie.clm_blob.zst
brcmfmac43602-pcie.txcap_blob
brcmfmac43602-pcie.txcap_blob.zst
brcmfmac43602-pcie.txt
brcmfmac43602-pcie.Apple Inc.-MacBookPro12,1.txt
```

Notas:

- Los blobs `.zst` son validos en kernels modernos.
- El backup del sistema intenta enriquecer este directorio en silencio desde el
  sistema actual cuando encuentra ficheros compatibles.
- La logica interna de extraccion vive en `src/tools/extract_bcm43602_bundle.sh`.
- Si faltan `clm_blob` o `txcap_blob`, el sistema puede seguir funcionando, pero
  con limitaciones de canales/cobertura.
