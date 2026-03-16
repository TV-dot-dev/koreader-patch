# KOReader Patch

A refined home screen UI for [KOReader](https://koreader.rocks), optimised for e-ink displays.

## Features

- **Home tab** — greeting, currently-reading card with progress bar, continue button, recent books list
- **Library tab** — full reading history with per-book progress, paginated (no scrolling)
- **Files tab** — drops straight into KOReader's built-in file browser
- **Goals tab** — library size, books opened this year, reading goal summary
- **More tab** — quick access to OPDS, KOSync settings, device settings, plugins
- **Pagination everywhere** — no scrolling; all lists use ← / → page turns, ideal for slow e-ink panels
- **Zero animations** — `display:none/block`-style show/hide only; no transitions that cause ghosting

## Compatibility

Tested against KOReader **v2023.x** and later.
Works on any device KOReader supports (Kindle, Kobo, PocketBook, Android, Linux).

## Installation

### Option A — Sideload (recommended for Kindle / Kobo)

1. Download or clone this repo.
2. Copy the **`koreader-patch.koplugin`** folder into KOReader's `plugins/` directory on your device:

   | Device | Path |
   |--------|------|
   | Kindle | `koreader/plugins/` (on the Kindle's internal storage) |
   | Kobo   | `.adds/koreader/plugins/` |
   | Android | `/sdcard/koreader/plugins/` or the path shown in KOReader → Settings → Advanced |
   | Linux / desktop | `~/.config/koreader/plugins/` |

3. Restart KOReader (or go to **Main Menu → Tools → Plugin management** and tap **Reload plugins**).
4. The Home Screen opens automatically on next launch.
   You can also open it at any time via **Main Menu → Home Screen**.

### Option B — Install via SSH / shell (advanced)

```bash
# Replace <device-ip> and <koreader-plugins-path> for your device
scp -r koreader-patch.koplugin root@<device-ip>:<koreader-plugins-path>/
```

## File structure

```
koreader-patch.koplugin/
├── _meta.lua          Plugin metadata (name, version)
├── main.lua           Entry point; hooks FileManager startup
└── homescreen.lua     Full-screen HomeScreen widget (all views)
```

## Updating

Replace the `koreader-patch.koplugin` folder with the new version and restart KOReader.

## Uninstalling

Delete the `koreader-patch.koplugin` folder from the `plugins/` directory and restart KOReader.

## Notes

- **KOSync** — only syncs reading *position* for the currently open book. The plugin does not sync your whole library. KOSync settings are accessible via More → KOSync Settings.
- **OPDS** — the OPDS browser opens KOReader's built-in OPDS client. Your custom OPDS server works exactly like any standard OPDS feed (Calibre, Kavita, Standard Ebooks, etc.).
- **Statistics** — the Goals view shows richer data when KOReader's built-in **Statistics** plugin is enabled (Main Menu → Tools → Statistics).

## License

MIT
