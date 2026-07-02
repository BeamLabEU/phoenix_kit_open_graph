defmodule PhoenixKitOg.Paths do
  @moduledoc """
  Centralized path helpers — every link routes through
  `PhoenixKit.Utils.Routes.path/1` so the configured admin prefix and
  locale handling are honored.
  """

  alias PhoenixKit.Utils.Routes

  @base "/admin/open-graph"

  @spec templates() :: String.t()
  def templates, do: Routes.path(@base)

  @spec assignments() :: String.t()
  def assignments, do: Routes.path("#{@base}/assignments")

  @spec new_template() :: String.t()
  def new_template, do: Routes.path("#{@base}/new")

  @spec edit_template(binary()) :: String.t()
  def edit_template(uuid), do: Routes.path("#{@base}/#{uuid}/edit")
end
