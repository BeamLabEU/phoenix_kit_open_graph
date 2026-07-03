defmodule PhoenixKitOG.Web.ImageController do
  @moduledoc """
  Serves rendered OG PNGs from the on-disk cache.

  Route: `GET /og-image/:key.png` → 200 PNG bytes if the cache file
  exists, 404 otherwise. The cache key is the hash returned by
  `PhoenixKitOG.Render.Cache.key_and_path/2`; renders are cheap to
  rebuild on cache miss, but `refine_og/4` always renders first and
  embeds the URL only on success, so a 404 here means an external
  cache-warm request or a long-since-purged entry.

  Public route — no auth — because OG image consumers (Facebook,
  Twitter, LinkedIn crawlers) don't carry sessions.
  """

  use Phoenix.Controller, formats: [:html]

  import Plug.Conn

  alias PhoenixKitOG.Render.Cache

  @max_key_length 64

  def show(conn, %{"key" => key}) do
    # Defensive: the route already validates the shape, but reject
    # anything that looks like a path-traversal attempt or wild chars.
    cond do
      String.length(key) > @max_key_length ->
        send_resp(conn, 400, "Bad request")

      not Regex.match?(~r/\A[a-f0-9]+\z/, key) ->
        send_resp(conn, 400, "Bad request")

      true ->
        case Cache.read(key) do
          {:ok, bytes} ->
            conn
            # Pass `nil` for charset — the default `; charset=utf-8`
            # suffix on Content-Type trips some strict social crawlers
            # (Telegram in particular) into dropping the preview when
            # they see a text charset attached to a binary MIME.
            |> put_resp_content_type("image/png", nil)
            |> put_resp_header(
              "cache-control",
              "public, max-age=#{:timer.hours(24 * 30) |> div(1000)}, immutable"
            )
            |> put_resp_header("content-length", Integer.to_string(byte_size(bytes)))
            |> send_resp(200, bytes)

          {:error, _} ->
            send_resp(conn, 404, "Not found")
        end
    end
  end
end
