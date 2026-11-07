# Security policy

Monitorer runs as you, with no helper, no root access and no network access. It starts
`m1ddc` from Homebrew (`/opt/homebrew/bin` or `/usr/local/bin`) to talk to the monitor over
DDC/CI, and only ever passes it the commands in `Sources/Monitorer/Model/M1DDC.swift`:
listing displays, and reading or setting brightness, contrast, volume, mute and input.

A vulnerability would be a way to make Monitorer run something else, pass m1ddc other
arguments, or affect anything other than the monitor's picture, sound and input. Code that can
already write to your Homebrew folder can replace m1ddc itself, so that is out of scope.

## Reporting a vulnerability

**Please don't open a public issue.** Report it privately through GitHub's
[private vulnerability reporting](https://github.com/armendu/monitorer/security/advisories/new).

Please include what an attacker can do and what access they need to start with, steps to
reproduce it, and the macOS version and Monitorer commit you tested.

You should get an acknowledgement within a week. Once a fix is ready, the advisory will be
published and you'll be credited unless you'd rather not be.

## Supported versions

Only the latest version on `main` is supported.
