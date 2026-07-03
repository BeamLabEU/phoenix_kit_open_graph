defmodule PhoenixKitOG.Slots do
  @moduledoc """
  Scans a canvas for `{{slot}}` references — the abstract, template-
  local names that get wired to concrete module variables at assignment
  time.

  Also handles `[[name]]` "global" references — these resolve
  automatically from the OG module's own settings/context (site host,
  page URL, etc.) and never appear in the slots panel or need wiring.
  Same substitution pass, different bracket.

  Syntax matches the workspace convention (`phoenix_kit_ai.Prompt`,
  publishing's translation module): `\\w+` names, inline interpolation
  OK anywhere text or an image `src` is accepted.

  ## Slot type inference

  Slots pick up a type from *where they appear*:

  - text/stamp element content, background color → `:text`
  - image element `src` → `:image`

  A slot referenced from multiple element kinds keeps whichever type
  came first. Wiring at assignment time filters module variables by
  type so an `:image` slot only shows image-typed vars in its
  dropdown.
  """

  @slot_regex ~r/\{\{(\w+)\}\}/
  @global_regex ~r/\[\[(\w+)\]\]/

  @doc "Returns unique `[[global]]` names referenced in a string."
  @spec globals_used(String.t() | nil) :: [String.t()]
  def globals_used(nil), do: []

  def globals_used(text) when is_binary(text) do
    @global_regex
    |> Regex.scan(text)
    |> Enum.map(fn [_full, name] -> name end)
    |> Enum.uniq()
  end

  @type t :: %{name: String.t(), type: :text | :image}

  @doc """
  Returns unique slots used in the canvas, in first-appearance order.
  """
  @spec used(map()) :: [t()]
  def used(canvas) when is_map(canvas) do
    # Also scan the background src, since users can wire an image slot
    # (`{{background_image}}`) as the canvas backdrop from the template
    # props panel.
    bg_fields =
      case Map.get(canvas, "background", %{}) do
        %{"type" => "image", "value" => v} when is_binary(v) -> [{v, :image}]
        _ -> []
      end

    elements =
      canvas
      |> PhoenixKitOG.Canvas.elements()
      |> Enum.flat_map(&slot_fields/1)

    (bg_fields ++ elements)
    |> Enum.flat_map(&extract_names/1)
    |> Enum.reduce({[], MapSet.new()}, fn {name, type}, {acc, seen} ->
      if MapSet.member?(seen, name) do
        {acc, seen}
      else
        {[%{name: name, type: type} | acc], MapSet.put(seen, name)}
      end
    end)
    |> then(fn {acc, _} -> Enum.reverse(acc) end)
  end

  @doc """
  Substitutes both `{{name}}` (wired slot) and `[[name]]` (global)
  references from the values map. Unknown names pass through unchanged
  so the raw token stays visible — matches the workspace convention.

  Callers merge globals + wired slot values into a single map before
  calling; both bracket styles read the same map, and the distinction
  matters only for `Slots.used/1` (which lists slots for the wiring
  UI and only picks up `{{...}}`).
  """
  @spec substitute(String.t() | nil, %{optional(String.t()) => String.t()}) :: String.t()
  def substitute(nil, _values), do: ""

  def substitute(text, values) when is_binary(text) and is_map(values) do
    text
    |> replace_with(@slot_regex, values)
    |> replace_with(@global_regex, values)
  end

  defp replace_with(text, regex, values) do
    Regex.replace(regex, text, fn full, name ->
      case Map.get(values, name) do
        nil -> full
        v -> to_string(v)
      end
    end)
  end

  # =========================================================================
  # Per-element scanning
  # =========================================================================

  # Returns `[{text, :text | :image}]` — the fields we scan for slot
  # references, tagged with the type the slot inherits from that field.
  defp slot_fields(%{"type" => "text"} = el) do
    [{Map.get(el, "text", ""), :text}, {Map.get(el, "binding", ""), :text}]
  end

  defp slot_fields(%{"type" => "stamp"} = el),
    do: [{Map.get(el, "preset", ""), :text}]

  defp slot_fields(%{"type" => "image"} = el),
    do: [{Map.get(el, "src", ""), :image}]

  defp slot_fields(_), do: []

  # Extract `{{name}}` occurrences from a string, each tagged with the
  # field-declared type.
  defp extract_names({text, type}) when is_binary(text) do
    @slot_regex
    |> Regex.scan(text)
    |> Enum.map(fn [_full, name] -> {name, type} end)
  end

  defp extract_names(_), do: []
end
