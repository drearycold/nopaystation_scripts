# Repository Guidelines

## Project Structure & Module Organization

This repository is a flat collection of command-line utilities. `nps_*.sh` scripts handle individual download workflows: games, DLC, updates, PSM/PSP titles, TSV snapshots, bundles, changelogs, and region batches. Shared shell helpers—including configuration loading, downloader selection, checksum checks, and title-ID validation—belong in `functions.sh`; `config.example` documents per-user directory settings. `pyNPU.py` queries update metadata and formats links or changelogs. User-facing setup and examples live in `README.md`. There is currently no dedicated test or asset directory.

## Build, Test, and Development Commands

There is no build step; scripts run directly after dependencies from `README.md` are installed.

- `chmod +x nps_*.sh pyNPU.py` restores executable permissions.
- `for f in *.sh; do sh -n "$f" || exit; done` checks shell syntax without downloading content.
- `python3 -m py_compile pyNPU.py` checks Python syntax.
- `./pyNPU.py -h` and `./nps_region.sh --help` inspect supported options.
- `./nps_game.sh /path/to/GAME.tsv PCSE00986` exercises a game workflow; use disposable output and test data because integration runs access remote services and create archives.

## Coding Style & Naming Conventions

Keep shell scripts compatible with their `#!/bin/sh` shebang. Use four-space indentation, uppercase names for environment/configuration variables (`TITLE_ID`, `DESTDIR`), lowercase snake_case for functions, and quote path and argument expansions. Put reusable behavior in `functions.sh`; source it relative to `SCRIPT_DIR`. Preserve documented exit-code meanings when changing workflows. Python follows four-space indentation and snake_case. No formatter or linter is configured, so match nearby code and keep changes focused.

## Testing Guidelines

Automated tests and coverage thresholds are not yet defined. At minimum, run both syntax checks above and manually verify `-h`/`--help`, invalid arguments, and the affected happy path. Avoid tests that download large packages unless explicitly required. If adding tests, place them under `tests/` and name shell cases `test_*.sh` and Python cases `test_*.py`.

## Commit & Pull Request Guidelines

Recent history uses short, imperative, lowercase subjects such as `fixed mistake in readme` and `added support to download PSM games`. Follow that concise style and keep each commit scoped to one concern. Pull requests should explain the behavior change, list commands run, call out dependency or output-format changes, and link relevant issues. Include terminal output for CLI behavior changes; screenshots are generally unnecessary.

## Security & Configuration

Do not commit downloaded packages, TSV archives, credentials, private tracker URLs, or generated title directories. Treat remote metadata as untrusted input and quote variables used in paths or commands.
