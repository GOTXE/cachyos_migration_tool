[Leer en español 🇪🇸](README.md)

## Broadcom BCM43602 bundle

This directory contains the local bundle that `Bootstrap CachyOS` can copy to:

```text
/usr/lib/firmware/brcm/
```

Purpose:

- avoid Wi-Fi dependency during post-install
- preserve firmware/NVRAM useful for `MacBookPro12,1`

Typical files:

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

Notes:

- `.zst` blobs are valid on modern kernels.
- The system backup silently tries to enrich this directory from the current
  system when it finds compatible files.
- The internal extraction logic lives in `src/tools/extract_bcm43602_bundle.sh`.
- If `clm_blob` or `txcap_blob` are missing, the system may still work but
  with channel/coverage limitations.
