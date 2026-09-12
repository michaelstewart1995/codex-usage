# Codex Usage 1.1

A personal, unofficial macOS menu bar utility. Not affiliated with OpenAI.

## Requirements and setup

- macOS 13 or newer, on Apple Silicon or Intel.
- Python 3.9 or newer installed on the recipient's Mac. The app detects standard Homebrew, Python.org, and system Python locations at launch; it does not download software.
- Codex installed and signed in with the recipient's own ChatGPT account. Both `/Applications` and `~/Applications` are supported, as are standard Homebrew CLI installations.

Unzip the package, copy **Codex Usage.app** into your Applications folder, and open it. It appears in the menu bar without a Dock icon. Spotlight can launch it by searching for **Codex Usage**. Click the two usage rows to see the details. Quit stops periodic polling; starting at login is optional through macOS Login Items.

This build is locally ad-hoc signed, **not Developer ID signed or Apple notarized**. macOS may block a downloaded copy. The supplied source archive can be reviewed and built locally using Xcode command line tools and Python. A frictionless public release requires the distributor's Developer ID signing certificate and Apple notarization; those are not included. Do not disable Gatekeeper globally.

## Privacy and account access

The distribution contains the executable, usage script, icon, app metadata/signature, and this document. It contains no creator account credentials, account IDs, usage snapshots, preferences, or absolute home-directory paths.

At runtime, the script starts the recipient's installed Codex app-server and requests `account/rateLimits/read`. Codex handles its own authentication and network connection to its service. The utility neither copies nor exports login credentials. No model turn is started, no reset credit is consumed, and no third-party analytics are added.

Only quota percentages, window labels, reset times, and the fetch timestamp are passed to the UI. These are held in memory until the app quits. Failed updates retain the last successful values with a warning. The refresh interval is stored in local macOS preferences. Codex itself may maintain its own logs and authentication files according to its configuration.

The optional command-line `--watch` mode prints usage JSON to the caller's terminal. That output is private to whoever runs it unless they redirect or share it. The app bundle and release archives do not include that output.

Never include your `.codex` directory, auth files, logs, or preference files when sharing. Share the generated release ZIP, not a copy of your home folder or development caches.

## Source and license

Source: https://github.com/michaelstewart1995/codex-usage

Distributed under the included GNU GPL v3 license. The corresponding source ZIP is provided alongside the app download.
