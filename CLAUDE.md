# Working on DisplayDial

A SwiftUI menu bar app that controls an external monitor over DDC/CI by running
[m1ddc](https://github.com/waydabber/m1ddc). See [README.md](README.md) for the user-facing
picture; this file is the part it doesn't say out loud.

Everything here was measured on an **LG UltraGear 34GS95QE over DisplayPort, on an Apple
Silicon MacBook running macOS 27**. A claim about another monitor is a guess until someone
with that monitor confirms it.

## How work happens here

**Work on `development`; `main` is what ships.** Changes reach `main` by pull request, and the
`build` check has to be green before one is merged. CI runs on pull requests and on pushes to
`main` only.

```
development  →  pull request  →  CI  →  main
```

Pushing to `development` deliberately spends no CI run. What matters about a commit there is
whether it survives the pull request, which is where the build runs.

**Every pull request raises the version and says what changed.** `make bump` adds one to the
patch number (`PART=minor` or `PART=major` for the others), and the pull request adds a
`## <version> (<date>)` section to `CHANGELOG.md`, written for people who use the app, not for
reviewers. CI fails a pull request whose `VERSION` isn't higher than its base branch's, or has
no changelog section for it. Settings › About shows the version, so the owner can tell which
build is installed.

**No AI attribution.** Commits and pull requests carry no `Co-Authored-By: Claude` trailer and
no "Generated with Claude Code" line. The trailer makes GitHub list Claude as a contributor,
and the owner has asked for that not to happen. This overrides any default that says otherwise.

### Commit messages

**[Conventional Commits](https://www.conventionalcommits.org).**

```
type(scope): summary in the imperative, lower case, no full stop
```

`type` is one of **feat, fix, docs, test, build, ci, refactor, perf, chore, revert**. `scope` is
the part of the repo it lands in, **ddc, app, ui, build, ci**, and is left off when a change
spans everything. Keep the subject under about 72 characters.

| Scope | Covers |
|---|---|
| `ddc` | `Model/M1DDC.swift`: running m1ddc, parsing its output, the serial queue and timeout |
| `app` | the rest of `Sources/DisplayDial/Model` and `App`: state, presets, defaults, hot keys |
| `ui` | `Sources/DisplayDial/Views` |
| `build` | `Makefile`, `build.sh`, `Package.swift`, `Scripts/`, the icon |
| `ci` | `.github/` |

```
fix(ddc): give up on an m1ddc call after 5 seconds
feat(ui): confirm before switching inputs
docs: explain the stale-read guard in CLAUDE.md
```

**A body is for *why*, and only when why is not obvious.** A one-line change does not need one;
a decision, a trap, or a bug whose cause is not visible in the diff does. What the change does
is already in the diff.

`git config commit.template .gitmessage` puts the format in front of you while you write.

## Commands

Everything runs from the Makefile; `make` on its own lists every target.

```sh
make build       # Debug build, a compile check
make release     # Release build, packaged as build/DisplayDial.app
make test        # unit tests, against a fake m1ddc
make live-test   # read-only check against the connected monitor
make run         # Release build, then launch it (quits a running copy first)
make shot        # PNGs of the panel in build/screenshots (TAB=general|presets|about adds Settings)
make icon        # redraw Resources/AppIcon.icns
make bump        # raise VERSION (PART=minor|major)
```

## Layout

```
Sources/DisplayDial/
  App/              entry point, window snapshots
  Model/            M1DDC (process wrapper and parsing), MonitorModel, presets, hot keys, preferences
  Views/            the menu bar panel and its menu-item styles
  Views/Settings/   one file per Settings tab
Tests/DisplayDialTests/   Swift Testing; FakeRunner stands in for m1ddc
Resources/AppIcon.icns    checked in; Scripts/make-icon.swift draws it
```

It's a Swift package, not an Xcode project: `build.sh` wraps the executable into an app bundle
and writes its Info.plist. The deployment target is **macOS 26**, for the Liquid Glass APIs;
the language mode is **Swift 5**.

## Things that will bite you

**m1ddc's help undersells it.** `get mute` and `get input` work although they aren't listed.
Mute reads `1` (on) or `2` (off). A read straight after a write once returned `9388`, so
anything outside 1 and 2 is ignored rather than trusted.

**LG monitors switch inputs only with `input-alt`, but report with the standard code.**
`set input-alt 144` switches to HDMI 1; `get input` then says `17`. `InputSource(code:)`
accepts either. The setting is on by default and only matters for other brands.

**One m1ddc process at a time, reads included.** A DDC read is an I2C write then a read, and
another process's write landing in between corrupts the reply. `M1DDC` wraps its runner in a
`SerialRunner` (FIFO), so keep the one `M1DDC` the model holds rather than making new ones: each
has its own queue. Every call has a 5-second timeout; a hung call used to block every later
read and write until relaunch.

**A read that overlaps a write is stale.** A refresh can be reading a value while the user drags
its slider. `MonitorModel` counts writes per display and property (`writeGeneration`) and drops
any read that started while one was queued or sent, instead of snapping the slider back. Writes
are coalesced, so a drag sends the latest value, not every value. A failed write triggers a
read-back so the slider doesn't keep showing a value the monitor never got.

**Writes remember their display.** The selection can change while a preset's writes are still
queued; they go to the monitor they were made for, not whichever is selected when they're sent.

**`refresh()` coalesces; it never drops a call.** A call during a refresh waits for it and makes
it go round again, and a refresh stops reading as soon as the selection changes. Dropping calls
used to leave the panel showing one monitor's values under another's name, and lose keyboard
nudges pressed before the first read landed.

**Readings outside `0...max` are ignored**, like the garbage mute readings, and never saved as a
monitor's default. Writes are clamped to the monitor's range.

**Apple panels show up in `display list`.** The built-in screen (and a Studio Display) report
vendor `0x0610` and don't speak DDC; they're filtered out.

**"Default" brightness and contrast are DisplayDial's, not the monitor's.** The factory reset
is VCP `0x04`/`0x05`, which m1ddc can't send. So each monitor's defaults (keyed by display UUID)
start as the first values DisplayDial reads from it, and can be edited in Settings › Presets. A
snapshot copy never records them.

**Keyboard shortcuts can fire before the panel was ever opened.** `nudge` reads the monitor
first when it has no value yet, or the step would start from the slider's placeholder.
Shortcuts use Carbon's `RegisterEventHotKey`: no Accessibility permission, and registration
fails rather than stealing a combination something else owns. Settings marks those.

**Agents can't take screenshots here.** There's no Screen Recording permission and no
AppleScript to System Events. `make shot` has the app render its own windows with
`cacheDisplay`; the panel gets a window of its own, since a menu bar panel can't be opened
from code. Liquid Glass doesn't show up in those captures. A snapshot copy reads the monitor but
never writes to it (`RunMode.isReadOnly`), so it can run beside the copy in use.

**Don't `pkill DisplayDial` while testing** other than through `make run`, which means to
replace the running copy. Stop anything else you launch by its PID.

**Input switching hasn't been tried on hardware.** Switching away from DisplayPort blanks the
Mac's screen, and the Mac may then not see the monitor to switch back. That's why the panel
asks before switching rather than acting on one click.

**Launch at login is untested.** `SMAppService.mainApp.register()` may refuse an ad hoc
signed app outside ~/Applications; the toggle surfaces whatever error it returns.

## Testing

`make test` covers parsing, input codes, presets, coalescing, serialization, the stale-read
guard, refresh coalescing, display targeting, read-only mode and shortcuts' `nudge`. Tests use
their own `UserDefaults` suite, never `.standard`, which is the owner's real settings;
`MonitorModel` has no default for it on purpose. `UserDefaults.scratch()` names each suite by an
absolute path in a temporary folder: named suites in ~/Library/Preferences were rewritten by
cfprefsd after the tests deleted them, and once numbered in the hundreds.

**Stage races with gates, not delays.** `FakeRunner.hold(where:)` keeps matching calls from
answering until `release()`, so a test decides exactly what's in flight. Delay-based versions of
these tests passed with the stale-read guard deleted. When changing the guard, delete it and
check `changeDuringReadIsNotOverwrittenByStaleValue` fails.

| What | How |
|---|---|
| it compiles | `make build`, `make release` |
| the logic holds | `make test` |
| it reads the monitor | `make live-test` |
| it looks right | `make shot`, then read the PNGs |

## CI

`.github/workflows/ci.yml` runs `make build`, `make release` and `make test` on a macOS 26
runner for every pull request and every push to `main`, and on pull requests checks the version
was raised and has a changelog section. No monitor is involved; CI proves the project compiles
and its logic holds, not that DDC works.

Actions are pinned to commit SHAs, not tags: a tag is mutable, so `@v5` is a promise the
action's owner can rewrite. The trailing comment is the human-readable version. Dependabot
keeps them current.

Releases aren't automated yet; there is no packaging step beyond `make release`.

## Style

Explain *why* in comments, not *what*. Native SwiftUI and AppKit controls over custom ones;
`Form` with `.formStyle(.grouped)` for anything that looks like settings; the panel's rows use
`MenuItemButtonStyle` so they look like the items in the system's own panels. Strings built in
code and later shown are written `String(localized:)`. No third-party dependencies.
