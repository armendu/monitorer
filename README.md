# Monitorer

A macOS menu bar app for controlling an external monitor over DDC/CI, built on [m1ddc](https://github.com/waydabber/m1ddc): brightness, contrast, volume and mute, input switching (with LG's alternate input codes), saved presets, a one-click return to each monitor's default brightness and contrast, and optional global shortcuts (⌃⌥⌘↑ / ⌃⌥⌘↓) for brightness.

Requires an Apple Silicon Mac, macOS 26 or later, and m1ddc:

```bash
brew install m1ddc
```

## Commands

Everything runs from the Makefile; `make` on its own lists every target.

```sh
make build       # Debug build, a compile check
make release     # Release build, packaged as build/Monitorer.app
make test        # unit tests, no monitor needed
make live-test   # read-only check against the connected monitor
make run         # Release build, then launch it (quits a running copy first)
make shot        # PNGs of the menu bar panel in build/screenshots
make shot TAB=presets   # …plus Settings on that tab (general | presets | about)
make install     # copy to ~/Applications, where Launch at login expects it
make icon        # redraw Resources/AppIcon.icns from Scripts/make-icon.swift
make bump        # raise the version in VERSION (PART=minor|major)
```

## Layout

```
Sources/Monitorer/
  App/              entry point, window snapshots
  Model/            m1ddc wrapper, MonitorModel, presets, preferences
  Views/            menu bar panel and its menu-item styles
  Views/Settings/   one file per Settings tab
Tests/MonitorerTests/   Swift Testing, against a fake m1ddc
Resources/AppIcon.icns    checked in; drawn by Scripts/make-icon.swift
```

## Things worth knowing

- **Turn on DDC/CI** in the monitor's on-screen menu. DDC often doesn't pass through docks or hubs, nor the built-in HDMI port on M1 and base M2 Macs.
- **LG monitors switch inputs only with m1ddc's `input-alt` addressing**, but report the current input with the standard code. Settings › General › Use LG input codes; turn it off for other brands.
- **`m1ddc get mute` and `get input` work** even though m1ddc's help doesn't list them. Mute reads 1 (on) or 2 (off); a read straight after a write can return garbage, which the app ignores.
- **A read that overlaps a write is stale.** The model drops it rather than snapping the slider back (`writeGeneration`), and coalesces slider drags into one write per value.
- **Agents can't take screenshots here** (no Screen Recording permission). `make shot` has the app render its own windows; the menu bar panel gets a window of its own, since a panel can't be opened from code. Liquid Glass doesn't show up in these captures. Snapshot copies read the monitor but never write to it (`RunMode.isReadOnly`), so they can run beside the copy in use.
- Tested on an LG UltraGear 34GS95QE on HDMI 1: brightness, contrast, volume and mute read and write correctly. The LG can't report which input it's showing (it always answers DisplayPort), so the menu shows the input Monitorer last switched to. Input switching hasn't been tried, since switching away blanks the Mac's screen.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md). Monitorer is released under the [MIT License](LICENSE).
