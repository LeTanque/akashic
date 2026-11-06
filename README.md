# Akashic

Native macOS menu-bar todo app (SwiftUI + SQLite). Accessory app with no Dock icon: use the **sparkles** menu-bar item for a compact popover, or **Open Akashic** for the detachable main editor window.

![Akashic header](docs/akashic-header.png)

## Requirements

- macOS 15 or later
- Xcode **16.3+** / Swift **6.1+** (`Package.swift` uses `swift-tools-version: 6.1` — required for the SQLCipher-backed GRDB dependency)

Shared logic (models, database, sync bookkeeping, merge helpers) lives in the **`AkashicCore`** library target (macOS 15 + iOS 17); the `Akashic` executable is the menu-bar app.

## Build and run

From this directory:

```sh
chmod +x build.sh
./build.sh
open build/Akashic.app
```

To install into Applications:

```sh
./build.sh
cp -R build/Akashic.app /Applications/
open -a Akashic
```

## Data (important)

**Local-only, encrypted at rest.** Akashic uses **SQLCipher** (via GRDB) for `akashic.sqlite`. A separate **`akashic-security.json`** file in the same folder stores **wrapped** database keys and KDF parameters — never the raw key.

```text
~/Library/Application Support/Akashic/akashic.sqlite
~/Library/Application Support/Akashic/akashic-security.json
```

Do **not** commit those files, exports of personal todos, or dumps named like `seed-from-*.json`. Those patterns are gitignored.

**First launch / upgrade:** You create a local account (username, password), save a **one-time recovery code** and scan a **TOTP** QR (RFC 6238: SHA-1, 30s, 6 digits). If an older **plaintext** `akashic.sqlite` is already on disk, Akashic migrates it with **`sqlcipher_export`**, verifies row counts for every table, atomically swaps in the encrypted file, and renames the original to `akashic.sqlite.plaintext-backup-<timestamp>` — **delete that backup yourself after verifying**. Auto-deleting it would remove your safety net.

On **first successful unlock with an empty DB**, Akashic imports the bundled **demo** seed (`Sources/AkashicCore/Resources/akashic-seed-todos.json`). That seed is sample content only.

**Passwords / AutoFill:** Text fields use `textContentType` for username, password, and one-time code. Saving credentials to the **Passwords** app with automatic form filling on a website usually needs **Associated Domains** and a **paid Apple Developer** account; without that, use **manual entry** or scan the setup QR.

**Biometrics (optional):** After password unlock, you can store the data key in the Keychain with `Touch ID` / Face ID (`LocalAuthentication`); unlocking still requires the current TOTP code.

**Lock:** The app starts locked; **auto-lock** after configurable idle time (default 15 minutes) and on **sleep**; use **Lock Akashic** in the menu-bar menu.

Sync-oriented schema, crypto details, and merge rules are in [docs/sync-design.md](docs/sync-design.md).

Use **Import Demo Seed…** or **Import JSON…** from the **sparkles** menu-bar menu only when you intentionally want to load sample or your own exported JSON into the local DB. Both actions ask for confirmation because they replace your current todos.

## Embedded API (FlyingFox)

While Akashic is running **unlocked**, an in-process HTTP server listens on **localhost only** (`localhost:4311`). It reads and writes the same encrypted SQLite store as the UI through `TodoStore`, so the menu-bar UI refreshes after API mutations. There is no separate API process and no second database.

When the app is **locked**, data routes return **HTTP 423 Locked** (see table below). `GET /health` still responds.

The main-window **top header chrome** (`CyberHeaderStrip`) keeps the Akashic wordmark **centered in the window** and the add/sidebar controls on the **trailing** edge; the leading slot is empty space so the logo stays optically centered.

| Method | Path | Notes |
|--------|------|--------|
| `GET` | `/health` | `{ "status", "database", "app" }` |
| `*` | `/api/*` (when locked) | **423** `{ "error": "locked", … }` |
| `GET` | `/api/todos?status=all\|active\|completed` | `{ "todos": [ … ] }` |
| `POST` | `/api/todos` | Body: `{ "title", "description?", "priority?" }` → `201` |
| `PATCH` | `/api/todos/:id` | Body may include `title`, `description`, `completed`, `priority`, `complete_by` |
| `DELETE` | `/api/todos/:id` | `204` on success |

Todo `id` values are UUID strings.

Examples:

```sh
curl -s http://localhost:4311/health
curl -s 'http://localhost:4311/api/todos?status=active'
curl -s -X POST http://localhost:4311/api/todos \
  -H 'Content-Type: application/json' \
  -d '{"title":"Ship the README","priority":"high"}'
```

If nothing answers on `:4311`, start Akashic first (the server starts with the app).

## Build with Xcode

```sh
open Package.swift
```

Or:

```sh
xcodebuild -scheme Akashic -destination 'platform=macOS' -configuration Release build
./build.sh
```

## Text zoom

Keyboard / menu bar only (no in-window buttons). Preference is persisted in UserDefaults.

- **View → Zoom In** `⌘+`
- **View → Zoom Out** `⌘-`
- **View → Actual Size** `⌘0`

Todo titles, descriptions, and editors scale by an explicit point-size factor (chrome controls stay fixed).

### Import from cyberpunk2044 / cyberpunk2077

Use the stdlib Python importer to pull todos from a running cyberpunk-style app (`GET /api/todos`) or from a JSON seed file into Akashic’s SQLite database. New rows get fresh UUIDs; import **appends** by default (`--replace` deletes existing todos first). Quit or relaunch Akashic after importing so the UI picks up changes.

Home API (default port 2044):

```sh
python3 scripts/import-from-cyberpunk.py
# or explicitly:
python3 scripts/import-from-cyberpunk.py --api http://127.0.0.1:2044/api/todos
```

Work fork or another host/port:

```sh
python3 scripts/import-from-cyberpunk.py --api http://127.0.0.1:PORT/api/todos
```

From a seed file (same shape as `seed-from-cyberpunk2044.json`):

```sh
python3 scripts/import-from-cyberpunk.py --json seed-from-cyberpunk2044.json
```

Other useful flags: `--db PATH`, `--dry-run`, `--write-seed PATH` (save the fetched payload for reuse).

## Development notes

- Only the large checkbox toggles completion; clicking anywhere else on the row opens that todo for editing.
- New todos open in the editor immediately. Selecting a todo does not change its list position.
- Click-hold-drag reorders the list. Default stack is high → medium → low; drag can override that. Completed items stay at the bottom.
- App chrome uses smoked-glass vibrancy (`NSVisualEffectView` HUD material) with a light black veil; neon frame stays on top.
- Title and description support Markdown, including tappable links, headings, and bullet lists. Both editor fields keep a raw-source `NSTextView` (smart quotes/dashes off so `- ` list markers survive) and a live formatted preview from the same renderer as list rows. SQLite stores the raw markdown strings.
- Priority: high / medium / low. Optional **complete by** date and time; **created on** and **completed at** are stored and shown when set.
- Dependencies: [GRDB + SQLCipher (SPM fork)](https://github.com/sqlcipher/GRDB.swift), [FlyingFox](https://github.com/swhitty/FlyingFox).
