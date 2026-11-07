# Changelog

Every pull request raises the version (`make bump`) and adds a section here for it, written for
people who use the app.

## 1.4.0 (2026-11-07)

The first version in this repository.

* Control an external monitor from the menu bar: brightness, contrast, volume and mute, and
  input switching, with LG's alternate input codes on by default.
* Presets, saved from the menu bar and renamed or deleted in Settings.
* Reset brightness and contrast to each monitor's defaults, which start as the values first read
  from it and can be changed in Settings › Presets.
* Optional keyboard shortcuts: ⌃⌥⌘↑ and ⌃⌥⌘↓ change brightness without opening the menu.
* Switching inputs asks first, since switching away can leave the Mac's screen dark.
* Reads and writes go to the monitor one at a time, each change goes to the monitor it was made
  for, and a monitor that stops answering no longer freezes the app.
