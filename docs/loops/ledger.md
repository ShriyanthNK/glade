# Loop ledger

(one line per round: loop, round, what failed, what changed)
- mascot art, round 0: rendered both candidates; firefly redesigned twice by the implementer (wings read as ears; face lost on dark head). Handing to the independent reviewer.
- mascot art, round 1: reviewer FAIL both. Glim: reads as bee/frog (head too big, no antenna stalks, whole belly glowing), calm~waiting, stray pixels, clipping in done/angry. Hoot: calm~waiting silhouette, annoyed eyes closed, belly dither, done clips, no shake/tap. Fixing all.
- mascot art, round 2: reviewer FAIL both (Glim 6 fails: reads as gremlin holding a lemon, calm~waiting, dark eyes vanish, doubled outline, halo cut off. Hoot 2 fails: calm lid bar makes calm/waiting/annoyed alike; clipping in done/angry). Root cause found by looking at pixels: antenna stalks were plum-on-plum (invisible); head too dark; lamp drawn as separate oval. Fixing.
- mascot art, round 3 prep: Glim rebuilt (pale face, light antenna stalks, lamp = bottom of abdomen, rim glow). Hoot: calm eyes open & glancing, no lid bar; wings narrowed. Added design/mascots/check-bounds.mjs (automated verifier for criterion 6): it caught side/bottom/top clipping the eye missed; now passes for every mood at 160 time steps.
