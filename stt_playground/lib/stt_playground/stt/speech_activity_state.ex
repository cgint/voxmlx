defmodule SttPlayground.STT.SpeechActivityState do
  @moduledoc """
  Deterministic, side-effect free speech activity state machine.

  The state consumes:
  - enabled/disabled transitions
  - normalized energy samples (e.g. RMS in range 0.0..1.0)
  - optional semantic speech events (`:speech_start`, `:speech_end`)

  And exposes a stable `is_speaking` boolean using hysteresis/debounce.
  """

  @enforce_keys [:min_speak_ms, :min_silence_ms, :on_threshold, :off_threshold]
  defstruct [
    :min_speak_ms,
    :min_silence_ms,
    :on_threshold,
    :off_threshold,
    :speech_candidate_since_ms,
    :silence_candidate_since_ms,
    enabled: false,
    is_speaking: false
  ]

  @type t :: %__MODULE__{
          min_speak_ms: non_neg_integer(),
          min_silence_ms: non_neg_integer(),
          on_threshold: float(),
          off_threshold: float(),
          speech_candidate_since_ms: integer() | nil,
          silence_candidate_since_ms: integer() | nil,
          enabled: boolean(),
          is_speaking: boolean()
        }

  @spec new(keyword()) :: t()
  def new(opts \\ []) do
    min_speak_ms = Keyword.get(opts, :min_speak_ms, 120)
    min_silence_ms = Keyword.get(opts, :min_silence_ms, 220)
    on_threshold = Keyword.get(opts, :on_threshold, 0.02)
    off_threshold = Keyword.get(opts, :off_threshold, 0.01)

    %__MODULE__{
      min_speak_ms: min_speak_ms,
      min_silence_ms: min_silence_ms,
      on_threshold: on_threshold,
      off_threshold: off_threshold,
      speech_candidate_since_ms: nil,
      silence_candidate_since_ms: nil
    }
  end

  @spec set_enabled(t(), boolean(), integer()) :: t()
  def set_enabled(state, false, _ts_ms) do
    %{
      state
      | enabled: false,
        is_speaking: false,
        speech_candidate_since_ms: nil,
        silence_candidate_since_ms: nil
    }
  end

  def set_enabled(state, true, _ts_ms) do
    %{state | enabled: true, speech_candidate_since_ms: nil, silence_candidate_since_ms: nil}
  end

  @spec ingest_event(t(), :speech_start | :speech_end, integer()) :: t()
  def ingest_event(state, _event, _ts_ms) when state.enabled == false do
    %{state | is_speaking: false, speech_candidate_since_ms: nil, silence_candidate_since_ms: nil}
  end

  def ingest_event(state, :speech_start, _ts_ms) do
    %{state | is_speaking: true, speech_candidate_since_ms: nil, silence_candidate_since_ms: nil}
  end

  def ingest_event(state, :speech_end, _ts_ms) do
    %{state | is_speaking: false, speech_candidate_since_ms: nil, silence_candidate_since_ms: nil}
  end

  @spec ingest_energy(t(), number(), integer()) :: t()
  def ingest_energy(state, _energy, _ts_ms) when state.enabled == false do
    %{state | is_speaking: false, speech_candidate_since_ms: nil, silence_candidate_since_ms: nil}
  end

  def ingest_energy(state, energy, ts_ms) do
    energy = max(0.0, min(1.0, energy * 1.0))

    cond do
      state.is_speaking ->
        maybe_turn_off(state, energy, ts_ms)

      true ->
        maybe_turn_on(state, energy, ts_ms)
    end
  end

  @spec rms_from_pcm_f32(binary(), :little | :big | :native) :: float()
  def rms_from_pcm_f32(binary, endian \\ :native)

  def rms_from_pcm_f32(binary, _endian) when byte_size(binary) == 0, do: 0.0

  def rms_from_pcm_f32(binary, _endian) when rem(byte_size(binary), 4) != 0 do
    raise ArgumentError, "PCM float32 binary size must be divisible by 4"
  end

  def rms_from_pcm_f32(binary, :little), do: do_rms_little(binary, 0, 0.0)
  def rms_from_pcm_f32(binary, :big), do: do_rms_big(binary, 0, 0.0)
  def rms_from_pcm_f32(binary, :native), do: do_rms_native(binary, 0, 0.0)

  defp maybe_turn_on(state, energy, ts_ms) when energy >= state.on_threshold do
    candidate_since = state.speech_candidate_since_ms || ts_ms

    if ts_ms - candidate_since >= state.min_speak_ms do
      %{
        state
        | is_speaking: true,
          speech_candidate_since_ms: nil,
          silence_candidate_since_ms: nil
      }
    else
      %{state | speech_candidate_since_ms: candidate_since, silence_candidate_since_ms: nil}
    end
  end

  defp maybe_turn_on(state, _energy, _ts_ms) do
    %{state | speech_candidate_since_ms: nil, silence_candidate_since_ms: nil}
  end

  defp maybe_turn_off(state, energy, ts_ms) when energy <= state.off_threshold do
    candidate_since = state.silence_candidate_since_ms || ts_ms

    if ts_ms - candidate_since >= state.min_silence_ms do
      %{
        state
        | is_speaking: false,
          speech_candidate_since_ms: nil,
          silence_candidate_since_ms: nil
      }
    else
      %{state | silence_candidate_since_ms: candidate_since, speech_candidate_since_ms: nil}
    end
  end

  defp maybe_turn_off(state, _energy, _ts_ms) do
    %{state | silence_candidate_since_ms: nil, speech_candidate_since_ms: nil}
  end

  defp do_rms_little(<<>>, count, sum_squares), do: finish_rms(count, sum_squares)

  defp do_rms_little(<<sample::float-little-size(32), rest::binary>>, count, sum_squares) do
    do_rms_little(rest, count + 1, sum_squares + sample * sample)
  end

  defp do_rms_big(<<>>, count, sum_squares), do: finish_rms(count, sum_squares)

  defp do_rms_big(<<sample::float-big-size(32), rest::binary>>, count, sum_squares) do
    do_rms_big(rest, count + 1, sum_squares + sample * sample)
  end

  defp do_rms_native(<<>>, count, sum_squares), do: finish_rms(count, sum_squares)

  defp do_rms_native(<<sample::float-native-size(32), rest::binary>>, count, sum_squares) do
    do_rms_native(rest, count + 1, sum_squares + sample * sample)
  end

  defp finish_rms(0, _sum_squares), do: 0.0
  defp finish_rms(count, sum_squares), do: :math.sqrt(sum_squares / count)
end
