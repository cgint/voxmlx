defmodule SttPlaygroundWeb.OnAirIndicatorTest do
  use SttPlaygroundWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  test "renders inactive indicator when stt is disabled" do
    html =
      render_component(&SttPlaygroundWeb.CoreComponents.on_air_indicator/1,
        enabled: false,
        active: false
      )

    assert html =~ "On Air"
    assert html =~ "aria-label=\"On Air inactive\""
    assert html =~ "bg-gray-500"
  end

  test "renders inactive indicator when stt is enabled but not speaking" do
    html =
      render_component(&SttPlaygroundWeb.CoreComponents.on_air_indicator/1,
        enabled: true,
        active: false
      )

    assert html =~ "On Air"
    assert html =~ "aria-label=\"On Air inactive\""
    assert html =~ "bg-gray-500"
  end

  test "renders active indicator when stt is enabled and speaking" do
    html =
      render_component(&SttPlaygroundWeb.CoreComponents.on_air_indicator/1,
        enabled: true,
        active: true
      )

    assert html =~ "On Air"
    assert html =~ "aria-label=\"On Air active\""
    assert html =~ "bg-red-500"
  end
end
