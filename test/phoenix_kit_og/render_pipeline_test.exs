defmodule PhoenixKitOG.RenderPipelineTest do
  # async: false — writes to the shared on-disk render cache.
  use ExUnit.Case, async: false

  alias PhoenixKitOG.Render
  alias PhoenixKitOG.Schemas.Template

  @moduletag :rasterizer

  # The resvg NIF ships as this repo's own optional dep, so the
  # standalone suite always has a backend; guard anyway so a host
  # without one skips instead of failing.
  setup_all do
    if OpenFresco.rasterizer_available?() do
      :ok
    else
      {:ok, skip: true}
    end
  end

  setup do
    dir =
      Path.join(System.tmp_dir!(), "pk_og_pipeline_test_#{System.unique_integer([:positive])}")

    Application.put_env(:phoenix_kit_og, :cache_dir, dir)
    on_exit(fn -> Application.delete_env(:phoenix_kit_og, :cache_dir) end)
    :ok
  end

  # A LEGACY canvas — the pipeline must lazily migrate it and render.
  defp legacy_template do
    %Template{
      uuid: "0197a5b3-1111-7000-8000-00000000abcd",
      name: "t",
      canvas: %{
        "width" => 600,
        "height" => 315,
        "background" => %{"type" => "color", "value" => "#0b1220"},
        "elements" => [
          %{
            "type" => "text",
            "id" => "t1",
            "x" => 40,
            "y" => 60,
            "width" => 520,
            "height" => 120,
            "text" => "{{Title}} — [[site_name]]",
            "size" => 40,
            "color" => "#ffffff",
            "weight" => 700
          }
        ]
      },
      updated_at: nil
    }
  end

  test "renders a legacy canvas end-to-end through OpenFresco" do
    assert {:ok, url} =
             Render.render_url(legacy_template(), %{
               values: %{"Title" => "Hello"},
               globals: %{"site_name" => "Acme"},
               mode: :public
             })

    assert url =~ "/og-image/"

    key = url |> String.split("/") |> List.last()
    assert {:ok, png} = PhoenixKitOG.Render.Cache.read(key)
    assert <<137, ?P, ?N, ?G, _::binary>> = png
  end

  test "same inputs hit the cache (same URL), changed values/globals re-key" do
    ctx = %{values: %{"Title" => "A"}, globals: %{"site_name" => "S"}, mode: :public}

    assert {:ok, url1} = Render.render_url(legacy_template(), ctx)
    assert {:ok, url2} = Render.render_url(legacy_template(), ctx)
    assert url1 == url2

    assert {:ok, url3} = Render.render_url(legacy_template(), put_in(ctx.values["Title"], "B"))
    refute url3 == url1

    assert {:ok, url4} =
             Render.render_url(legacy_template(), put_in(ctx.globals["site_name"], "Z"))

    refute url4 == url1
  end

  test ":public and :preview render distinct artifacts for unresolved image slots" do
    template = %Template{
      uuid: "0197a5b3-2222-7000-8000-00000000abcd",
      name: "t2",
      canvas: %{
        "width" => 600,
        "height" => 315,
        "background" => %{"type" => "image", "value" => "{{Bg}}"},
        "elements" => []
      },
      updated_at: nil
    }

    assert {:ok, public_url} = Render.render_url(template, %{values: %{}, mode: :public})
    assert {:ok, preview_url} = Render.render_url(template, %{values: %{}, mode: :preview})

    # Public gets the dark fallback, preview gets the labeled stand-in —
    # different pixels, different cache identities.
    refute public_url == preview_url
  end
end
