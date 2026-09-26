# Akashic

Native macOS menu-bar todo app (SwiftUI + SQLite). Accessory app with no Dock icon: use the **sparkles** menu-bar item for a compact popover, or **Open Akashic** for the detachable main editor window.

## Requirements

- macOS 15 or later
- Xcode 15+ or Swift 5.9+ toolchain

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

**Live todos are local-only.** The SQLite database lives outside the git tree:

```text
~/Library/Application Support/Akashic/akashic.sqlite
```

Do **not** commit that file, exports of personal todos, or dumps named like `seed-from-*.json`. Those patterns are gitignored.

On **first launch with an empty database**, Akashic imports the bundled **demo** seed (`Sources/Akashic/Resources/akashic-seed-todos.json`). That seed is sample content only — replace it with your own local list in Application Support; never put personal todos in the bundled seed.

Use **Import demo seed** or **Import JSON…** in the main window only when you intentionally want to load sample or your own exported JSON into the local DB.

## Embedded API (FlyingFox)

While Akashic is running, an in-process HTTP server listens on **localhost only** (`127.0.0.1:4311`). It reads and writes the same SQLite store as the UI through `TodoStore`, so the menu-bar UI refreshes after API mutations. There is no separate API process and no second database.

| Method | Path | Notes |
|--------|------|--------|
| `GET` | `/health` | `{ "status", "database", "app" }` |
| `GET` | `/api/todos?status=all\|active\|completed` | `{ "todos": [ … ] }` |
| `POST` | `/api/todos` | Body: `{ "title", "description?", "priority?" }` → `201` |
| `PATCH` | `/api/todos/:id` | Body may include `title`, `description`, `completed`, `priority`, `complete_by` |
| `DELETE` | `/api/todos/:id` | `204` on success |

Todo `id` values are UUID strings.

Examples:

```sh
curl -s http://127.0.0.1:4311/health
curl -s 'http://127.0.0.1:4311/api/todos?status=active'
curl -s -X POST http://127.0.0.1:4311/api/todos \
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

## Development notes

- Only the large checkbox toggles completion; clicking anywhere else on the row opens that todo for editing.
- New todos open in the editor immediately. Selecting a todo does not change its list position.
- Click-hold-drag reorders the list. Default stack is high → medium → low; drag can override that. Completed items stay at the bottom.
- App chrome uses smoked-glass vibrancy (`NSVisualEffectView` HUD material) with a light black veil; neon frame stays on top.
- Title and description support Markdown, including tappable links.
- Priority: high / medium / low. Optional **complete by** date and time; **created on** and **completed at** are stored and shown when set.
- Dependencies: [GRDB](https://github.com/groue/GRDB.swift), [FlyingFox](https://github.com/swhitty/FlyingFox).
