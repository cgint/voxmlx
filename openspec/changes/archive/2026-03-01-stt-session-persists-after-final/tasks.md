## 1. Reproduce and lock down the regression (TDD first)

- [x] 1.1 Identify existing LiveView/STT tests and define a TDD test case for: `final` arrives, then later `partial` still updates transcript in the same session
- [x] 1.2 Implement/adjust regression test(s) that fail with current behavior (session cleared on `final`)

## 2. Implement session continuity lifecycle fix

- [x] 2.1 Update STT `final` handling in `stt_live.ex` so active recording/session is preserved (`recording` and `session_id` remain active)
- [x] 2.2 Keep stop semantics explicit: verify only stop/error paths deactivate the session and disable speaking state
- [x] 2.3 Ensure transcript and status handling remain coherent for post-`final` partial/final updates in the same session

## 3. Align indicator behavior with lifecycle semantics

- [x] 3.1 Confirm On Air enablement remains tied to `recording == true` even when interim `final` events occur
- [x] 3.2 Add/adjust tests covering the `final`-while-recording path for indicator/session state consistency

## 4. Verification

- [x] 4.1 Run project verification (tests + precommit checks) and confirm no regressions in STT/TTS playground flow
- [x] 4.2 Verify manually in browser that transcript continues to update after AI+Speak and post-`final` events without stop/start
- [x] 4.3 Final verification by the user: user confirms continuous transcript behavior across interim finals and normal stop/error handling
