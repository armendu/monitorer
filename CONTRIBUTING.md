# Contributing to Monitorer

Thanks for helping. Monitorer talks to real monitors, and monitors differ, so the bar for
changes that touch DDC is "tried on a real monitor, and you say which one". Everything else is
ordinary.

## Before you start

- **Bugs and small fixes:** open a pull request directly. If the bug isn't obvious, an issue
  first with your monitor model, how it's connected and your macOS version helps.
- **New features:** open an issue (or comment on an existing one) before writing much code, so
  we can agree on the shape first.
- **Security problems:** don't open a public issue. See [SECURITY.md](SECURITY.md).

## Setting up

You need an Apple Silicon Mac running macOS 26 or newer, Xcode 26 or newer, and m1ddc
(`brew install m1ddc`).

```sh
git clone https://github.com/armendu/monitorer.git
cd monitorer
git checkout development
git config commit.template .gitmessage
make run
```

`make` on its own lists every target.

## Branches and pull requests

```
development  →  pull request  →  CI  →  main
```

- Branch from `development` (or work on it directly if you have push access) and open your pull
  request **into `main`**.
- A pull request needs a green `build` check before it's merged.
- Keep a pull request to one change. Two unrelated fixes are two pull requests.
- Fill in the pull request template, especially the monitor section.

## Commit messages

[Conventional Commits](https://www.conventionalcommits.org):

```
type(scope): summary in the imperative, lower case, no full stop
```

- **Types:** feat, fix, docs, test, build, ci, refactor, perf, chore, revert
- **Scopes:** `ddc` (talking to m1ddc), `app` (the rest of the model), `ui` (views), `build`,
  `ci`. Leave the scope off if a change spans everything.
- Keep the subject under about 72 characters.
- Use the body to explain *why*, when that isn't obvious from the diff.

## Testing your change

1. `make build` and `make release` both succeed with no new warnings, and `make test` passes.
   The tests need no monitor; add one for logic you change where you can.
2. `make bump` to raise the version, and add a section for that version to
   [CHANGELOG.md](CHANGELOG.md) saying what changed for people who use the app. CI checks both.
3. `make run` and look at what you changed. `make shot` saves PNGs of the menu bar panel and
   Settings to `build/screenshots/`, handy for the pull request description.
4. **If your change touches DDC**, try it on your own monitor and say which one in the pull
   request. `make live-test` checks that readings work, without changing anything.

## Code style

- Match the code around you: naming, structure, comment density.
- Comments explain *why*, not *what*.
- Prefer native SwiftUI and AppKit controls; use `Form` with `.formStyle(.grouped)` for
  settings-like screens.
- No third-party dependencies.

[CLAUDE.md](CLAUDE.md) lists the non-obvious traps in this codebase: what m1ddc really returns,
LG's input codes, stale reads and why calls are serialized. It's worth reading before touching
the model.

## Code of conduct

This project follows the [Contributor Covenant](CODE_OF_CONDUCT.md). Be kind.

## License

By contributing, you agree that your contributions will be licensed under the
[MIT License](LICENSE).
