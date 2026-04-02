# Shopify Distribution Plan (DMG-Style Windows Flow)

## Goal
Deliver a one-click Windows install flow that feels like a managed app channel:
- User clicks install page button
- Windows App Installer opens
- Atlas installs and can check for updates
- On first launch, BlackHaven completes local AI setup inside the app

## 1. Build release bundle
From `windows-app/scripts`:

```powershell
.\build-windows-dmg-style-installer.ps1 `
  -Arch x64 `
  -Configuration Release `
  -Version 1.0.0 `
  -AppInstallerBaseUrl "https://downloads.atlasmasa.com/windows/stable/x64/" `
  -SigningThumbprint "<YOUR_CODESIGN_CERT_THUMBPRINT>"
```

Output path:
- `windows-app/release/<version>/<arch>/appinstaller/`

Important artifacts:
- `web/AtlasMasa-<arch>.appinstaller`
- `web/AtlasMasa-<arch>.msix`
- `web/index.html`
- `AtlasMasa-Windows-Install-<version>-<arch>.zip`
- `SHA256SUMS.txt`
- `appinstaller-manifest.json`

## 2. Host installer channel files
Upload all files from `web/` to your stable HTTPS folder (same folder used in `AppInstallerBaseUrl`).

Recommended:
- `https://downloads.atlasmasa.com/windows/stable/x64/`
- Keep filenames stable for updates (`AtlasMasa-x64.appinstaller`, `AtlasMasa-x64.msix`)

## 3. Shopify product setup
1. Create product in Shopify Admin, example: `Atlas Masa for Windows (x64)`.
2. Install a digital delivery app:
   - Shopify guide: https://help.shopify.com/en/manual/products/digital-service-product/digital-products
   - App Store: https://apps.shopify.com/digital-downloads
3. Attach `AtlasMasa-Windows-Install-<version>-<arch>.zip` to the product.
4. In product description and post-purchase instructions, direct users to open `index.html` or run `Install-AtlasMasa.cmd`.

## 4. Production trust checklist
- Use OV/EV code signing cert (required for production trust)
- Verify installer on clean Windows VM
- Verify update from previous version
- Publish checksums and version notes

## 5. Operational checklist
1. Build signed release.
2. Upload `web/` to stable HTTPS hosting.
3. Upload Shopify ZIP artifact.
4. Place a real test purchase.
5. Confirm buyer can install with one click.
6. Archive `SHA256SUMS.txt` + `appinstaller-manifest.json`.

## Reference docs
- Shopify digital products guide: https://help.shopify.com/en/manual/products/digital-service-product/digital-products
- Shopify app recommendation for digital goods: https://shopify.dev/docs/apps/build/purchase-options/product-variant-media/digital-goods-apps
- Shopify App Store digital delivery app: https://apps.shopify.com/digital-downloads
