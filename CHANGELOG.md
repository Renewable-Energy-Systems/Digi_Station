# Changelog

All notable changes to Digi Station are recorded here. The latest section is
also used as the **GitHub Release notes** (the in-app updater shows the release
body to whoever installs the update).

## 2.1.4 — 2026-08-05

**Home screen**
- The dew point now flips to **OFFLINE** if the selected sensor stops sending
  for 60 seconds — even while the connection stays up — so a stale reading no
  longer shows as **LIVE** (e.g. when a sensor is set inactive in Dewpoint
  Monitor).
- Sensor Information layout fix: long workstation / sensor names now fit on one
  line and the values line up; the status badge and process-slip cards are equal
  width.

---

## 2.1.3 — 2026-07-29

**Connection & setup**
- New **Connection** section in Settings — the **Dewpoint live-feed server
  address** is now set on the tablet, so changing the server IP no longer needs
  an app rebuild. It stays read-only until you tap **Edit**, confirms before
  applying, and reconnects live on save.
- Settings setup flow reordered for a cleaner first-time setup.
- **Station & API now defaults to off** — a new station stays quiet (no ops
  calls) until you turn it on.

**Live Readings**
- Manual **Disconnect / Reconnect** control — pause or restore the live gauge
  feed on demand (persists until you reconnect or switch machines).

**Fixes**
- Home dashboard cards now fill the width on any tablet size.

---

## 2.1.2 — 2026-07-29

**Calibration reminders**
- The Home screen's Sensor Information card now shows a **calibration alert**
  based on the sensor's Calibration Due date:
  - **Overdue** (red) once the due date has passed.
  - **Due soon** (amber) within 30 days of the due date — including "due today".

**Under the hood**
- The release script now commits and pushes the version bump before tagging, so
  every release tag matches the released code.

---

## 2.1.1 — 2026-07-04

**Station flexibility**
- **Station & API can be turned off per station** (Settings → Station & API).
  Stations that don't use the ops server no longer fetch workstations or live
  process slips — and no longer show the related errors.
- **Settings now follow your layout.** If a screen is turned off in Layout &
  Navigation, its configuration is disabled with a shortcut to switch it back
  on — you can't pick a **Machine** while **Live Readings** is off, or choose
  videos while **Work Instructions** is off.

**Production hardening**
- Release builds use the **Production** ops API only — the LOCAL option (a
  development convenience) is hidden.
- In Production, the **Workstation Identity is chosen from the list only** — no
  free-typed IDs.
- The production ops API is now called over **HTTPS**.

---

## 2.1.0 — 2026-07-04

**New look & name**
- The app is now **Digi Station**, with a new RES-blue app icon.
- Redesigned **Settings** as a clean two-pane screen. Pick the connected
  **Machine** (HPM / CPM / APM / EPM) from selectable tiles.
- The old "Gauge" screen is now **Live Readings** (thickness & weight from the
  weighing balance / thickness gauge).

**New features**
- **Dew-point voice alert** — a spoken warning plays when the dew point goes
  outside the permitted range (in addition to the red/green indicator).
- The Home screen now shows a **"Configure sensor"** guide until a sensor is
  set up, instead of blank/placeholder values.
- **Faster navigation** — the "Configure videos" and "Choose a machine" buttons
  now open the exact Settings section directly.

**Fixes & improvements**
- Changing the machine now takes effect the moment you return to **Live
  Readings** — no app restart needed.
- Viewing the **Sensor Configuration** screen no longer drops the live
  dew-point reading; it only changes when you actually pick a new channel.
- The previous machine's **Pi temperature** no longer lingers after switching
  machines.
- **More reliable connections** — no more crash when a server is unreachable;
  faster, quieter reconnection to the dew-point and gauge servers.
- **Smoother startup and screen switching** — the Web Logs screen no longer does
  background work while it's off-screen, plus assorted startup optimizations.

**Under the hood**
- Cleaned up all analyzer warnings across the codebase.

---

## 2.0.4

- Dashboard performance and UI improvements for tablet operation.
- Real-time SSE listener for instant process-slip updates.
- Workstation dropdown fix, process-slip loading, and bottom-overflow UI fix.
