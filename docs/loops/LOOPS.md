# Loops

How work gets done on this project: a loop with a separate verifier, not a single pass that grades itself.

## The contract every loop follows

1. **A goal that can be checked.** A command that exits 0, or a rubric a reviewer scores, written down before work starts.
2. **An implementer** makes the change and commits. It never decides that it is done.
3. **An independent verifier** decides. For code it is `scripts/verify.sh`; for art and design it is a fresh reviewer agent that sees only the rendered output and the rubric, never the implementer's reasoning.
4. **A stop condition and a cap.** Stop when the verifier passes. At most 5 rounds; rounds 4 and 5 use a more capable model. If round 5 still fails, record the open findings and ask the owner instead of looping on.
5. **A ledger.** Each round appends one line (what failed, what changed) to `docs/loops/ledger.md` so a restarted session can pick up the loop where it stopped.
6. **Safety rails run in every round:** tests use throwaway homes (`GLADE_HOME`, `GLADE_CLAUDE_SETTINGS`); the real `~/.claude/settings.json` checksum must not change; nothing is pushed or published by a loop.

## The loops

| Loop | Goal | Verifier | Cap |
|---|---|---|---|
| App phase | The phase's acceptance checks pass | `scripts/verify.sh` (build, unit tests, isolated install/CLI test, real settings untouched) | 5 |
| Mascot art | Rubric in `design/mascots/RUBRIC.md` passes | Fresh reviewer agent scoring screenshots at several animation times | 5 |
| Website | `npm run lint`, `npm test`, `npm run build` green; rubric for design, contrast, copy claims | The site's own checks plus a fresh reviewer on screenshots at 1440 and 390 wide | 5 |
| Release | `.dmg` opens on a clean account; `spctl -a -vv` accepts it once signed | A script on a throwaway user, then a reviewer reading its output | 3 |

## Rules learned so far

- An implementer's "tests pass" is not evidence. Run the verifier.
- A verifier that only checks the happy path is not a verifier: add the failure case that bit us (the real-home leak, the `$bar█` shell bug) to it.
- Cost matters: each round is tokens. Use the cheapest model that can do the round, and stop at the first pass.
