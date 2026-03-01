## 1. Baseline analysis and TDD setup

- [x] 1.1 Review current STT stream semantics: session continues after `final`, and audio gating forwards chunks only while speaking.
- [x] 1.2 Define TDD cases (failing first) for conservative end-of-turn: `final`-aware countdown start, start-from-last-transcript-change, and cancellation on transcript churn/speech resumption.
- [x] 1.3 Add/extend tests for `SttPlaygroundWeb.SttLive` covering: multiple turns, one-commit-per-turn, and no duplicate submissions.

## 2. Implement turn buffers and conversation history

- [x] 2.1 Add LiveView assigns for `active_turn_text` and `conversation_history` and ensure clear/reset resets both.
- [x] 2.2 Update transcript handling so partial/final events mutate only `active_turn_text` (no history commit yet).
- [x] 2.3 Implement a shared submit helper: commit `user` message → run AI → commit `assistant` message → reset active turn.

## 3. Implement conservative auto-submit countdown (less premature)

- [x] 3.1 Track `last_transcript_change_ms` and `last_final_ms` (or equivalent) so countdown start can be `final`-aware.
- [x] 3.1a Add configuration plumbing for `min_pause_after_final_ms` (default 3000) and `fallback_stable_without_final_ms` (default 6000).
- [x] 3.2 Implement countdown start rule: require speech inactive + transcript stable + final observed (preferred), and measure 3s from last transcript change.
- [x] 3.3 Implement explicit fallback if `final` is delayed (default: submit after 6 seconds of transcript stability while speech is inactive) to avoid never responding, while preserving conservative behavior.
- [x] 3.4 Cancel/restart countdown on speech resumption or any transcript change.
- [x] 3.5 Add dedupe/in-flight guards so the same user turn snapshot is not submitted twice.

## 4. Activity indicators (separate, overlapping)

- [x] 4.1 Keep an explicit **On Air** indicator (speech activity) visible whenever recording is enabled.
- [x] 4.2 Keep an explicit **Transcribing/Finalizing** indicator visible whenever the backend is still catching up, even if On Air is also active.
- [x] 4.3 Add an explicit **auto-submit countdown** indicator (showing time remaining) that cancels/resets when the user starts speaking again or when transcript text changes.
- [x] 4.4 Optionally render a minimal history view so users perceive discrete turns.

## 5. Verification

- [x] 5.1 Verification: run tests for changed areas and confirm new/updated tests pass.
- [x] 5.2 Verification: run `./precommit.sh` after implementation updates and resolve any issues.
- [x] 5.3 Verification: manual browser check with multiple turns (speak → pause → answer → speak again) to confirm only the new active turn is submitted each time.

## 6. Final verification by the user

- [x] 6.1 Final verification by the user: ask two separate questions in two separate pauses and confirm responses are based on discrete turns (not one cumulative transcript).
- [x] 6.2 Final verification by the user: pause mid-thought; confirm system is conservative (waits for transcript settle and does not submit too early).
- [x] 6.3 Final verification by the user: manual "Run AI + Speak" still works as an override.
