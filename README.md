# Glade

A Mac app for people who live in Claude Code. **Hoot**, a pixel-art owl, pops up in the
corner of your screen when Claude is done or waiting on you, then gets out of the way.

Native Swift/SwiftUI. Lives in the menu bar; the Glade window (Home, Looks, Terminal, Alerts, Claude Code, About) opens from its icon. macOS 13+.

## Install (from source)

    ./install.sh

Builds the app and installs it to `~/.glade/`, then opens it. Click Hoot's icon in the menu bar, choose
"Open Glade…" and turn on the hooks on the Claude Code page; that merges five hooks into
`~/.claude/settings.json` (a backup is written next to it first). Needs a Swift toolchain. Restart running
Claude Code sessions afterwards.

Upgrading from claude-buddy: `install.sh` copies your settings and removes the old install. Turn on the new hooks
in the app; they replace the old ones.

## Behavior

| Hook | Effect |
|---|---|
| Notification | "Claude's waiting on you" + the hook message, after 5s |
| PermissionRequest | what Claude wants ("Run: npm test", "Edit: Views.swift") goes in the waiting bubble |
| Stop | "Claude's done, your turn" + a one-line summary of Claude's last message, after 20s |
| UserPromptSubmit, PostToolUse | hide (or cancel the pending show) immediately |

- Smart alerts (on by default): if the app running the session is frontmost and you used the keyboard or mouse in
  the last 8 seconds, Hoot stays away and checks again every 3 seconds, and hides once you are typing
  in the terminal. The "Show Hoot" buttons ignore this.
- Events are matched by session, so a reply in one session doesn't hide another's buddy.
- The hook script returns in about 10 ms; the work runs in a detached background job.
- Click Hoot or its bubble to jump to the terminal app Claude runs in (detected from
  `__CFBundleIdentifier`, falling back to any running known terminal). `x` just dismisses.
- Waiting gets more impatient: Hoot taps a foot with a wide-eyed look, then looks annoyed (sweat drop and a "?") after
  1 min, then angry (brows, "!!" and a puffed-up body) after 2 min.
  At 3 min he gives up and leaves (config `giveUpAfter`, 0 = never).
- Click-through everywhere except on Hoot and the bubble. Never takes focus.

## Develop

    swift build                    # debug build
    swift test                     # unit tests (config, wire format, migration)
    scripts/bundle.sh              # build/Glade.app (ad-hoc signed)
    scripts/test-install.sh        # install/uninstall smoke test, in a throwaway home
    scripts/demo.sh start|stop     # run the app in a throwaway home

Layout: `Sources/GladeCore` (no UI: config, wire format, socket server), `Sources/Glade` (the app),
`Tests/GladeCoreTests`. Set `GLADE_HOME` / `GLADE_LEGACY_HOME` to point a run at a different support directory
(the test script does this so it never touches your real install).

## Uninstall

    ./uninstall.sh

Removes only Glade's hook entries (backup first) and the app. The Uninstall button on the About page does the same.

## Notes

- Config lives in `~/.glade/config.json`.
- Not affiliated with or endorsed by Anthropic.
