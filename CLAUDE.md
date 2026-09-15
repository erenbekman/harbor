# CLAUDE.md

## What this is

**Harbor** — a macOS app (Swift 6 + SwiftUI + AppKit, no dependencies) that keeps a
rail of projects and starts/stops each project's dev services. Claude Studio is the
reference for the tmux and process handling; Harbor is deliberately only the services
half of it.

## Commands

```bash
swift build      # fast compile check
./build.sh       # release build + Harbor.app
./install.sh     # build + install into /Applications + launch
```

`VERSION` is read by `build.sh` for the bundle version.

## Layout

```
Sources/Harbor/
├── main.swift          # AppKit entry point (no WindowGroup)
├── AppDelegate.swift   # window + menu bar item + main menu
├── Models.swift        # Project, Service, ServiceStatus
├── Theme.swift         # every color and metric
├── Core/
│   ├── Paths.swift     # ~/Library/Application Support/Harbor
│   ├── Shell.swift     # PATH snapshot, process helpers, ps tree, lsof
│   ├── Tmux.swift      # sessions services run in
│   ├── Store.swift     # projects.json + service detection
│   ├── Runner.swift    # start/stop, the 2 s poll, health, crashes, restarts
│   ├── Terminals.swift # attach in a terminal, open in an editor, free a port
│   ├── Notify.swift    # osascript notifications
│   └── HotKey.swift    # the global ⌃⌘H
└── Views/              # RootView (rail), ServicesPanel (rows + log), Sheets,
                        # Palette (the quick switcher)
```

## Hard-won rules

- **tmux takes a fixed `-S /tmp/harbor-<uid>.sock`**, never `-L`: a GUI process and a
  login shell see different `TMUX_TMPDIR` and would land on two servers.
- **tmux needs a UTF-8 locale and launchd does not give one.** In the C locale tmux
  turns every byte it considers unprintable into `_`, including the TAB its formats
  separate fields with — the parse then collapses to one field and every service reads
  as "not running". `Tmux.run` forces `LANG` unless the inherited one is already UTF-8.
- **`remain-on-exit` is set from INSIDE the pane, before the command runs.** Setting it
  from outside a moment later is a race a fast-failing service wins: the pane dies, the
  session goes, and the output that says why is gone with it.
- **`Project.shortID` is FNV-1a, never `hashValue`** — Swift seeds that per process, so
  every tmux session would be orphaned on the next launch.
- **Spawning is `/bin/zsh -l -i -c`** and `Shell.userPath` is injected: a GUI app
  inherits a minimal PATH, and `node`/`php` live in a PATH exported from `.zshrc`.
- **`lsof` needs `-a`.** It ORs its selection criteria, so `-p <pids> -iTCP -sTCP:LISTEN`
  without it reports every listening socket on the machine. And the pane's pid is the
  SHELL — the process tree has to be walked to reach the server it started, which is
  why `Shell.processTree()` exists instead of a `pgrep` per service.
- **One poll answers for every service**: `list-panes -a`, one `ps`, one `lsof`. A fork
  per service twice a second is what this avoids.
- **Never publish an unchanged value** (`Runner.apply`): an `@Published` write
  invalidates every view that reads it, and this runs forever.
- **Never `Process.waitUntilExit()`** — it pumps the run loop, so on the main thread it
  re-enters AppKit underneath its own caller. `Shell.barrier` waits on the termination
  handler instead.
- **`Service` and `Project` decode BY HAND.** The synthesized decoder throws on a key
  that is missing even where there is a default, so `autoStart`/`autoRestart`/`health`
  would have failed the whole array and silently emptied every project on upgrade.
- **Auto-start ADOPTS a live pane.** `start` only kills the session when its pane is
  dead; otherwise a launch would restart the dev server that was already running —
  which is the one thing running services in tmux exists to avoid.
- **A port is not an answer.** With `health` set, the dot goes green only when the URL
  responds; the pane being alive makes it yellow, not green. Without one the port is
  all there is, and that is what the dot means.
- **The port in a crash is read off the SCREEN**, because every runtime words it
  differently (`EADDRINUSE`, "address already in use", "Port 3000 is already in use").
  Only for a service that JUST died — capturing a pane per poll would be a fork per
  failed service forever — and Python's message carries no port at all, so the banner
  simply does not appear rather than naming the wrong one.
- **Notifications go out on the TRANSITION**, never on the state: `.failed` is a
  standing value and announcing it per poll is how a warning becomes noise. Auto-restart
  stops after three consecutive tries, and the counter only resets on a manual
  start/stop — a service that cannot bind will not be restarted forever.
- **The global shortcut is Carbon** (`RegisterEventHotKey`): `NSEvent`'s global monitor
  would need the Accessibility permission for the same keystroke. The palette is an
  `NSPanel` subclass overriding `canBecomeKey` — a borderless panel takes no keystrokes
  otherwise, and a switcher that cannot be typed into is decoration.
- **Closing the window does not quit the app** (menu bar item stays), and quitting does
  NOT stop services — that is the entire point of running them in tmux.

## Design

Native and restrained: macOS semantic colors, system font, no decoration. New colors
or metrics go in `Theme.swift` and nowhere else.
