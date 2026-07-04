# Changelog

All notable changes to Digi Station are recorded here. The latest section is
also used as the **GitHub Release notes** (the in-app updater shows the release
body to whoever installs the update).

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
