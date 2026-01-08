defmodule BookReportDemoWeb.PageController do
  use BookReportDemoWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
