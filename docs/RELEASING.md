# Releasing Framegentic

Releases are cut by pushing a `v*` tag. CI builds, signs with Developer ID, notarizes, staples and attaches a zip + SHA-256 checksum to a GitHub release.

## One-time setup

Six repository secrets (Settings → Secrets and variables → Actions):

| Secret | Content |
|---|---|
| `MACOS_CERT_P12` | Developer ID Application cert + private key, exported as .p12, base64-encoded |
| `MACOS_CERT_PASSWORD` | The .p12 export password |
| `KEYCHAIN_PASSWORD` | Any throwaway password for the CI temp keychain |
| `ASC_KEY_ID` | App Store Connect API key ID |
| `ASC_ISSUER_ID` | App Store Connect issuer UUID |
| `ASC_API_KEY_P8` | Contents of the .p8 private key |

Export the cert (identity: `Developer ID Application: Duncan Smith (5V849Q2B6Z)`):

```bash
security export -k login.keychain -t identities -f pkcs12 -o cert.p12
base64 -i cert.p12 | pbcopy
```

Create the API key at App Store Connect → Users and Access → Integrations → App Store Connect API. Developer role is enough for notarization.

## Cutting a release

```bash
git tag v1.0.0 && git push origin v1.0.0
```

That's it. `CFBundleShortVersionString` comes from the tag, `CFBundleVersion` from `git rev-list --count HEAD` — never edit versions in Info.plist by hand.

## Local release build

```bash
VERSION=1.0.0 SIGN_IDENTITY="Developer ID Application" ./scripts/build.sh
```

Then notarize manually if distributing:

```bash
ditto -c -k --keepParent .build/Framegentic.app Framegentic.zip
xcrun notarytool submit Framegentic.zip --keychain-profile framegentic --wait
xcrun stapler staple .build/Framegentic.app
```

(`notarytool store-credentials framegentic` once beforehand to save the API key locally.)

## Notes

- The app cannot ship on the Mac App Store: CGEvent keystroke posting is incompatible with the App Sandbox. Developer ID + notarization is the only channel.
- No entitlement exceptions are needed under hardened runtime — Accessibility and Screen Recording are TCC grants, not entitlements.
- Ship the *stapled* zip, not the one submitted for notarization.
- Sparkle auto-updates are planned but not wired yet. Until then, releases are manual downloads. Add Sparkle before the install base grows.
