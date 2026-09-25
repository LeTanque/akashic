# Akashic

Native macOS menu-bar todo app (SwiftUI + SQLite). Accessory app with no Dock icon: use the **sparkles** menu-bar item for a compact glass popover, or **Open Akashic** for the detachable main editor window.

## Requirements

- macOS 14 or later
- Xcode 15+ or Swift 5.9+ toolchain

## Build and run

From this directory:

```sh
chmod +x build.sh
./build.sh
open build/Akashic.app
```

## Build with Xcode

Open the Swift package in Xcode and run the **Akashic** scheme (menu bar only at runtime when launched from a signed `.app` bundle with `LSUIElement`):

```sh
open Package.swift
```

Or verify from the command line:

```sh
xcodebuild -scheme Akashic -destination 'platform=macOS' -configuration Release build
./build.sh
```

## Data

SQLite database: `~/Library/Application Support/Akashic/akashic.sqlite`

On first launch with an empty database, Akashic imports the bundled cyberpunk2044 seed (`Resources/akashic-seed-todos.json`, 12 items). Use **Import seed** or **Import JSON…** in the main window to re-import.

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

- Only the large checkbox toggles completion; title and description clicks open/select for editing.
- Title and description support Markdown, including tappable links.
- Priority: high / medium / low. Optional **complete by** date and time; **created on** and **completed at** are stored and shown when set.
