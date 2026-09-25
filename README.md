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

## Development notes

- Only the large checkbox toggles completion; title and description clicks open/select for editing.
- Title and description support Markdown, including tappable links.
- Priority: high / medium / low. Optional **complete by** date and time; **created on** and **completed at** are stored and shown when set.
