defmodule SttPlaygroundWeb.PageController do
  use SttPlaygroundWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
