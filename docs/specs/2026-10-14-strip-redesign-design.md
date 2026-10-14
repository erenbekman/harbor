# Edge strip redesign — berth + arrival

2026-10-14

## Why

The strip reads as a flat list of coloured dots: the running badge is a 6pt dot in a
corner, the two states (closed chips, open rows) share nothing visually, and the "glass"
is `ultraThinMaterial` with a 20% black veil painted over it — which is what makes the
panel look cheap rather than translucent. The ship in the logo lives only in the menu
bar symbol, so the metaphor pays for nothing.

Direction chosen: the metaphor stays a hint and the app stays native. Motion only on a
state change, never ambient.

## 1. Closed strip — the berth

- Chip stays a 30pt squircle (radius 9); idle is `white 0.07` with the project's tint
  letter, running is the tint gradient with a white letter.
- The corner dot is removed. A running project draws a **wake**: a 14×2pt capsule in the
  project's tint, 3pt under the chip, pulsing between 0.45 and 1.0 opacity over 2.4s.
- The wake's 2pt is reserved whether or not it is drawn, so chips never shift.
- `closedHeight = padding*2 + n*chipSlot + (n-1)*chipSpacing`, `chipSlot = chipSize + 5`.

## 2. Open panel — arrival

- The closed chip and the open row's colour square are one element
  (`matchedGeometryEffect`, keyed by project id): opening flies the chip into the row.
- Rows stagger in: 28ms apart, 6pt from above, `spring(response: 0.3, damping: 0.85)`.
- A service's trailing state (port, exit code) crossfades from the trailing edge when the
  status changes.

## 3. Motion budget

| what | duration |
|---|---|
| panel open/close | 0.22s spring |
| row stagger step | 28ms |
| status change | 0.25s ease-out |
| wake pulse | 2.4s, autoreversing |

With `accessibilityReduceMotion`: no pulse, no stagger, plain crossfade.

Nothing animates on the two-second poll — `Runner` already publishes only changed
values, and that is what keeps this honest.

## 4. Material

`NSVisualEffectView` (`.hudWindow`, `.behindWindow`, `.active`) clipped to the panel
shape, replacing material + black veil. The 0.5pt top-lit hairline and the shadow stay.

## 5. Where the ship goes

- Menu bar: unchanged (`sailboat.fill`).
- Open panel with no projects: a `sailboat` symbol and "nothing docked yet".
- App icon: unchanged for now.

## 6. Unchanged

Height arithmetic as constants (AppKit animates the window frame and needs the total
before SwiftUI lays out), hover-to-open at the screen edge, drag to move, ⌘-click to open
in the window, the poll.
