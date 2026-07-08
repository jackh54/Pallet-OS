# Legal & licensing notes

## Play Store / GAPPS (Waydroid)

Pallet OS can install **Waydroid with the GAPPS** variant to access the Google Play Store on devices. This is a **legal and Terms-of-Service gray area**:

- **Google Play Services and Play Store** are proprietary Google software. They are not redistributed by Pallet OS.
- Waydroid's `waydroid init -s GAPPS` downloads vendor images; you are responsible for compliance with Google's terms.
- For **production fleets**, consider:
  - **FOSS-only** Android apps (F-Droid APKs force-installed via policy)
  - **Managed web apps** in Chromium instead of native Android
  - Enterprise-owned APK mirrors you are licensed to distribute

Pallet OS does **not** bundle GAPPS. The provisioner optionally initializes Waydroid GAPPS on the device at install time.

## Chromium enterprise policies

Pallet OS writes standard Chromium `managed` policy JSON. This uses open policy keys documented by Chromium — **no Chrome Enterprise / Google Admin license** is required for the policy format itself.

## Trademarks

"ChromeOS", "Chromebook", and "Google Play" are trademarks of Google LLC. Pallet OS is an independent project and is not affiliated with Google.
