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
./dist.sh        # release artifact: Harbor.zip (the asset name the updater expects)
```

Release flow: bump `VERSION` → `./dist.sh` → commit and push →
`gh release create v<VERSION> Harbor.zip --title "Harbor v<VERSION>" --notes "…"`.
`VERSION` is the single source of truth — `build.sh` and `dist.sh` both read it, and
`Updater` compares the installed `CFBundleShortVersionString` against the tag.

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
│   ├── Updater.swift   # GitHub release self-updater
│   ├── Magic.swift     # "what does this project run?", asked of claude -p
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
- **Magic is READ-ONLY and does not write the answer anywhere.** `claude -p` runs with
  `--allowedTools Read,Glob,Grep`, and what comes back is a proposal the user ticks.
  Claude Studio let Claude write `services.json` itself; here a wrong command that
  appears in the sidebar on its own is worse than a missing one, and the file it would
  write is the app's global store, not something inside the project.
- **A child that waits on stdin waits forever.** A GUI process's stdin never reaches
  EOF, so `claude -p` sat there until the timeout — the CLI even says so ("no stdin data
  received in 3s") where a terminal is attached, and from the app there is no terminal
  to say it to. `Shell.run` hands every child `FileHandle.nullDevice`. The same call is
  `zsh -l` and NOT `-l -i`: without a tty an interactive zsh prints "can't change
  option: zle" into the output, and the PATH it was wanted for is injected already.
- **The CLI's own output is not the answer.** `--output-format json` wraps it, a warning
  line may precede it, and the model's JSON may arrive inside a code fence — so the JSON
  is CUT OUT of stdout (first `{` to last `}`), unwrapped once through `result`, and cut
  out again. Anything less broke on the first warning line.
- **The strip belongs to no window**, which is the point: you look at it while you are
  in the editor. A borderless `nonactivatingPanel` at `.statusBar` level with
  `canJoinAllSpaces`, so pressing play never pulls focus out of the app in front.
  Four things it cannot do without:
  `acceptsFirstMouse` is overridden on the hosting view, or the first click on a row is
  spent trying to activate a panel that cannot be activated;
  hover is an `NSTrackingArea` with **`.activeAlways`**, never SwiftUI's `onHover` —
  the panel is never key, and the only time the strip matters is when another
  application is in front;
  row heights are ARITHMETIC constants (`Strip.rowHeight`, `serviceHeight`, `gripHeight`),
  because AppKit animates the WINDOW FRAME and has to know the total before SwiftUI lays
  anything out;
  and the position is stored as a FRACTION of the screen (`stripCenter`), not a point —
  the panel changes height every time it opens, and a stored y would make it drift.
- **Closed it shows chips, not a sliver.** It was 6pt wide and technically visible;
  nobody aims at 6pt, and it said nothing about what was running. A 44pt column of the
  same chips the window's rail uses is a target and a status display at once.
- **Open, everything is listed.** Clicking a project to reveal its services made the
  strip a menu; the reason to look at it is to see what is running. The chevron now
  FOLDS a project away instead, and a folded project stays folded.
- **A running bundle cannot overwrite itself.** The updater unpacks the download, then
  hands the swap to a detached shell script (`rm -rf`, `ditto`, `xattr -cr`, `open`) and
  quits — the script outlives the app it is replacing. Services are in tmux, so an
  update never touches them.
- **Closing the window does not quit the app** (menu bar item stays), and quitting does
  NOT stop services — that is the entire point of running them in tmux.

## Design

Native and restrained: macOS semantic colors, system font, no decoration. New colors
or metrics go in `Theme.swift` and nowhere else.
