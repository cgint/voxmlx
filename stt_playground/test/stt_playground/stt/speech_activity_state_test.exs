defmodule SttPlayground.STT.SpeechActivityStateTest do
  use ExUnit.Case, async: true

  alias SttPlayground.STT.SpeechActivityState

  test "turns on after sustained speech" do
    state =
      SpeechActivityState.new(
        min_speak_ms: 100,
        min_silence_ms: 150,
        on_threshold: 0.1,
        off_threshold: 0.05
      )
      |> SpeechActivityState.set_enabled(true, 0)

    state = SpeechActivityState.ingest_energy(state, 0.2, 40)
    refute state.is_speaking

    state = SpeechActivityState.ingest_energy(state, 0.2, 90)
    refute state.is_speaking

    state = SpeechActivityState.ingest_energy(state, 0.2, 140)
    assert state.is_speaking
  end

  test "stays on during brief pause and turns off after sustained silence" do
    state =
      SpeechActivityState.new(
        min_speak_ms: 50,
        min_silence_ms: 120,
        on_threshold: 0.1,
        off_threshold: 0.05
      )
      |> SpeechActivityState.set_enabled(true, 0)
      |> SpeechActivityState.ingest_energy(0.2, 10)
      |> SpeechActivityState.ingest_energy(0.2, 70)

    assert state.is_speaking

    state = SpeechActivityState.ingest_energy(state, 0.01, 130)
    assert state.is_speaking

    state = SpeechActivityState.ingest_energy(state, 0.01, 220)
    assert state.is_speaking

    state = SpeechActivityState.ingest_energy(state, 0.01, 260)
    refute state.is_speaking
  end

  test "stt disabled forces off" do
    state =
      SpeechActivityState.new(min_speak_ms: 0, min_silence_ms: 200)
      |> SpeechActivityState.set_enabled(true, 0)
      |> SpeechActivityState.ingest_energy(0.5, 10)

    assert state.is_speaking

    state = SpeechActivityState.set_enabled(state, false, 15)
    refute state.is_speaking
  end

  test "deterministic outputs for same inputs" do
    inputs = [
      {:enabled, true, 0},
      {:energy, 0.2, 10},
      {:energy, 0.2, 90},
      {:energy, 0.01, 120},
      {:energy, 0.01, 200},
      {:enabled, false, 210}
    ]

    run_once = fn ->
      Enum.reduce(inputs, {SpeechActivityState.new(min_speak_ms: 50, min_silence_ms: 60), []}, fn
        {:enabled, enabled?, ts_ms}, {state, acc} ->
          state = SpeechActivityState.set_enabled(state, enabled?, ts_ms)
          {state, [state.is_speaking | acc]}

        {:energy, energy, ts_ms}, {state, acc} ->
          state = SpeechActivityState.ingest_energy(state, energy, ts_ms)
          {state, [state.is_speaking | acc]}
      end)
      |> elem(1)
      |> Enum.reverse()
    end

    assert run_once.() == run_once.()
  end
end
