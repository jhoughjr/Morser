# Practice modes — plan

**Status:** phases 0a, 0b and 1 are done. 0a shipped as Morse.swift v1.0.0
(jhoughjr/Morse.swift#1); 0b and 1 landed together, since the generators are
nearly free once the seam exists and doing them separately means paying for the
same context three times over. Phases 2–5 are still as written below.

Ordered easiest to hardest. Cost is in PRs, not days, because the sizes differ by
an order of magnitude and calendar estimates would be fiction.

The ordering is not just difficulty: phase 0 is a prerequisite for everything
after it, and phase 4 needs an input change before any of its scoring is
meaningful. Doing the cheap generators first and refactoring afterwards means
writing them twice.

## Where the seams already are

`PracticeSession.startRound()` is the only thing that knows how a prompt is made.
`PracticeSession.grade(prompt:answer:)` is the only thing that knows how it's
marked. Sending, Farnsworth timing, per-character scoring and persistence are all
mode-agnostic already. So most modes below are a prompt generator, not a feature.

Four axes actually vary:

| axis | Koch today | varies in |
|---|---|---|
| character set | first N of the Koch order | 1a, 1b, 1c, 1d |
| prompt shape | random groups of 5 | 1b, 1c, 2a |
| how you answer | type it, then Return | 2b (self-report), 3 (single key, timed), 4 (key it back) |
| how it's marked | per-group character alignment | 3 (latency), 4 (fist timing) |

---

## Phase 0a — push the morse knowledge into Morse.swift ✅ done (v1.0.0)

`Morse.swift` exists to abstract morse, so domain knowledge belongs there rather
than accreting in the app. Doing this first deletes app code instead of adding
to it, and unblocks phase 1.

Verified by compiling and running the package's own source, not by reading it:

```
latin(from: ".-.-.-")   → "DOT "        should be "."
latin(from: "-....-")   → "DASH "       should be "-"
morse(from: "a#b")      → ".-   -..."   the "#" vanishes, silently
isTextMorse("...")      → false
isTextLatin("hello")    → false
```

- **Punctuation decode is corrupt.** `LatinCharacters.DOT` / `.DASH` claim
  `.-.-.-` and `-....-`, are checked before the punctuation table, and emit
  their raw enum *names*. Any round-trip through punctuation returns letters.
- **Both `isText*` predicates are broken.** They assign `flag` per character
  instead of accumulating, so only the last character decides the answer. They
  return false for valid input either way. Fix or delete — nothing uses them.
- **`latin(from:)` appends a trailing space** per word, so a round-trip never
  equals its input. Worth a property test: `latin(morse(x)) == x.uppercased()`.
- **Encoding drops unknown characters with no signal.** For a trainer that's a
  real hazard — the prompt says one thing and the audio sends another. An
  encode that reports what it skipped lets the app delete the `promptLetters`
  filter, which exists only to mirror this behaviour.
- **Expose the canonical char↔morse table.** `Keyer` keeps a duplicated
  50-entry dictionary because the package offers no lookup. That copy is a
  second source of truth for the same facts.
- **Prosigns as a real concept** (`<AR>`, `<SK>`, `<BT>`, `<KN>`), with a token
  syntax the encoder understands. Right now the punctuation table shadows them:
  `AR` is `.-.-.` which decodes as `+`, `BT` is `-...-` which decodes as `=`.
  Phase 1c needs this.
- **Alphabets** — letters, digits, punctuation, prosigns as addressable sets.
  Phase 1a's character-set filters are trivial once these exist.
- **Timing** — `Symbols.ditTime()` is a hardcoded `0.1`. PARIS and Farnsworth
  are morse domain knowledge; moving them in lets the app drop its own
  `Farnsworth` enum.

~~⚠️ **The dependency tracks a branch, not a version.**~~ Fixed: the package is
tagged `v1.0.0` and MorserX now pins `upToNextMajorVersion` from 1.0.0. It had
been worse than "no gate" — `Package.resolved` recorded `78ecfb2` while the
checkout being compiled was `bf5cf81`, so the pin didn't describe the build.

## Phase 0b — the seam ✅ done

**No user-visible change.** Extract a `PracticeDrill` protocol over those four
axes and re-express Koch as `KochDrill`. Persist settings *per mode*, so
switching to callsigns and back doesn't reset your Koch level.

Also generalise the stat model once, here, rather than three times later: today
it's `[Character: CharacterScore]` with `(attempts, hits)`. Head copy scores
words, instant recognition scores latency, send practice scores ratios. One
migration now is cheaper than three migrations spread across the other phases.

**Risk:** none really — it's a refactor behind passing tests. That's exactly why
it goes first.

## Phase 1 — generators ✅ done (one PR)

Each is a `makePrompt` implementation plus a test that the output is well-formed
and encodable end to end.

- **1a. Character-set filters.** Numbers only, punctuation only, "the eight I
  keep missing." The last one is free — `weakest` already computes it.
- **1b. Callsigns.** Prefix / digit / suffix shapes rather than uniform random
  letters: `W4ABC`, `DL1XYZ`, `VE3AB`. Structure is the point — you start
  predicting the shape, which uniform groups never teach.
- **1c. QSO phrases and prosigns.** `CQ CQ DE`, `RST 599`, `QTH`, `TU 73`, AR,
  SK, BT. ⚠️ The Morse package has no prosign concept and its punctuation table
  claims the codes. Handled in phase 0a, in the package where it belongs.
- **1d. Custom text.** Paste anything and drill against it. Trivially small, and
  it's the escape hatch that makes every missing mode less urgent.

## Phase 2 — words and head copy

- **2a. Plain words.** A word list instead of random groups, so `THE` is heard as
  one shape rather than three letters. This is the bridge to head copy.
  **Decision:** embed the list as a Swift array rather than a bundled `.txt` —
  the project uses filesystem-synchronised groups, which pick up `.swift`
  automatically but would need a Copy Bundle Resources phase for a text file.
  Not worth touching the pbxproj for ~500 words.
- **2b. Head copy.** Send a word, no text field, reveal it, self-report hit or
  miss. Trains you out of writing, which is the wall most people hit around
  20 wpm. Needs the "how you answer" axis from phase 0 to be real, and scores
  words rather than characters.

## Phase 3 — instant recognition

One character, answer before a deadline. **The metric is latency, not accuracy** —
at speed, "correct after two seconds of thinking" is a miss, and nothing we
currently record would show that.

Needs: a clock from end-of-send to keystroke, an answer path that takes a single
keypress without Return, a deadline that scores a timeout as a miss, and
per-character latency in the stat model (phase 0 pays for itself here).

**Optional, any time after this:** a *speed ladder* — hold ≥90% for N rounds and
character speed goes up on its own instead of you deciding. Small, and it depends
only on stats that already exist.

## Phase 4 — send practice

The valuable one, and the one where this app is unusual: it already owns a keyer
and an audio engine, and almost no trainer marks your *fist*.

**4a. A straight key, first.** This is the part that isn't obvious: the current
dit paddle auto-streams dits on a timer, so its timing is machine-generated. You
cannot score a fist on an input that is already perfect. Send practice needs a
single-button straight-key mode where the press length is yours, and `Keyer` has
to timestamp key-down/key-up — today it appends a symbol after a sleep and keeps
no wall-clock record at all.

**4b. Decode from timings.** Classify press durations into dit/dah against an
estimated dit, and gaps into intra-character / letter / word. Adaptive threshold,
because a human's dit drifts across a sentence. Pure function over an array of
timings, so it tests well without any audio.

**4c. Score the fist, not just the text.** Character accuracy *and* the ratios:
dit:dah, gap widths, and consistency (variance). "Your dahs are 2.1× your dits,
should be 3×" is actionable in a way that "you sent GAT instead of CAT" is not.

**4d. UI.** Prompt shown, key it, marked, with the ratio feedback.

Its own PR, minimum. 4a alone touches existing keyer behaviour.

## Phase 5 — pileup / QRM (hardest)

Two or three signals at once at different pitches — contest copy. This is the
only item on the list that is an *audio engine* change rather than a practice
change: `MorseRenderer.render` produces a single buffer today, so it needs to
render each transmission independently and sum them into a mix, with per-voice
frequency and amplitude. Then a UI for how many signals and which one you're
being asked to copy.

Most risk, least reuse, so last — but it's also the only one that can't be
approximated by any of the others.

---

## Suggested PR sequence

1. Phase 0a — Morse.swift: fixes, table, prosigns, alphabets (its own repo/PR, then tag)
2. Phase 0b — seam + stat model (no behaviour change)
3. Phase 1 — all four generators together
4. Phase 2 — words, then head copy
5. Phase 3 — instant recognition (+ speed ladder)
6. Phase 4 — straight key, then decode, then scoring, then UI
7. Phase 5 — mixing, then pileup mode
