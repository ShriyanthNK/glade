# Glade

A Mac app for people who live in Claude Code. **Mochi**, a pixel-art dumpling with a sprout, pops up in the
corner of your screen when Claude is done or waiting on you, then gets out of the way.

Native Swift/SwiftUI. Lives in the menu bar; the Glade window (Home, Looks, Alerts, Claude Code, About) opens from its icon. macOS 13+.

## Install (from source)

    ./install.sh

Builds the app, installs it to `~/.glade/`, merges four hooks into `~/.claude/settings.json` (backup written
next to it first), and links `glade` into `~/.local/bin`. Needs `jq` (ships with macOS 15+) and a Swift
toolchain. Restart running Claude Code sessions afterwards.

Upgrading from claude-buddy: `install.sh` copies your settings, replaces the old hooks and removes the old install.
A `claude-buddy` command stays linked to `glade` so old scripts keep working.

    glade test                # show Mochi now (waiting)
    glade test done           # celebration pose
    glade test --age 90       # preview the impatient tiers
    glade chime on|off        # soft chime (off by default)
    glade delays 5 20         # seconds before the waiting / done buddy appears
    glade snooze 30           # silence for 30 min (or: forever, clear)
    glade open [page]         open the Glade window (home, looks, alerts, claude-code, about)
    glade look list|use ID|add PHOTO|remove ID   backdrops (add --out FILE.png only exports)
    glade hooks install|uninstall|status         manage the Claude Code hooks
    glade hide | quit
| quit

## Behavior

| Hook | Effect |
|---|---|
| Notification | "Claude's waiting on you" + the hook message, after 5s |
| Stop | "Claude's done, your turn", after 20s |
| UserPromptSubmit, PostToolUse | hide (or cancel the pending show) immediately |

- Events are matched by session, so a reply in one session doesn't hide another's buddy.
- The hook script returns in about 10 ms; the work runs in a detached background job.
- Click Mochi or its bubble to jump to the terminal app Claude runs in (detected from
  `__CFBundleIdentifier`, falling back to any running known terminal). `x` just dismisses.
- Waiting gets more impatient: calm and tapping, then a "?" sign after 1 min, then "!!" and steam after 2 min.
  At 3 min he gives up and leaves (config `giveUpAfter`, 0 = never).
- Click-through everywhere except on Mochi and the bubble. Never takes focus.

## Develop

    swift build                    # debug build
    swift test                     # unit tests (config, wire format, migration)
    scripts/bundle.sh              # build/Glade.app (ad-hoc signed)
    scripts/test-install.sh        # install/uninstall + CLI end to end, in a throwaway home

Layout: `Sources/GladeCore` (no UI: config, wire format, socket server), `Sources/Glade` (the app and CLI),
`Tests/GladeCoreTests`. Set `GLADE_HOME` / `GLADE_LEGACY_HOME` to point a run at a different support directory
(the test script does this so it never touches your real install).

## Uninstall

    ./uninstall.sh

Removes only Glade's hook entries (backup first), the app, and the symlinks.

## Notes

- Config lives in `~/.glade/config.json`.
- Not affiliated with or endorsed by Anthropic.
