defmodule PhoenixKitOG.Test.Publishing do
  @moduledoc """
  Test-only stand-ins for `phoenix_kit_publishing`, which is an optional
  peer and not a dependency of this package.

  The three modules below take the real modules' names so the guarded
  seams (`Code.ensure_loaded?/1` + `function_exported?/3`) dispatch to
  them:

    * `PhoenixKit.Modules.Publishing` — the consumer module, with the
      `og_variables/0` / `og_resolve/2` contract and the same reads off a
      post map as the real one. `PhoenixKit.ModuleDiscovery` only sees it
      once a test lists it under `config :phoenix_kit, :modules`
      (`register/0`).
    * `PhoenixKit.Modules.Publishing.Groups` / `.Posts` — the group and
      post listings the assignments admin and the group tier read.

  Groups and posts come from the application env so each test seeds its
  own; an unseeded test sees none, like a host without publishing.
  """

  @doc "Seeds the groups the stubs list: maps with string `uuid`, `slug` and `name` keys."
  def put_groups(groups),
    do: Application.put_env(:phoenix_kit_og, :test_publishing_groups, groups)

  @doc "Seeds the posts listed for one group slug."
  def put_posts(slug, posts) do
    current = Application.get_env(:phoenix_kit_og, :test_publishing_posts, %{})
    Application.put_env(:phoenix_kit_og, :test_publishing_posts, Map.put(current, slug, posts))
  end

  @doc "Makes the stub consumer discoverable by its `module_key/0`."
  def register do
    Application.put_env(:phoenix_kit, :modules, [PhoenixKit.Modules.Publishing])
  end

  @doc "Drops everything a test seeded."
  def reset do
    Application.delete_env(:phoenix_kit_og, :test_publishing_groups)
    Application.delete_env(:phoenix_kit_og, :test_publishing_posts)
    Application.delete_env(:phoenix_kit, :modules)
  end

  @doc """
  A post map shaped like `PhoenixKit.Modules.Publishing.DBStorage.Mapper.to_post_map/6`
  builds it: the group is its SLUG at `:group`, and nothing in the map
  carries the group's uuid.
  """
  def post(overrides \\ %{}) do
    metadata =
      Map.merge(
        %{
          title: "A real post",
          description: nil,
          status: "published",
          slug: "a-real-post",
          version: 1,
          allow_version_access: false,
          sitemap_exclude: false,
          url_slug: nil,
          previous_url_slugs: [],
          published_at: "2026-01-01T00:00:00Z",
          featured_image_uuid: nil,
          featured: false,
          tags: [],
          category_uuids: [],
          audio_uuid: nil,
          og: %{}
        },
        Map.get(overrides, :metadata, %{})
      )

    %{
      uuid: Ecto.UUID.generate(),
      group: "blog",
      slug: "a-real-post",
      url_slug: "a-real-post",
      date: ~D[2026-01-01],
      time: ~T[00:00:00],
      mode: :slug,
      language: "en",
      available_languages: ["en"],
      language_statuses: %{"en" => "published"},
      language_slugs: %{"en" => "a-real-post"},
      language_previous_slugs: %{},
      language_titles: %{"en" => "A real post"},
      version: 1,
      available_versions: [1],
      version_statuses: %{1 => "published"},
      version_publication_dates: %{1 => "2026-01-01T00:00:00Z"},
      version_dates: %{1 => "2026-01-01T00:00:00Z"},
      content: "Body text.",
      content_updated_at: ~U[2026-01-01 00:00:00Z]
    }
    |> Map.merge(Map.delete(overrides, :metadata))
    |> Map.put(:metadata, metadata)
  end
end

defmodule PhoenixKit.Modules.Publishing do
  @moduledoc false

  def module_key, do: "publishing"

  def og_variables do
    [
      %{name: "post_title", type: :text, label: "Post title", description: ""},
      %{name: "post_description", type: :text, label: "Post description", description: ""},
      %{name: "post_featured_image", type: :image, label: "Featured image", description: ""}
    ]
  end

  def og_resolve("post_title", %{resource: post}),
    do: override(post, "title") || meta(post, :title)

  def og_resolve("post_description", %{resource: post}),
    do: override(post, "description") || meta(post, :description)

  def og_resolve("post_featured_image", %{resource: post}),
    do: override(post, "image_uuid") || meta(post, :featured_image_uuid)

  def og_resolve(_, _), do: nil

  defp override(%{metadata: %{og: og}}, key) when is_map(og) do
    case Map.get(og, key) do
      v when is_binary(v) and v != "" -> v
      _ -> nil
    end
  end

  defp override(_, _), do: nil

  defp meta(%{metadata: metadata}, key) when is_map(metadata), do: Map.get(metadata, key)
  defp meta(_, _), do: nil
end

defmodule PhoenixKit.Modules.Publishing.Groups do
  @moduledoc false

  def list_groups(_status), do: Application.get_env(:phoenix_kit_og, :test_publishing_groups, [])

  def fetch_group(slug) do
    case Enum.find(list_groups("active"), &(&1["slug"] == slug)) do
      nil -> {:error, :not_found}
      group -> {:ok, group}
    end
  end
end

defmodule PhoenixKit.Modules.Publishing.Posts do
  @moduledoc false

  def list_posts(slug) do
    :phoenix_kit_og
    |> Application.get_env(:test_publishing_posts, %{})
    |> Map.get(slug, [])
  end
end
