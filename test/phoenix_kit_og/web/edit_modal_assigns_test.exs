defmodule PhoenixKitOG.Web.EditModalAssignsTest do
  @moduledoc """
  Regression guard for the assignment-modal `KeyError :preview_loading` crash.

  `edit_modal/1` is a function component, so `@x` in its body reads that
  component's OWN assigns. Reading one that is neither declared as an attr nor
  assigned in the body raises `KeyError` at render time — and the compiler says
  nothing, so only rendering the component finds it. That is what made the bug
  survive four releases: the read sat behind `:if={@selected_template}`, and HEEx
  wraps the whole invocation (attribute expressions included) in the conditional,
  so the modal rendered fine until a template was picked.

  The module has no endpoint or router of its own, so this asserts the invariant
  against the source rather than by rendering. It is deliberately scoped to the
  one component the bug was in.
  """
  use ExUnit.Case, async: true

  @source Path.expand("../../../lib/phoenix_kit_og/web/assignments_live.ex", __DIR__)
  @component "defp edit_modal(assigns) do"

  test "edit_modal/1 declares, or assigns, every assign its body reads" do
    source = File.read!(@source)
    [before_component, rest] = String.split(source, @component, parts: 2)

    # The attr block directly above the definition.
    declared =
      before_component
      |> String.split(~r/\n\s*\n/)
      |> Enum.filter(&String.contains?(&1, "attr(:"))
      |> List.last()
      |> then(&Regex.scan(~r/attr\(:(\w+)/, &1 || ""))
      |> Enum.map(fn [_, name] -> name end)
      |> MapSet.new()

    refute Enum.empty?(declared),
           "found no attr block above #{@component} — this test's parsing is stale"

    body = rest |> String.split(~r/\n  defp? /, parts: 2) |> List.first()

    # Assigns the component adds to itself before rendering are legitimate reads.
    self_assigned =
      ~r/assign\(\s*(?:assigns,\s*)?:(\w+)/
      |> Regex.scan(body)
      |> Enum.map(fn [_, name] -> name end)
      |> MapSet.new()

    read =
      ~r/@(\w+)/
      |> Regex.scan(body)
      |> Enum.map(fn [_, name] -> name end)
      |> MapSet.new()

    undeclared = read |> MapSet.difference(declared) |> MapSet.difference(self_assigned)

    assert MapSet.equal?(undeclared, MapSet.new()),
           """
           edit_modal/1 reads assigns it never declares: #{inspect(MapSet.to_list(undeclared))}

           Declare each as an `attr(...)` above the component AND pass it at the
           `<.edit_modal ... />` call site, or assign it in the body. Reading an
           undeclared assign raises KeyError when the component renders.
           """
  end

  test "the call site passes preview_loading through to the modal" do
    source = File.read!(@source)

    call_site =
      source
      |> String.split("<.edit_modal", parts: 2)
      |> List.last()
      |> String.split("/>", parts: 2)
      |> List.first()

    assert call_site =~ "preview_loading={@preview_loading}",
           """
           <.edit_modal> no longer forwards preview_loading.

           The attr defaults to false, so dropping it does not crash — it silently
           retires the preview spinner, which is why the pass-through is asserted
           separately from the declaration.
           """
  end
end
