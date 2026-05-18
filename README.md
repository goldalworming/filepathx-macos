# FilePathX for macOS

A native SwiftUI file manager for macOS, ported from a Windows C/OpenGL original. Built with the macOS look-and-feel in mind, with a focus on keyboard-driven workflows and dual-pane copy/paste convenience.

![FilePathX screenshot](docs/screenshot.png)

## Features

### Browsing
- **Hidden title bar** — tabs sit flush against the top of the window
- **Sidebar** with default locations (Home, Desktop, Documents, Downloads, Pictures, Movies, Music, Applications) plus user-defined Bookmarks (persisted in `UserDefaults`)
- **Toggleable sidebar** with click-and-drag resize handle (default width = minimum)
- **Breadcrumb path bar** — click any segment to jump there; click the empty trailing area (or double-click anywhere on the breadcrumb) to convert into an editable text field for typing full paths (supports `~` expansion)
- **Back / Forward / Up** navigation with history per tab
- **Auto-focus parent** — after going up to a parent folder, the directory you came from is automatically selected
- **Bookmarks** — toggle the bookmark icon in the toolbar to add/remove the current folder
- **Open in Terminal** — opens Terminal.app at the current folder

### Tabs
- Browser-style tab bar below the toolbar
- **Horizontal mouse-wheel scroll** — vertical scroll wheel converted to horizontal (so tabs scroll left/right when there are many of them), with separate tunable multipliers for mouse vs. trackpad
- Drag-to-reorder (planned)
- "+" button to open new tab; close button (×) appears on hover

### Dual-pane mode
- Toggle a second independent file browser on the right side
- Each panel has its own tabs, history, view mode, and selection
- **Click a panel to activate it** — selection clicks always activate the panel
- **Tab keyboard** to cycle the active panel
- **Drag files between panels** to copy (default) or move (hold ⌘)
- **First-responder transfer** — keyboard `Tab` switches macOS's AppKit first responder so arrow-key navigation, blue row highlight, and scroll-to-visible all follow the active panel
- Active panel shown with an accent border; inactive panel's row selection rendered in gray

### View modes
- **Details** — native `SwiftUI.Table` with Name / Kind / Date Modified / Size columns
- **Small icons** — compact grid (~36px icons)
- **Large icons** — generous grid (~96px icons)
- Switch between modes with the segmented picker in the header toolbar (per-tab setting)

### File operations
- **Cut / Copy / Paste** — uses both an internal clipboard (preserves cut vs. copy semantics) and `NSPasteboard` (so cross-app copy/paste with Finder works in both directions)
- **Move to Trash** — uses `FileManager.trashItem(at:)` so deleted items are recoverable
- **Rename** — inline `TextField` editor for a single file; for ≥2 selected files, opens an inline **batch rename** UI (described below)
- **New Folder / New File** with auto-unique-name (`untitled folder 2`, `untitled folder 3`, …) and auto-rename on creation
- **Reveal in Finder** — opens the system Finder selecting the file
- **Copy Path** — places the absolute path on the pasteboard

### Inline batch rename (C-source style)
Select 2+ files, trigger rename, and each row's name becomes an editor showing:
```
<original stem>     [typed text]   |    .<extension>
   primary             green    cursor      dim
```
- Type → text appended to **every** selected file's stem
- **Backspace** → first peels typed text right-to-left; once typed is empty, starts chopping characters off each file's original stem
- **Return** → commit (every file renamed atomically)
- **Esc** → cancel

Example: with `photo1.jpg`, `photo2.jpg`, `photo3.jpg` selected, typing `_2024` gives you `photo1_2024.jpg`, `photo2_2024.jpg`, `photo3_2024.jpg`. Press Backspace to peel back the `_2024`, then continue Backspace to chop the `1`/`2`/`3` off each stem.

### Drag & drop
- **Drag out** — drag a file or folder from FilePathX to Safari, Terminal, VS Code, Finder, etc. URL is shared via the system pasteboard (`NSURL` / `public.file-url`), so most apps know what to do with it
- **Drag preview** — file icon + name with rounded background and drop shadow follows the cursor
- **Three Finger Drag** (system setting) makes initiating a drag on a trackpad much smoother — enable it in **System Settings → Accessibility → Pointer Control → Trackpad Options**

## Keyboard shortcuts

| Shortcut | Action |
|----------|--------|
| `Return` · double-click · `⌘↓` | Open file / enter folder |
| `Backspace` · `⌘↑` | Enclosing (parent) folder |
| `⌘E` | Rename (works in batch when multiple selected) |
| `F2` | Rename (Windows-style alias — requires `Fn+F2` unless function-key mode is enabled in System Settings) |
| `⌘C` / `⌘X` / `⌘V` | Copy / Cut / Paste |
| `⌘T` / `⌘W` | New tab / Close tab |
| `⌘R` | Refresh |
| `⌘[` / `⌘]` | Back / Forward |
| `⌘\` | Toggle dual-pane (split view) |
| `Tab` | Switch active panel (in split mode) |
| `⌃D` | Open Terminal at current folder |
| `⌘⇧N` | New Folder |
| `↑` / `↓` | Move row selection (active panel) |
| `⇧↑` / `⇧↓` | Extend row selection |
| `Esc` | Cancel rename / cancel batch rename |

## Building

Requires **Xcode 15+** and **macOS 14+** to build. Deployment target is **macOS 13.0**.

```bash
git clone https://github.com/goldalworming/filepathx-macos.git
cd filepathx-macos
open FilePathX.xcodeproj
```

Then press **⌘R** in Xcode, or build a Release `.app` from the command line:

```bash
xcodebuild -project FilePathX.xcodeproj \
           -scheme FilePathX \
           -configuration Release \
           -derivedDataPath build \
           build
```

The resulting bundle is at `build/Build/Products/Release/FilePathX.app`.

The app is signed ad-hoc ("Sign to Run Locally") so it runs on the developer's own machine without a Developer ID. To distribute it, configure a `DEVELOPMENT_TEAM` and re-sign.

## Project structure

```
FilePathX/
├── FilePathX.xcodeproj/         # Xcode project
└── FilePathX/                   # Swift source
    ├── FilePathXApp.swift       # @main entry, CommandGroup shortcuts
    ├── AppModel.swift           # Root state: panels, bookmarks, clipboard
    ├── Panel.swift              # Per-pane state: tabs + active tab id
    ├── BrowserTab.swift         # Per-tab state: url, history, entries, selection, rename, batch
    ├── FileSystemService.swift  # FileManager wrapper (list, trash, rename, copy, move, terminal)
    ├── KeyboardShortcutMonitor  # NSEvent local monitor — global keystroke routing
    ├── HorizontalWheelScroller  # NSScrollView subclass redirecting vertical wheel → horizontal
    ├── ContentView.swift        # Top-level layout (sidebar + dual-pane HStack)
    ├── HeaderToolbar.swift      # Per-pane header: back/fwd/up/breadcrumb/view-mode + sidebar/split toggles on the leftmost
    ├── TabBarView.swift         # Custom tab bar (one per panel)
    ├── BrowserView.swift        # Per-tab content (Details or Icon grid + status bar)
    ├── DetailsView.swift        # SwiftUI Table with custom selection binding
    ├── IconGridView.swift       # LazyVGrid for small/large icon modes
    ├── BatchRenameInline.swift  # Composite view for inline batch rename
    ├── BreadcrumbView.swift     # Segment chips + text-field address mode
    ├── SidebarView.swift        # Favorites + bookmarks list
    ├── FileContextMenu.swift    # Right-click menu builder
    ├── StatusBarView.swift      # Bottom item count / selection summary
    ├── FileIcon.swift           # NSWorkspace icon → SwiftUI Image bridge
    ├── FileEntry.swift, ViewMode.swift, SidebarItem.swift, FileClipboard.swift  # Models
    └── Assets.xcassets/         # AppIcon + AccentColor
```

## Roadmap

- **Per-path persistence**: view mode + sort order saved per directory (currently kept in tab state only)
- **Date grouping** in Downloads (Today / Earlier this week / Last week / Last month / A long time ago), matching the C original
- **Tab drag-to-reorder**
- **Multi-select drag-out** (currently single item per drag)
- **QuickLook thumbnails** for large-icon view via `QLThumbnailGenerator`
- **Search field** in the header toolbar
- **Properties / Get Info** sheet
- **Hidden file toggle** (currently always hidden)

## License

MIT — see [LICENSE](LICENSE) if/when added. The original Windows C source remains the property of its author.

## Credits

Ported from the original Windows C/OpenGL FilePathX implementation. Built with Swift, SwiftUI, and AppKit interop where needed (custom `NSScrollView` for tab-bar wheel redirection, `NSWindow.makeFirstResponder` for dual-pane focus transfer, `NSEvent.addLocalMonitorForEvents` for global keystroke handling).
