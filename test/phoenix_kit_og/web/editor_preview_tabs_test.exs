defmodule PhoenixKitOG.Web.EditorPreviewTabsTest do
  @moduledoc """
  Locks the preview-platform switcher onto core's `<.nav_tabs>` contract.

  Event tabs dispatch `phx-value-tab`. The handler used to match
  `%{"platform" => _}`, and the catch-all `set_preview_platform` clause
  returns `:noreply` for anything else — so a payload-key mismatch is a
  silent no-op, not a crash. This test is the thing that would fail if
  the template and the handler drifted again.

  Asserts against source rather than by rendering: EditorLive also
  embeds OpenFresco + MediaBrowser, and the payload contract does not
  need that stack. The LiveView path is in `editor_live_test.exs`.
  """
  use ExUnit.Case, async: true

  @live Path.expand("../../../lib/phoenix_kit_og/web/editor_live.ex", __DIR__)
  @template Path.expand("../../../lib/phoenix_kit_og/web/editor_live/template.ex", __DIR__)

  test "the preview switcher is core nav_tabs with the standard tab payload" do
    template = File.read!(@template)
    live = File.read!(@live)

    assert template =~ ~r/<\.nav_tabs\b/
    assert template =~ ~s(on_change="set_preview_platform")
    refute template =~ "phx-value-platform"

    assert live =~ ~s|handle_event("set_preview_platform", %{"tab" => platform}|
    refute live =~ ~s|%{"platform" => platform}|
  end

  test "platform tab ids stay in sync with the handler whitelist" do
    live = File.read!(@live)
    template = File.read!(@template)

    [_, whitelist] = Regex.run(~r/@preview_platforms ~w\(([^)]+)\)/, live)
    expected = String.split(whitelist)

    [_, body] = Regex.run(~r/defp platform_tabs do\n(.*?)\n  end\n/s, template)
    ids = Regex.scan(~r/id: "(\w+)"/, body) |> Enum.map(&List.last/1)

    assert ids == expected,
           """
           platform_tabs/0 ids #{inspect(ids)} do not match @preview_platforms #{inspect(expected)}.

           The handler guard drops unknown ids on the floor (the catch-all
           `set_preview_platform` clause is a silent no-op). Keep the two
           lists in the same order.
           """
  end
end
