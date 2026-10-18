# claude-buddy

A tiny macOS menu-bar-less app. When Claude Code is waiting on you, **Mochi**, a pixel-art
dumpling with a sprout, pops up in the bottom-right corner of whichever screen your mouse is on.

Native Swift/SwiftUI, no Dock icon, no dependencies beyond `jq` (ships with macOS 15+).

## Install

    ./install.sh

Builds the app into `~/.claude-buddy/`, merges four hooks into `~/.claude/settings.json`
(backup written next to it first), and links `claude-buddy` into `~/.local/bin`.
Restart running Claude Code sessions afterwards.

    claude-buddy test            # show Mochi now (waiting)
    claude-buddy test done       # celebration pose
    claude-buddy test --age 90   # preview the impatient tiers (60s: sign, 300s: furious)
    claude-buddy chime on|off    # soft chime (off by default)
    claude-buddy delays 5 20     # seconds before waiting / done buddy appears
    claude-buddy snooze 30       # silence for 30 min (or: forever, clear)
    claude-buddy hide | quit

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
- Waiting gets more impatient: calm and tapping, then a "?" sign after 1 min, then "!!" and steam after 2 min. At 3 min he gives up and leaves (config `giveUpAfter`, 0 = never).
- Click-through everywhere except on Mochi and the bubble. Never takes focus.

## Uninstall

    ./uninstall.sh

Removes only claude-buddy's hook entries (backup first), the app, and the symlink.

## Notes

- If `swiftc` complains about the Xcode license, install.sh falls back to the Command Line Tools toolchain.
- Config lives in `~/.claude-buddy/config.json`.
- Source: `Sources/` (Sprite.swift = the character, Views.swift = animation and bubble).
