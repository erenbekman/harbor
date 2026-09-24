# Harbor

A rail of projects, and every project's dev servers one click away.

Harbor is a small native macOS app for the thing you do before you write any code:
starting `npm run dev` in one folder, `php artisan serve` and a queue worker in
another, a `docker compose up` somewhere else — and then remembering which of them is
still running. Add a folder, Harbor finds what it obviously runs, and each service
becomes a row with a start button, the port it is actually listening on, and its live
output.

Services run inside **tmux**, so they outlive the app: quit Harbor and your dev server
keeps serving. Open it again and it is still there, still green, still on `:3000`.

Most of the time you never open the window at all: a column of project chips sits on
the right edge of the screen, above whatever you are working in, and opens under the
pointer.

```
                                        ┌──┐        ┌──────────────────────┐
                                        │N │        │ ──                   │
   the edge strip, closed  ─────────────│Ü │  hover │ ● nott             ⌄ │
                                        │A │  ────► │   ▶ dev              │
                                        └──┘        │     stopped          │
                                                    │ ● üstad            ⌄ │
                                                    │   ■ serve            │
                                                    │     running · :8000  │
                                                    └──────────────────────┘

┌──────────────┬──────────────────────────────────────────────┐
│ ● nott       │  nott                    ▶ Start all  ■ Stop  │
│ ● üstad   ●2 │  ~/Documents/GitHub/nott                      │
│ ● api        │  ┌──────────────────────────────────────────┐ │
│              │  │ ■  dev                                 › │ │
│ + Add project│  │    ● running · :3000                     │ │
│              │  └──────────────────────────────────────────┘ │
│              │  ┌──────────────────────────────────────────┐ │
│              │  │ ▶  horizon                             › │ │
│ ‹ Collapse   │  │    ● stopped                             │ │
└──────────────┴──────────────────────────────────────────────┘
```

## Install

```bash
git clone https://github.com/erenbekman/harbor.git
cd harbor
./install.sh
```

`install.sh` builds a release bundle, installs it into `/Applications` and launches it.
It installs tmux with Homebrew if you do not have it. macOS 14+.

The app is ad-hoc signed, so the first launch may need right-click → Open.

## What it does

**Projects.** Add a folder and it becomes a row in the rail. The sidebar shows project
names by default; `Collapse` turns it into a column of colored chips when you want the
space. Each project keeps its own color, its own services, and its own place in the
list.

**Service detection.** When you add a folder, Harbor reads it and offers what it finds
— `package.json` scripts (`dev`, `start`, `serve`, `watch`, with the right runner for
your lockfile: npm, pnpm, yarn or bun), Laravel's `artisan serve` plus Horizon or a
queue worker, Django's `runserver`, `docker compose up`. You tick the ones you want;
nothing is added behind your back.

**Ports are measured, not configured.** You never type a port into Harbor. When a
service is running, it walks the tmux pane's process tree and asks `lsof` what those
processes are actually listening on, so the row says `running · :3000` because
something really is on 3000 — and gives you a button that opens it in the browser.

**Live output.** The chevron on a row opens the last 300 lines of the pane, refreshed
while it is open. For anything interactive, right-click → *Open in Terminal* attaches
a real terminal to the same tmux session, so you can answer a prompt or press `r` to
reload.

**Crash handling.** A service that exits keeps its pane (`remain-on-exit`), so the
error that killed it stays on screen instead of disappearing with the session. The row
goes red with the exit code, and you get a notification. Turn on *Restart if it
crashes* and Harbor retries up to three times, then stops and leaves it alone.

**Port conflicts.** `EADDRINUSE` is the most boring way to lose five minutes. When a
service dies complaining that its port is taken, Harbor reads the port out of the
output, asks `lsof` who is holding it, and offers: `:3000 is held by node (4821) —
Free port`.

**Health checks.** An open port is not the same as an app that answers. Give a service
`/health` (or a whole URL) and the dot only turns green once that URL responds;
until then it stays yellow, which is the truth while a framework is still booting.

**The edge strip.** A 44pt column of project chips docked to the right edge of the
screen, above every app and on every Space. A chip fills with the project's color when
something in it is running. Hover it and it widens into the full list — every project
with its services, each with a start/stop button, its status and its port. It is a
non-activating panel, so pressing play does not pull focus away from your editor.
Drag it up or down to park it where you like; ⌘-click a project name to open it in the
window. Turn it off in Settings → General or in the menu bar item.

**Quick switcher.** `⌃⌘H` from anywhere, `⌘K` inside the app. Type a project or
service name, `Enter` starts or stops it. No window, no mouse.

**Menu bar.** The same projects and services live in a menu bar item, with a dot each,
so you can start the API without leaving what you are doing. Closing the window does
not quit the app, and quitting does not stop your services.

**Auto-start.** Mark a service *Start automatically* and it comes up with Harbor; mark
Harbor *Open at Login* and it comes up with the Mac. A service that is already running
in tmux is adopted, never restarted.

## Per service

| Field | What it does |
|---|---|
| Command | Run through your login shell (`zsh -l -i`), so your real PATH, nvm, asdf and aliases all work |
| Subfolder | Optional — run in `frontend/` while the project root is one level up |
| Health check | `/health`, or `http://localhost:8000/up`. Green means answering |
| Start automatically | Started when Harbor opens |
| Restart if it crashes | Up to three consecutive retries, with a notification each time |

## Status colors

| | Meaning |
|---|---|
| 🟢 | The tmux pane is alive — and, if a health check is set, the app is answering |
| 🟡 | Started, no pane yet, or up but not responding yet |
| 🔴 | The command exited. The pane is kept so the error stays readable |
| ⚪️ | Not running |

## How it works

Every service is one tmux session on a fixed socket (`/tmp/harbor-<uid>.sock`), named
from an FNV-1a hash of the project path, so the same folder maps to the same session on
every launch — that is what lets Harbor find services it did not start in this run.
`remain-on-exit` is set from inside the pane before the command runs, so even a service
that fails instantly leaves its output behind.

One poll every two seconds answers for every service at once: one `list-panes -a` for
liveness and exit codes, one `ps` for the process tree, one `lsof` for the ports. No
per-service polling, and nothing is published to the UI unless the value actually
changed.

Nothing is stored in your projects. Project and service definitions live in
`~/Library/Application Support/Harbor/projects.json`.

## Updates

Harbor updates itself. Settings → About shows the installed version and checks the
latest GitHub release; when a newer one exists the button becomes **Update to x.y.z** —
it downloads the release, swaps the bundle and relaunches. It also checks quietly at
launch, and an available update shows up in the menu bar item.

Your services are untouched by an update: they live in tmux, not in the app.

Cutting a release:

```bash
# bump VERSION, then
./dist.sh
gh release create v$(cat VERSION) Harbor.zip --title "Harbor v$(cat VERSION)" --notes "…"
```

The contract the updater relies on: the tag is `v<VERSION>` and the release ships an
asset named exactly `Harbor.zip`.

## Build from source

```bash
swift build      # fast compile check
./build.sh       # release build + Harbor.app
./install.sh     # build + install into /Applications + launch
```

No dependencies: Swift 6, SwiftUI and AppKit only. `CLAUDE.md` in the repo documents
the traps that shaped the implementation — the tmux locale bug, the `lsof -a` rule, the
hand-rolled `Codable` conformances — if you plan to change any of it.
