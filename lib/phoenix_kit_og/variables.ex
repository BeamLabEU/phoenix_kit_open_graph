defmodule PhoenixKitOG.Variables do
  use Gettext, backend: PhoenixKitOG.Gettext

  @moduledoc """
  Registry + resolver for module-exposed variables that templates can
  bind their slots to.

  ## Sources

  - **Global** — always available regardless of consumer module.
    Owned by this module (see `global/0`). Includes site host, site
    URL, site name, current page URL, current locale.
  - **Module-declared** — external PhoenixKit modules opt in by
    implementing two optional callbacks:

        def og_variables, do: [
          %{name: "post_title", type: :text, label: "Post title", description: "..."},
          %{name: "post_featured_image", type: :image, label: "Featured image"}
        ]

        def og_resolve(var_name, context)
        # context = %{module_key: "publishing", resource: post_map, conn: conn, language: "en"}

    `og_variables/0` declares the shape; `og_resolve/2` fetches the
    value at render time. Both are auto-discovered via
    `PhoenixKit.ModuleDiscovery`.

  Globals + module-declared variables are combined at assignment-time
  in the "wire slots" dropdown — the user sees one list per slot,
  scoped by matching type.
  """

  @type variable :: %{
          name: String.t(),
          type: :text | :image,
          label: String.t(),
          description: String.t()
        }

  # =========================================================================
  # Global variables — OG-module-owned, always available.
  # =========================================================================

  @globals [
    %{
      name: "site_host",
      type: :text,
      label: "Site host",
      description: "e.g. example.com"
    },
    %{
      name: "site_url",
      type: :text,
      label: "Site URL",
      description: "e.g. https://example.com"
    },
    %{
      name: "site_name",
      type: :text,
      label: "Site name",
      description: "From the project_title setting"
    },
    %{
      name: "page_url",
      type: :text,
      label: "Current page URL",
      description: "Full URL of the page carrying this OG image"
    },
    %{
      name: "page_locale",
      type: :text,
      label: "Current locale",
      description: "e.g. en, es-ES"
    }
  ]

  @spec global() :: [variable()]
  def global, do: @globals

  @doc """
  Translated label for one of the OG-owned global variables — literal
  `gettext/1` clauses so `mix gettext.extract` sees them (a `gettext(v.label)`
  over the `@globals` attribute would be invisible to the extractor).
  Returns `nil` for a name that isn't an OG global (e.g. a consumer
  module's own variable), so the caller can fall back to `v.label`.
  """
  @spec global_label(String.t()) :: String.t() | nil
  def global_label("site_host"), do: gettext("Site host")
  def global_label("site_url"), do: gettext("Site URL")
  def global_label("site_name"), do: gettext("Site name")
  def global_label("page_url"), do: gettext("Current page URL")
  def global_label("page_locale"), do: gettext("Current locale")
  def global_label(_), do: nil

  @doc "Translated description for an OG-owned global; `nil` otherwise."
  @spec global_description(String.t()) :: String.t() | nil
  def global_description("site_host"), do: gettext("e.g. example.com")
  def global_description("site_url"), do: gettext("e.g. https://example.com")
  def global_description("site_name"), do: gettext("From the project_title setting")
  def global_description("page_url"), do: gettext("Full URL of the page carrying this OG image")
  def global_description("page_locale"), do: gettext("e.g. en, es-ES")
  def global_description(_), do: nil

  @doc "Merged list — globals + everything a consumer module declares."
  @spec for_module(String.t()) :: [variable()]
  def for_module(module_key) when is_binary(module_key) do
    from_module = module_declared_vars(module_key)
    from_module ++ @globals
  end

  def for_module(_), do: @globals

  # =========================================================================
  # Resolution — turn a slot mapping into the values map the renderer
  # substitutes into `{{...}}`.
  # =========================================================================

  @doc """
  Given the slots a template uses, an assignment's `slot_mapping`
  (`%{slot_name => variable_name}`), and a resolution context,
  produces the substitution values map for the renderer.

  A slot with no wire is left out of the result — the renderer leaves
  `{{slot}}` visible, the "needs wiring" signal.

  A WIRED slot whose variable resolves to nothing (a post without a
  description, an unknown variable name) depends on `opts[:unresolved]`:

    * `:skip` (default) — left out, so an editor preview keeps the
      placeholder;
    * `:empty` — resolved to `""`. The crawler-facing render uses this: a
      missing value must read as nothing, never as `{{Description}}`.
  """
  @spec resolve(
          [%{name: String.t(), type: :text | :image}],
          %{String.t() => String.t()},
          map(),
          keyword()
        ) :: %{String.t() => String.t()}
  def resolve(slots, slot_mapping, context, opts \\ []) do
    globals_values = resolve_globals(context)
    unresolved = Keyword.get(opts, :unresolved, :skip)

    Enum.reduce(slots, %{}, fn %{name: slot_name}, acc ->
      case Map.get(slot_mapping, slot_name) do
        nil -> acc
        var_name -> put_resolved(acc, slot_name, var_name, context, globals_values, unresolved)
      end
    end)
  end

  # =========================================================================
  # Internals
  # =========================================================================

  # A `custom:` prefix in the mapping means the assignment carries a
  # literal value the author typed in (or a media UUID they picked)
  # rather than a variable name to resolve. Pass it through verbatim.
  defp put_resolved(acc, slot_name, "custom:" <> value, _context, _globals_values, _unresolved),
    do: Map.put(acc, slot_name, value)

  defp put_resolved(acc, slot_name, var_name, context, globals_values, unresolved) do
    if Map.has_key?(globals_values, var_name) do
      Map.put(acc, slot_name, globals_values[var_name])
    else
      case {resolve_via_module(var_name, context), unresolved} do
        {{:ok, value}, _} -> Map.put(acc, slot_name, to_string(value))
        {:error, :empty} -> Map.put(acc, slot_name, "")
        {:error, _skip} -> acc
      end
    end
  end

  defp resolve_via_module(var_name, %{module_key: module_key} = context) do
    with mod when is_atom(mod) <- module_for_key(module_key),
         true <- function_exported?(mod, :og_resolve, 2),
         value when not is_nil(value) <- safe_apply(mod, :og_resolve, [var_name, context]) do
      {:ok, value}
    else
      _ -> :error
    end
  end

  defp resolve_via_module(_, _), do: :error

  defp safe_apply(mod, fun, args) do
    apply(mod, fun, args)
  rescue
    _ -> nil
  end

  @doc """
  Flat map of all `[[global]]` values, ready to merge into the
  substitution map.

  The site origin behind `site_host` / `site_url` / `page_url` is the
  site's CONFIGURED one, never the request's `Host` header (anyone can
  send any `Host`, and these values end up in a cached public image):

    1. the `:canonical_host_resolver` MFA (`config :phoenix_kit`), called
       with the page language — a multi-domain host's per-language home;
    2. the `site_url` setting;
    3. the endpoint's configured URL (`:endpoint` in the context — how the
       editor previews real values without a request — else the parent
       app's endpoint);
    4. only when none of those is set, the origin the request arrived on.

  `page_url` is the context's `:page_url` when the caller has the
  canonical URL in hand, else the origin plus the request path.
  """
  @spec global_values(map()) :: %{String.t() => String.t()}
  def global_values(context \\ %{}) do
    conn = Map.get(context, :conn)
    language = context |> Map.get(:language, "") |> to_string()
    origin = origin(conn, Map.get(context, :endpoint), language)

    %{
      "site_host" => origin_host(origin),
      "site_url" => origin,
      "site_name" => project_title(),
      "page_url" => Map.get(context, :page_url) || page_url(origin, conn),
      "page_locale" => language
    }
  end

  @doc """
  The subset of `globals` a render can actually draw: the names that
  appear as a `[[name]]` token in the scene or in a slot value (custom
  text may carry one), plus a slot that shares a global's name (the
  renderer resolves both brackets from one merged map).

  The render cache hashes this subset, so a global the template never
  mentions cannot mint a new cache entry.
  """
  @spec referenced_globals(map(), term(), map()) :: map()
  def referenced_globals(globals, scene_dump, values) when is_map(globals) do
    names =
      [scene_dump, values]
      |> strings()
      |> Enum.flat_map(&Regex.scan(~r/\[\[(\w+)\]\]|\{\{(\w+)\}\}/, &1, capture: :all_but_first))
      |> List.flatten()
      |> MapSet.new()

    placeholders = scene_dump |> placeholder_names() |> MapSet.new()
    Map.take(globals, MapSet.to_list(MapSet.union(names, placeholders)))
  end

  defp strings(term) when is_binary(term), do: [term]
  defp strings(%_{} = struct), do: struct |> Map.from_struct() |> strings()
  defp strings(term) when is_map(term), do: Enum.flat_map(term, fn {_k, v} -> strings(v) end)
  defp strings(term) when is_list(term), do: Enum.flat_map(term, &strings/1)
  defp strings(_), do: []

  # A whole-value slot is stored as `%{"placeholder" => name}` rather than
  # as its `{{name}}` token.
  defp placeholder_names(%{"placeholder" => name}) when is_binary(name), do: [name]
  defp placeholder_names(%{placeholder: name}) when is_binary(name), do: [name]
  defp placeholder_names(%_{} = struct), do: struct |> Map.from_struct() |> placeholder_names()

  defp placeholder_names(term) when is_map(term),
    do: Enum.flat_map(term, fn {_k, v} -> placeholder_names(v) end)

  defp placeholder_names(term) when is_list(term), do: Enum.flat_map(term, &placeholder_names/1)
  defp placeholder_names(_), do: []

  defp resolve_globals(ctx), do: global_values(ctx)

  # An endpoint that never got a `url:` answers with one of these; such a
  # placeholder must not beat the request the visitor actually made.
  @placeholder_hosts ~w(localhost 127.0.0.1 0.0.0.0 [::1] ::1)

  defp origin(conn, endpoint, language) do
    canonical_host_origin(language) || site_url_setting() || endpoint_origin(endpoint) ||
      request_origin(conn) || raw_endpoint_url(endpoint)
  end

  defp canonical_host_origin(language) do
    with {mod, fun} <- Application.get_env(:phoenix_kit, :canonical_host_resolver),
         host when is_binary(host) and host != "" <- apply(mod, fun, [language]) do
      "https://" <> host
    else
      _ -> nil
    end
  rescue
    _ -> nil
  catch
    :exit, _ -> nil
  end

  defp site_url_setting do
    case PhoenixKit.Settings.get_setting("site_url", "") do
      url when is_binary(url) and url != "" -> String.trim_trailing(url, "/")
      _ -> nil
    end
  rescue
    _ -> nil
  catch
    :exit, _ -> nil
  end

  defp endpoint_origin(endpoint) do
    with url when is_binary(url) and url != "" <- configured_endpoint_url(endpoint),
         %URI{host: host} when is_binary(host) and host not in @placeholder_hosts <-
           URI.parse(url) do
      String.trim_trailing(url, "/")
    else
      _ -> nil
    end
  end

  defp configured_endpoint_url(endpoint) when is_atom(endpoint) and not is_nil(endpoint) do
    endpoint.url()
  rescue
    _ -> nil
  end

  defp configured_endpoint_url(_) do
    case PhoenixKit.Config.get_parent_endpoint_url() do
      {:ok, url} -> url
      _ -> nil
    end
  rescue
    _ -> nil
  end

  defp request_origin(%Plug.Conn{scheme: scheme, host: host, port: port}) do
    port_suffix = if port in [80, 443, nil], do: "", else: ":#{port}"
    "#{scheme}://#{host}#{port_suffix}"
  end

  defp request_origin(_), do: nil

  defp raw_endpoint_url(endpoint), do: configured_endpoint_url(endpoint) || ""

  defp origin_host(origin) do
    case URI.parse(origin) do
      %URI{host: host} when is_binary(host) -> host
      _ -> ""
    end
  end

  defp page_url(origin, %Plug.Conn{request_path: path}) when is_binary(path), do: origin <> path
  defp page_url(_origin, _conn), do: ""

  defp project_title do
    PhoenixKit.Settings.get_setting("project_title") |> to_string()
  rescue
    _ -> ""
  end

  # =========================================================================
  # Module discovery
  # =========================================================================

  defp module_declared_vars(module_key) do
    case module_for_key(module_key) do
      nil ->
        []

      mod ->
        if function_exported?(mod, :og_variables, 0),
          do: safe_apply(mod, :og_variables, []) || [],
          else: []
    end
  end

  # Consumer modules identify themselves by `module_key/0` (e.g.
  # `"publishing"`). Discovery scans all PhoenixKit-registered modules
  # for a matching key.
  defp module_for_key(module_key) do
    PhoenixKit.ModuleDiscovery.discover_external_modules()
    |> Enum.find(fn mod ->
      Code.ensure_loaded?(mod) and
        function_exported?(mod, :module_key, 0) and
        safe_apply(mod, :module_key, []) == module_key
    end)
  rescue
    _ -> nil
  end
end
