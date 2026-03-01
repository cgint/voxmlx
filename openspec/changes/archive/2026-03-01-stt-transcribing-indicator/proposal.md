# Make transcription latency visible with a “Transcribing…” indicator

## Why

### Summary
Today the UI shows an “On Air” indicator for speaking activity, but it does not communicate when the system is still working on converting already-spoken audio into text. Because STT results can arrive with variable latency, users can be unsure whether more transcript updates are still expected.

Adding an explicit “transcribing in progress” indicator makes the app’s state legible: users can tell whether the system is still processing audio (and more text may still arrive) versus being fully caught up.

### Original user request (verbatim)
Now we have that on-air indicator. I see that sometimes there is more or less latency during processing of spoken input until the output is returned and put into the transcript. So I would love to have a second indicator that indicates that currently there is still some transcribing ongoing. It should help the user to understand if something is still to be expected to come or not.

## What Changes
- Add a second UI indicator (in addition to “On Air”) that reflects whether transcription work is currently in progress.
- Introduce / derive a boolean state (e.g. `isTranscribing`) that becomes true when audio has been sent for transcription and the system is still awaiting transcript updates.
- Ensure the indicator is accessible (screen-reader friendly) and does not conflict with the meaning of the existing “On Air” indicator.

## Capabilities

### New Capabilities
- `transcription-processing-state`: Define how the app determines and exposes whether transcription is currently in progress (e.g. `isTranscribing`) during an active recording session.
- `transcribing-indicator-ui`: Display a “Transcribing…” (or equivalent) UI indicator driven by the transcription-processing state.

### Modified Capabilities
- (none)

## Impact
- **UI/LiveView:** `stt_playground` LiveView rendering will be extended to include the new indicator and its accessible labeling.
- **State management:** STT event handling and/or local state tracking will be updated to compute `isTranscribing`.
- **Tests:** LiveView tests will be added/updated to cover the new indicator behavior across partial/final/idle states.
