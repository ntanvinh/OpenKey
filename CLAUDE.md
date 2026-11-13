# Notes for AI assistants working in this repo

## The app is called "VOpenKey AI"

The name of the app is **VOpenKey AI**, everywhere a person sees or launches it:

- the app bundle: `VOpenKey AI.app`, executable `VOpenKey AI` (`PRODUCT_NAME` in the Xcode project), `CFBundleName` / `CFBundleDisplayName`
- `VOK_APP_NAME` in `Sources/OpenKey/macOS/ModernKey/AppInfo.h` and `DISPLAY_NAME` in `scripts/common.sh`
- every string in the UI (menus, alerts, tooltips, settings), README and the docs, on Windows too (`OpenKey.rc`, tray menu, message boxes, the desktop shortcut `VOpenKey AI.lnk`); the owner confirmed on 2026-10-24 that all desktop versions use the one name
- where `scripts/dev.sh` installs it: `~/Applications/VOpenKey AI.app` (never `VOpenKey.app`)
- the DMG volume name and the title of the GitHub release

The owner confirmed this on 2026-10-16, after it had been shortened to "VOpenKey" by mistake several times (commit `bc26318`
"rebrand app to VOpenKey" changed UI strings, commit `05ff654` changed `scripts/dev.sh` so that it installed `VOpenKey.app`).
Do not "rebrand", "simplify" or shorten it, and do not take "VOpenKey" in old commit messages or CHANGELOG headings as the
current name. If a task seems to need a rename, ask the owner first.

### What is plain "VOpenKey" on purpose

These are identifiers or file names that must not move, they are not the name of the app:

- release file names `VOpenKey-<version>.dmg` and `VOpenKey-<version>-Windows.zip` (`APP_NAME` in `scripts/common.sh`: no spaces, GitHub rewrites them), and `VOpenKey.dmg`, the same dmg without the version, which the website links to as `.../releases/latest/download/VOpenKey.dmg`; the app's updater looks for exactly `VOpenKey-<version>.dmg` (`VOK_RELEASE_FILE_NAME` in `AppInfo.h`)
- `VOpenKey-Windows.zip`, the fixed-name copy of the newest Windows zip that `.github/workflows/release-windows.yml` attaches to every release; the README, the website and the `product.json` files link to `.../releases/latest/download/VOpenKey-Windows.zip`
- the bundle id `vn.io.lssoft.vopenkey`
- the folder names `~/Library/Application Support/VOpenKey` and `~/Library/Logs/VOpenKey` (`VOK_DATA_DIR_NAME`), so the user's data stays where it is
- the notarytool profile `VOpenKey-notary`
- on Windows: the program files `OpenKey64.exe`, `OpenKey32.exe`, `OpenKeyUpdate.exe`, the registry key `SOFTWARE\TuyenMai\OpenKey` and the "OpenKey" start-up entry in it, the github URLs and the licence headers of the original author
- the `##### VOpenKey x.y.z` headings of `CHANGELOG.md` (`scripts/version.sh` searches for them) and the comment line `//  VOpenKey` at the top of source files

## Release workflow resilience
`scripts/release.sh` is designed to be idempotent:
- When a release is partly published or interrupted at the Windows build / announce step, `scripts/release.sh current --yes` safely resumes it, verifies existing notarized disk images, triggers/waits for the Windows build workflow, and finishes announcing the release.
- `wait_for_windows` automatically dispatches `.github/workflows/release-windows.yml` via `gh workflow run` if GitHub Actions does not trigger the `release: published` event automatically within 20 seconds.

## Windows ships with every release
- The Windows app is released with the macOS app (`VOpenKey-<version>-Windows.zip`). Do not call it upstream-only or "unverified" in `README.md`, `marketing/positioning.md`, the `product.json` files or `Sources/OpenKey/win32/README.md`, and do not write "Mac" alone where the product is for both platforms.
- When a platform claim changes, change those files in the same commit. `python3 scripts/check-product-docs.py` checks the Windows links, the platform lists and the descriptions; CI runs it in the `product-docs` job of `.github/workflows/msbuild.yml`.

## Product description length
- `description` in `marketing/website/product.json` is the page's meta description (search results cut it near 155 characters). Keep `description.en` and `description.vi` at 70-155 characters each, and keep the same text in `docs/vopenkey-ai/product.json`. `scripts/check-product-docs.py` enforces both rules; change both files in the same commit.

## Feature texts
- Each feature with a picture is written twice: `marketing/features/<id>.json` and its entry in `docs/vopenkey-ai/product.json`. Change both in the same commit; the title and description must match in both languages. `scripts/check-product-docs.py` checks it.
- Visitor text never names an internal file (the README, `marketing/positioning.md`, a changelog): a visitor cannot open it. Describe the feature itself. The checker rejects `README`, `.md` and `CHANGELOG` in these texts.
