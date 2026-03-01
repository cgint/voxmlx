## 1. Reproduction and test coverage

- [x] 1.1 Identify where STT `partial`/`final` events update the active user turn buffer (and confirm the exact event payload shape, especially whether `text` is cumulative per session)
- [x] 1.2 Add failing tests (TDD) that demonstrate the bug: repeated transcript updates must not create duplicated prefixes in the active turn, and a new turn must not include the previously committed turn as a prefix

## 2. Fix active-turn transcript handling

- [x] 2.1 Implement turn-relative transcript derivation (track a turn-start transcript anchor and derive the current turn text from the latest snapshot)
- [x] 2.2 Update the LiveView transcript event handler to update-by-replacement (not append), using the derived current-turn text, and add a safe fallback when prefix removal cannot be applied
- [x] 2.3 Ensure manual submit and auto-submit reset the active turn and update the anchor so subsequent transcript updates cannot re-introduce committed history

## 3. Verification

- [x] 3.1 Run automated tests and confirm the new regression tests pass
- [x] 3.2 Manual verification in the LiveView UI: record two consecutive turns in one continuous recording session and confirm the second user message does not repeat the first
- [x] 3.3 Final verification by the user: validate that conversation history no longer shows duplicated phrases/prefixes during normal speaking (including when STT emits multiple partial/final updates)
