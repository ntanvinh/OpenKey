# Notes for AI assistants working in this repo

## The app is called "VOpenKey AI"

The name of the app is **VOpenKey AI**, everywhere a person sees or launches it:

- the app bundle: `VOpenKey AI.app`, executable `VOpenKey AI` (`PRODUCT_NAME` in the Xcode project), `CFBundleName` / `CFBundleDisplayName`
- `VOK_APP_NAME` in `Sources/OpenKey/macOS/ModernKey/AppInfo.h` and `DISPLAY_NAME` in `scripts/common.sh`
- every string in the UI (menus, alerts, tooltips, settings), README and the docs
- where `scripts/dev.sh` installs it: `~/Applications/VOpenKey AI.app` (never `VOpenKey.app`)
- the DMG volume name and the title of the GitHub release

The owner confirmed this on 2026-10-16, after it had been shortened to "VOpenKey" by mistake several times (commit `bc26318`
"rebrand app to VOpenKey" changed UI strings, commit `05ff654` changed `scripts/dev.sh` so that it installed `VOpenKey.app`).
Do not "rebrand", "simplify" or shorten it, and do not take "VOpenKey" in old commit messages or CHANGELOG headings as the
current name. If a task seems to need a rename, ask the owner first.

### What is plain "VOpenKey" on purpose

These are identifiers or file names that must not move, they are not the name of the app:

- release file names `VOpenKey-<version>.dmg` and `VOpenKey-<version>-Windows.zip` (`APP_NAME` in `scripts/common.sh`: no spaces, GitHub rewrites them), and `VOpenKey.dmg`, the same dmg without the version, which the website links to as `.../releases/latest/download/VOpenKey.dmg`; the app's updater looks for exactly `VOpenKey-<version>.dmg` (`VOK_RELEASE_FILE_NAME` in `AppInfo.h`)
- the bundle id `vn.io.lssoft.vopenkey`
- the folder names `~/Library/Application Support/VOpenKey` and `~/Library/Logs/VOpenKey` (`VOK_DATA_DIR_NAME`), so the user's data stays where it is
- the notarytool profile `VOpenKey-notary`
- the `##### VOpenKey x.y.z` headings of `CHANGELOG.md` (`scripts/version.sh` searches for them) and the comment line `//  VOpenKey` at the top of source files
