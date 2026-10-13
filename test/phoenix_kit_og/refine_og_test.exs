defmodule PhoenixKitOG.RefineOgTest do
  @moduledoc """
  `refine_og/4` end to end: a real `%Plug.Conn{}`, a post map shaped like
  the one publishing's mapper builds, a stored template and assignment,
  and the real render pipeline.

  A PNG cannot be read back as text, so what was drawn is pinned through
  the cache identity: the image URL `refine_og/4` returns must be the one
  `Render.render_url/2` gives for the values and globals spelled out
  here, and must differ from the ones the wrong inputs would give.
  """
  use PhoenixKitOG.DataCase, async: false

  import ExUnit.CaptureLog

  alias OpenFresco.Scene
  alias PhoenixKitOG.{Assignments, Render, SceneStore, Templates}
  alias PhoenixKitOG.Render.Media
  alias PhoenixKitOG.Test.Publishing

  @moduletag :rasterizer

  @group_uuid "0197a5b3-aaaa-7000-8000-00000000abcd"
  @canonical "https://site.example/blog/a-real-post"

  setup do
    dir = Path.join(System.tmp_dir!(), "pk_og_refine_test_#{System.unique_integer([:positive])}")
    Application.put_env(:phoenix_kit_og, :cache_dir, dir)

    # The settings cache, so enabling the module is not a warning per read.
    start_supervised!({Registry, keys: :unique, name: PhoenixKit.Cache.Registry})
    start_supervised!({PhoenixKit.Cache, name: :settings})

    Publishing.register()
    Publishing.put_groups([%{"uuid" => @group_uuid, "slug" => "blog", "name" => "Blog"}])
    {:ok, _} = PhoenixKitOG.enable_system()

    on_exit(fn ->
      Application.delete_env(:phoenix_kit_og, :cache_dir)
      Publishing.reset()
      File.rm_rf(dir)
    end)

    :ok
  end

  defp conn(host \\ "site.example") do
    %{Plug.Test.conn(:get, "/blog/a-real-post") | host: host, scheme: :https, port: 443}
  end

  defp og(overrides \\ %{}) do
    Map.merge(
      %{
        title: "A real post",
        description: nil,
        image: "https://site.example/featured.jpg",
        url: @canonical,
        locale: "en",
        type: "article"
      },
      overrides
    )
  end

  defp text(id, y, value),
    do: Scene.text(id, box: %{x: 40, y: y, w: 1000, h: 80}, value: value)

  defp template!(elements, name \\ nil) do
    scene = Enum.reduce(elements, SceneStore.blank(), &Scene.add(&2, &1))

    {:ok, template} =
      Templates.create(%{
        "name" => name || "T-#{System.unique_integer([:positive])}",
        "canvas" => SceneStore.dump(scene)
      })

    template
  end

  defp key(url), do: url |> String.split("/") |> List.last()

  defp render_key(template, values, globals) do
    {:ok, path} = Render.render_url(template, %{values: values, globals: globals, mode: :public})
    key(path)
  end

  describe "a wired text slot whose variable has no value" do
    test "draws as empty, never as its {{placeholder}}" do
      template =
        template!([
          text("t", 40, Scene.placeholder("Title")),
          text("d", 200, Scene.placeholder("Description"))
        ])

      {:ok, _} =
        Assignments.create("publishing", "default", nil, template.uuid, %{
          "Title" => "post_title",
          "Description" => "post_description"
        })

      post = Publishing.post(%{metadata: %{title: "A real post", description: nil}})
      refined = PhoenixKitOG.refine_og(og(), conn(), post, "en")

      assert refined.image =~ "/og-image/"
      assert refined.image_type == "image/png"
      assert {refined.image_width, refined.image_height} == {1200, 630}

      emptied = render_key(template, %{"Title" => "A real post", "Description" => ""}, %{})
      placeholder_left = render_key(template, %{"Title" => "A real post"}, %{})

      refute emptied == placeholder_left
      assert key(refined.image) == emptied
    end

    test "keeps every key the consumer passed in" do
      template = template!([text("t", 40, Scene.placeholder("Title"))])

      {:ok, _} =
        Assignments.create("publishing", "default", nil, template.uuid, %{"Title" => "post_title"})

      refined = PhoenixKitOG.refine_og(og(), conn(), Publishing.post(), "en")

      assert Map.take(refined, [:title, :description, :url, :locale, :type]) ==
               Map.take(og(), [:title, :description, :url, :locale, :type])
    end
  end

  describe "[[page_url]]" do
    test "prints the canonical URL the consumer computed, not the literal token" do
      template = template!([text("u", 40, "[[page_url]]")])
      {:ok, _} = Assignments.create("publishing", "default", nil, template.uuid, %{})

      refined = PhoenixKitOG.refine_og(og(), conn(), Publishing.post(), "en")

      with_url = render_key(template, %{}, %{"page_url" => @canonical})
      token_left = render_key(template, %{}, %{})

      refute with_url == token_left
      assert key(refined.image) == with_url
    end

    test "without a canonical URL from the consumer, falls back to the request path" do
      template = template!([text("u", 40, "[[page_url]]")])
      {:ok, _} = Assignments.create("publishing", "default", nil, template.uuid, %{})

      refined = PhoenixKitOG.refine_og(og(%{url: nil}), conn(), Publishing.post(), "en")

      assert key(refined.image) ==
               render_key(template, %{}, %{"page_url" => "https://site.example/blog/a-real-post"})
    end
  end

  describe "the request's Host header" do
    test "does not mint a new image when the template uses no global" do
      template = template!([text("t", 40, Scene.placeholder("Title"))])

      {:ok, _} =
        Assignments.create("publishing", "default", nil, template.uuid, %{"Title" => "post_title"})

      post = Publishing.post()
      a = PhoenixKitOG.refine_og(og(), conn("site.example"), post, "en")
      b = PhoenixKitOG.refine_og(og(), conn("evil-1.example"), post, "en")

      assert key(a.image) == key(b.image)
    end
  end

  describe "an image slot given a remote URL" do
    test "is left off the public card instead of shipping a stand-in" do
      image =
        Scene.image("hero",
          box: %{x: 0, y: 0, w: 300, h: 200},
          value: Scene.placeholder("Hero"),
          fit: :cover
        )

      with_image = template!([text("t", 300, "Hello"), image])
      without_image = template!([text("t", 300, "Hello")])

      {:ok, _} =
        Assignments.create("publishing", "default", nil, with_image.uuid, %{
          "Hero" => "custom:https://cdn.example/x.png"
        })

      refined = PhoenixKitOG.refine_og(og(), conn(), Publishing.post(), "en")
      assert refined.image =~ "/og-image/"

      # Same pixels as the template that never had the image element: the
      # prepared scenes are identical once the element is dropped.
      {dropped, _} =
        Media.prepare(
          SceneStore.load(with_image.canvas),
          %{"Hero" => "https://cdn.example/x.png"},
          :public
        )

      assert SceneStore.dump(dropped) == SceneStore.dump(SceneStore.load(without_image.canvas))
    end
  end

  describe "the scope hierarchy for a real post" do
    test "a group assignment wins over the module default (the post names its group by slug)" do
      default_template = template!([text("t", 40, "default")])
      group_template = template!([text("t", 40, "group")])
      {:ok, _} = Assignments.create("publishing", "default", nil, default_template.uuid, %{})
      {:ok, _} = Assignments.create("publishing", "group", @group_uuid, group_template.uuid, %{})

      refined = PhoenixKitOG.refine_og(og(), conn(), Publishing.post(%{group: "blog"}), "en")

      assert key(refined.image) == render_key(group_template, %{}, %{})
      refute key(refined.image) == render_key(default_template, %{}, %{})
    end

    test "a post in another group falls through to the default" do
      default_template = template!([text("t", 40, "default")])
      group_template = template!([text("t", 40, "group")])
      {:ok, _} = Assignments.create("publishing", "default", nil, default_template.uuid, %{})
      {:ok, _} = Assignments.create("publishing", "group", @group_uuid, group_template.uuid, %{})

      refined = PhoenixKitOG.refine_og(og(), conn(), Publishing.post(%{group: "docs"}), "en")

      assert key(refined.image) == render_key(default_template, %{}, %{})
    end
  end

  describe "pass-through" do
    test "returns og unchanged when no template is assigned" do
      assert PhoenixKitOG.refine_og(og(), conn(), Publishing.post(), "en") == og()
    end

    test "returns og unchanged when the module is disabled" do
      template = template!([text("t", 40, "x")])
      {:ok, _} = Assignments.create("publishing", "default", nil, template.uuid, %{})
      {:ok, _} = PhoenixKitOG.disable_system()

      assert PhoenixKitOG.refine_og(og(), conn(), Publishing.post(), "en") == og()
    end

    test "a raise inside resolution returns og and logs the post uuid, not its content" do
      template = template!([text("t", 40, "x")])
      {:ok, _} = Assignments.create("publishing", "default", nil, template.uuid, %{})
      post = Publishing.post(%{metadata: %{title: "SECRET TITLE"}})

      # A language that cannot be turned into a string raises while the
      # globals are built, after the template has been resolved.
      log =
        capture_log(fn ->
          assert PhoenixKitOG.refine_og(og(), conn(), post, {:not, :a_language}) == og()
        end)

      assert log =~ "refine_og raised"
      assert log =~ post.uuid
      refute log =~ "SECRET TITLE"
    end
  end
end
