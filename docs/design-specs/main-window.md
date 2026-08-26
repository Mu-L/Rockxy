# Rockxy Main Window — Design Spec

## Overview

The primary application window — a 3-column developer debugging interface following industry-standard layout patterns and Apple HIG for macOS 14+.

---

## Layout Structure

```
┌─────────────────────────────────────────────────────────────────────────────────────┐
│ ◉ ◉ ◉  [Sidebar] │ [📁 Checkout API ▾]       ● Listening        [▶] [Inspector]  │  ← Toolbar
├────────────┬────────────────────────────────────────────┬───────────────────────────┤
│            │ [All][HTTP][HTTPS][WS][GQL]..│[2xx][3xx].. │                           │  ← Filter Bar (28pt)
│  SIDEBAR   ├────────────────────────────────────────────┤    INSPECTOR PANEL        │
│            │ #  │ URL           │Method│Code│Time│Dur│Sz│                           │
│ ▼ Favorites│ 1  │ /api/users    │ GET  │200 │12:0│45m│2K│  ┌─────────┬───────────┐ │
│   Pinned   │ 2  │ /api/auth     │ POST │201 │12:0│12m│1K│  │ Request │ Response  │ │
│   Saved    │ 3  │ /graphql      │ POST │200 │12:0│89m│8K│  │ Headers │ Headers   │ │
│ ▼ All      │ 4  │ /api/orders   │ GET  │404 │12:0│23m│0 │  │ Query   │ Body      │ │
│   ▶ Apps   │ 5  │ /ws/events    │ GET  │101 │12:0│-  │- │  │ Body    │ Set-Cookie│ │
│   ▶ Domains│ 6  │ /api/users/42 │ PUT  │200 │12:0│67m│3K│  │ Cookies │ Auth      │ │
│ ▼ Analytics│ 7  │ /api/config   │ GET  │304 │12:0│8m │0 │  │ Raw     │ Timeline  │ │
│   Errors   │ 8  │ /api/upload   │ POST │500 │12:0│2s │1M│  │ Synopsis│           │ │
│   Perf     │    │               │      │    │    │   │  │  │ Comments│           │ │
│   Trends   │    │               │      │    │    │   │  │  └─────────┴───────────┘ │
├────────────┤────────────────────────────────────────────┤───────────────────────────┤
│ [+] [⚙ ⌘⇧F]│ 847 requests                    ● :9090  │                           │  ← Status Bar (22pt)
└────────────┴────────────────────────────────────────────┴───────────────────────────┘
```

**Minimum window size**: 1000 x 600 pt
**Default window size**: 1280 x 800 pt

---

## Column Dimensions

| Column | Default Width | Min Width | Max Width | Collapsible |
|--------|--------------|-----------|-----------|-------------|
| Sidebar | 220pt | 160pt | 400pt | Yes (double-click divider) |
| Request List | Flexible (fills) | 300pt | — | No |
| Inspector | 480pt | 400pt | — | Yes (toolbar toggle) |

**Dividers**: 1pt visual width, 8pt hit target. Color: `NSColor.separatorColor`.

---

## 1. Toolbar (38pt height)

### Layout
```
[Sidebar] │ [📁 Active Project ▾]     {● Listening on 127.0.0.1:9090}     [▶ Start/Stop] [Developer Hub] [Bottom Inspector] [Context Dock]
```

### Controls

| Control | Icon (SF Symbol) | States | Shortcut | Priority |
|---------|-----------------|--------|----------|----------|
| Project Selector | `folder.fill` | Active Project menu | — | High |
| Start/Stop | `play.fill` / `stop.fill` | Toggle | — / ⌘. | High |
| Developer Hub | `command` | Opens tool launcher | — | Medium |
| Bottom Inspector | `rectangle.split.1x2` | Toggle visibility | — | Medium |
| Context Dock | `sidebar.trailing` | Toggle visibility | — | Medium |

### Project Selector (Leading)
- Appears immediately after the sidebar tracking separator.
- Shows the active local Project name and opens switching/management actions.
- Sizes to the active Project name within a 104–240 pt band; short names stay compact and long names truncate without displacing the centered status.

### Status Indicator (Center)
- Circle: 8pt diameter, `NSColor.systemGreen` (running) / `NSColor.secondaryLabelColor` (stopped)
- Text: `"Listening on 127.0.0.1:9090"` or `"Not Running"`
- Font: `.systemFont(ofSize: 12)`, `NSColor.secondaryLabelColor`

### Styling
- Button style: native bordered `NSToolbarItem` controls in the unified toolbar, with the shared glass-control treatment used by SwiftUI toolbar fallbacks
- Icon size: 16pt SF Symbols
- Button spacing: 4pt
- Separator: SwiftUI `Divider()` between action groups
- Tooltips on all buttons via `.help()` modifier

### Customization Flow
- Entry point: `Customize Toolbar…` at the bottom of the protocol-filter ellipsis menu.
- Uses the standard AppKit toolbar customization palette, including Icon and Text display modes,
  fixed/flexible spaces, Done, and the draggable default set.
- User-customizable items: Source List, Project, Proxy Status, Start or Stop Proxy, Developer Hub,
  Bottom Inspector, and Context Dock.
- The source-list tracking separator is structural and immovable so the unified titlebar continues
  to align with the three-pane split even when the Source List button is removed. AppKit documents
  immovable items as un-draggable and non-removable, so the separator cannot be dragged out or
  reordered from the customization palette.
- Removing a toolbar item never removes the underlying command: proxy, Project, panel, Source List,
  and Developer Hub actions remain available from the app menus or the traffic control shelf; Proxy
  Status is informational only.
- Proxy Status is registered as the toolbar's centered item, so when present it stays visually
  centered regardless of the surrounding item order — removing and re-adding it, or reordering its
  neighbors, does not move it out of the centered set.
- The Icon and Text display modes only change how AppKit's own image/label items render. The custom
  hosted items (Project selector, Proxy Status) supply their own SwiftUI content via `NSHostingController`,
  so they keep their native rendered view across every display mode rather than collapsing to a
  system label or icon.
- The customized order, visibility, and display mode autosave under a versioned toolbar identity and
  are reused whenever AppKit recreates the main workspace toolbar. Toolbar instances sharing that
  identity synchronize changes immediately.
- Dynamic toolbar items keep live behavior after removal and re-addition: Start/Stop follows proxy
  state, Bottom Inspector follows selection and panel visibility, and Context Dock tooltips follow
  its visible state.

---

## 2. Sidebar (Left Column)

### Structure
```
▼ Favorites
    ★ Pinned                               (0)
    📁 Saved Sessions                       (3)
▼ All
    ▶ Apps                                  (12)
        Safari                          (245)
        Xcode                           (89)
        MyApp                           (1,203)
    ▶ Domains                               (47)
        api.example.com                 (892)
        cdn.example.com                 (156)
        graphql.example.com             (45)
▼ Analytics
    ⚠ Errors                                (23)
    ⏱ Performance
    📈 Trends
─────────────────────
[+]                              [⚙ ⌘⇧F]
```

### Typography

| Element | Font | Size | Weight | Color |
|---------|------|------|--------|-------|
| Section header | .systemFont | 11pt | .medium | .secondaryLabelColor |
| Item label | .systemFont | 13pt | .regular | .labelColor |
| Count badge | .monospacedDigitSystemFont | 11pt | .regular | .tertiaryLabelColor |
| Nested item | .systemFont | 12pt | .regular | .labelColor |

### Styling
- List style: `.sidebar`
- Row height: 24pt (standard sidebar row)
- Selection: System accent color highlight (rounded corners)
- Disclosure triangles: System default (SF Symbol `chevron.right` rotating to `chevron.down`)
- Section spacing: 8pt between sections
- Icons: 16pt SF Symbols, `NSColor.secondaryLabelColor`
- Count badges: Right-aligned, tertiary label color, no background

### Bottom Bar (28pt)
- Background: `NSColor.windowBackgroundColor`
- Top border: 1pt `NSColor.separatorColor`
- Plus button: `plus` SF Symbol, borderless
- Filter button: `line.3.horizontal.decrease` SF Symbol with "⌘⇧F" accessory text
- Padding: 8pt horizontal

---

## 3. Protocol Filter Bar (28pt height)

### Layout
```
┌──────────────────────────────────────────────────────────────────────────────────────┐
│ [All] [HTTP] [HTTPS] [WebSocket] [JSON] [XML] [JS] [CSS] [GraphQL] [Doc] [Media]  │ [2xx] [3xx] [4xx] [5xx]  [Reset]
└──────────────────────────────────────────────────────────────────────────────────────┘
  ← Content Filters ─────────────────────────────────────────────────────────────→ | ← Status Filters ──────→
```

### Pill Button Styling

| State | Background | Foreground | Font Weight |
|-------|-----------|------------|-------------|
| Active | `Color.accentColor.opacity(0.15)` | `Color.accentColor` | `.semibold` |
| Inactive | `Color.clear` | `Color.secondary` | `.regular` |
| Hover | `Color.secondary.opacity(0.08)` | `Color.secondary` | `.regular` |

- Font size: 11pt
- Corner radius: 4pt
- Padding: 8pt horizontal, 3pt vertical
- Pill spacing: 2pt
- Section divider: 0.5pt vertical, 16pt tall, `NSColor.separatorColor`
- Bar padding: 8pt horizontal, 4pt vertical
- Bottom border: 1pt `NSColor.separatorColor`
- Reset button: Tertiary style, appears only when filters active
- Scrollable: `ScrollView(.horizontal, showsIndicators: false)`

---

## 4. Request Table (NSTableView)

### Column Specifications

| Column | Width | Min | Alignment | Font | Content |
|--------|-------|-----|-----------|------|---------|
| # | 40pt | 30pt | Right | Monospaced 11pt, secondary | Row number |
| URL | 300pt | 200pt | Left | Monospaced 12pt, primary | Request path, truncated |
| Client | 100pt | 60pt | Left | System 11pt, secondary | App name |
| Method | 60pt | 50pt | Center | System 11pt, bold | Colored badge |
| Code | 50pt | 40pt | Center | Monospaced 11pt, medium | Colored text |
| Time | 80pt | 60pt | Right | Monospaced 11pt, secondary | HH:mm:ss |
| Duration | 70pt | 50pt | Right | Monospaced 11pt, secondary | "245ms", "1.2s" |
| Size | 70pt | 50pt | Right | Monospaced 11pt, secondary | "24.5 KB" |
| Query Name | 100pt | 60pt | Left | System 11pt, secondary | GraphQL op name |

### Row Styling
- Height: 22pt (fixed)
- Intercell spacing: 4pt horizontal, 0pt vertical
- Alternating backgrounds: `NSColor.controlBackgroundColor` / `NSColor.alternatingContentBackgroundColors[1]`
- Selection: `Color.accentColor.opacity(0.2)`
- Multi-select enabled
- Sortable by all columns (click header)

### Method Badge Colors
| Method | Color |
|--------|-------|
| GET | `.systemBlue` |
| POST | `.systemGreen` |
| PUT | `.systemOrange` |
| PATCH | `.systemYellow` |
| DELETE | `.systemRed` |
| HEAD | `.systemPurple` |
| OPTIONS | `.secondaryLabelColor` |

### Status Code Colors
| Range | Color |
|-------|-------|
| 2xx | `.systemGreen` |
| 3xx | `.systemBlue` |
| 4xx | `.systemOrange` |
| 5xx | `.systemRed` |

### Method Badge Component
- Font: 11pt, bold, monospaced, caption2
- Background: method color at 0.15 opacity
- Corner radius: 3pt
- Fixed width: 44pt
- Text: uppercased, centered

---

## 5. Status Bar (22pt height)

### Layout
```
┌──────────────────────────────────────────────────────────────────┐
│  847 requests                                    ● Listening :9090 │
│  ← left-aligned                                  right-aligned → │
└──────────────────────────────────────────────────────────────────┘
```

### Content Rules
- **No selection**: `"{count} requests"` (or `"No requests"`)
- **With selection**: `"{selected} of {count} selected"`
- **Proxy running**: Green circle (8pt) + `"Listening on :{port}"`
- **Proxy stopped**: Gray circle (8pt) + `"Proxy stopped"`

### Styling
- Font: `.caption` (11pt), `NSColor.secondaryLabelColor`
- Background: `NSColor.windowBackgroundColor`
- Top border: 1pt `NSColor.separatorColor`
- Padding: 8pt horizontal, 4pt vertical
- Circle size: 8pt diameter

---

## 6. Inspector Panel (Right Column)

### URL Bar (32pt height)
```
┌──────────────────────────────────────────────────────────────────┐
│ [GET] [200 OK]  https://api.example.com/v2/users?page=1&limit=20│
│  ↑       ↑        ↑                                              │
│ method  status    full URL (monospaced, truncated middle)        │
└──────────────────────────────────────────────────────────────────┘
```

- Background: `NSColor.controlBackgroundColor`
- Padding: 8pt horizontal, 6pt vertical
- URL font: `.monospacedSystemFont(ofSize: 11)`, selectable
- URL truncation: `.truncationMode(.middle)`
- Bottom border: 1pt `NSColor.separatorColor`

### Inspector Split (Below URL Bar)
```
┌──────────────────────┬──────────────────────┐
│   REQUEST INSPECTOR  │  RESPONSE INSPECTOR  │
│                      │                      │
│  [Headers][Query]... │  [Headers][Body]...  │
│  ─────────────────── │  ─────────────────── │
│                      │                      │
│  Header Name  Value  │  Header Name  Value  │
│  Accept     text/htm │  Content-Type  app/j │
│  Host       api.exam │  Cache-Control no-ca │
│  ...                 │  ...                 │
│                      │                      │
└──────────────────────┴──────────────────────┘
   min 250pt each         min 250pt each
```

### Tab Button Styling (Underline Style)

| State | Font | Weight | Indicator |
|-------|------|--------|-----------|
| Active | 11pt | `.bold` | 2pt accent color underline |
| Inactive | 11pt | `.regular` | None |

- Tab bar padding: 8pt horizontal, 4pt vertical
- Tab spacing: 12pt between tabs
- Bottom border below tab bar: 1pt `NSColor.separatorColor`
- Horizontal scroll if too many tabs

### Request Inspector Tabs
1. **Headers** — Two-column grid (Name | Value), monospaced 11pt
2. **Query** — Two-column grid (Name | Value), parsed from URL
3. **Body** — Raw text or formatted (JSON tree, form data)
4. **Cookies** — Table (Name | Value | Domain | Path | Flags)
5. **Raw** — Full HTTP request as plain text, monospaced
6. **Synopsis** — Metadata table (Method, URL, Host, Path, Version, Status, Content-Type, Size, Duration, Client)
7. **Comments** — User annotations (empty state default)

### Response Inspector Tabs
1. **Headers** — Two-column grid (Name | Value)
2. **Body** — Auto-formatted by Content-Type (JSON tree view, raw text, hex)
3. **Set-Cookie** — Per-cookie detail (name, value, domain, path, secure, httponly flags)
4. **Auth** — Authorization header analysis (Bearer/Basic/Digest type detection)
5. **Timeline** — Timing waterfall with colored phase bars

### Empty State (No Selection)
```
┌──────────────────────────────┐
│                              │
│       [rectangle.split icon] │
│                              │
│    Select a request to       │
│    view its details          │
│                              │
└──────────────────────────────┘
```
- Uses `ContentUnavailableView`
- Icon: 32pt SF Symbol, `NSColor.tertiaryLabelColor`
- Title: 14pt medium, `NSColor.secondaryLabelColor`

---

## 7. States

### State 1: Populated (Traffic Flowing)
- All 3 columns visible
- Table populated with requests
- Inspector showing selected request details
- Status bar showing count + proxy running

### State 2: Empty (No Traffic)
- Sidebar visible (empty domain tree)
- Center shows `ContentUnavailableView`:
  - Icon: `network` SF Symbol
  - Title: "No Traffic Captured"
  - Description: "Start the proxy to begin capturing network traffic"
  - Action: "Start Proxy" button
- Inspector hidden or showing "No Selection"

### State 3: Inspector Hidden
- Sidebar + Center fill window width
- Table expands to fill available space
- Toggle via toolbar button or keyboard shortcut

### State 4: Proxy Stopped
- Status bar: gray dot + "Proxy stopped"
- Toolbar: Start button shows `play.fill`
- Existing captured traffic remains visible

---

## 8. Keyboard Shortcuts

| Action | Shortcut | Context |
|--------|----------|---------|
| Start Proxy | — | Toolbar or Tools menu |
| Stop Proxy | ⌘. | Global |
| Clear Session | ⌘K | Global |
| Pause/Resume Recording | ⌥⌘R | Main capture window |
| Toggle Inspector | ⌘I | Main window |
| Navigate rows | ↑↓ | Table focused |
| Copy URL | ⌘C | Row selected |
| Toggle sidebar filter | ⌘⇧F | Sidebar |

---

## 9. Animations

| Transition | Animation | Duration |
|-----------|-----------|----------|
| Panel show/hide | `.spring(response: 0.35, dampingFraction: 0.8)` | ~350ms |
| Data updates | `.easeInOut` | 200ms |
| Filter toggle | Linear | 150ms |
| Sidebar collapse | `.easeInOut` | 300ms |
| Row selection | None (instant) | — |

---

## 10. Dark Mode

All colors use semantic system names — no hex values. Both appearances handled automatically:

| Element | Light | Dark | System Name |
|---------|-------|------|-------------|
| Window bg | White | #1E1E1E | `.windowBackgroundColor` |
| Table row even | White | #1E1E1E | `.controlBackgroundColor` |
| Table row odd | #F5F5F5 | #2A2A2A | `.alternatingContentBackgroundColors[1]` |
| Dividers | #D1D1D6 | #3D3D41 | `.separatorColor` |
| Primary text | Black | White | `.labelColor` |
| Secondary text | #8A8A8E | #8D8D93 | `.secondaryLabelColor` |
| Selection | Blue tint | Blue tint | `.selectedContentBackgroundColor` |

---

## 11. Accessibility

- All interactive elements have VoiceOver labels
- Status indicators use color + shape (not color alone)
- Minimum touch target: 22pt (matches row height)
- Focus rings: 1pt accent color, 2pt offset
- Dynamic Type: Respects system text size settings
- Column headers announce sort state to VoiceOver
- Tab buttons announce active/inactive state
