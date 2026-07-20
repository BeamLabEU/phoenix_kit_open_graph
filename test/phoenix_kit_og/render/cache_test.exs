defmodule PhoenixKitOG.Render.CacheTest do
  use ExUnit.Case, async: true

  alias PhoenixKitOG.Render.Cache

  # A minimal struct-shaped map — Cache only reads the fields it hashes,
  # so we don't need the full Template schema (which requires a Repo).
  defp fake_template do
    %{
      uuid: "01234567-89ab-cdef-0123-456789abcdef",
      updated_at: ~U[2026-07-02 10:00:00Z],
      canvas: %{"width" => 1200, "height" => 630, "elements" => []}
    }
  end

  describe "key_and_path/2" do
    test "returns a 16-hex-char key + absolute path" do
      {key, path} = Cache.key_and_path(fake_template(), %{values: %{}})

      assert String.length(key) == 16
      assert Regex.match?(~r/\A[a-f0-9]{16}\z/, key)
      assert String.starts_with?(path, System.tmp_dir!())
      assert String.ends_with?(path, "#{key}.png")
    end

    test "same inputs produce the same key" do
      ctx = %{values: %{"Title" => "Hello"}, module_key: "publishing"}
      {k1, _} = Cache.key_and_path(fake_template(), ctx)
      {k2, _} = Cache.key_and_path(fake_template(), ctx)
      assert k1 == k2
    end

    test "different values produce different keys" do
      {k1, _} = Cache.key_and_path(fake_template(), %{values: %{"Title" => "A"}})
      {k2, _} = Cache.key_and_path(fake_template(), %{values: %{"Title" => "B"}})
      refute k1 == k2
    end

    test "bumping template.updated_at invalidates the key" do
      old = fake_template()
      new = %{old | updated_at: ~U[2026-07-02 11:00:00Z]}
      {k1, _} = Cache.key_and_path(old, %{values: %{}})
      {k2, _} = Cache.key_and_path(new, %{values: %{}})
      refute k1 == k2
    end
  end

  describe "prune/0 — eviction" do
    setup do
      dir =
        Path.join(System.tmp_dir!(), "og_cache_prune_test_#{System.unique_integer([:positive])}")

      File.mkdir_p!(dir)
      prev = Application.get_env(:phoenix_kit_og, :cache_dir)
      Application.put_env(:phoenix_kit_og, :cache_dir, dir)

      on_exit(fn ->
        File.rm_rf!(dir)

        if prev,
          do: Application.put_env(:phoenix_kit_og, :cache_dir, prev),
          else: Application.delete_env(:phoenix_kit_og, :cache_dir)

        Application.delete_env(:phoenix_kit_og, :cache_ttl_seconds)
        Application.delete_env(:phoenix_kit_og, :cache_max_files)
      end)

      {:ok, dir: dir}
    end

    test "deletes files older than the TTL, keeps fresh ones", %{dir: dir} do
      Application.put_env(:phoenix_kit_og, :cache_ttl_seconds, 100)

      old_file = Path.join(dir, "aaaaaaaaaaaaaaaa.png")
      new_file = Path.join(dir, "bbbbbbbbbbbbbbbb.png")
      File.write!(old_file, "x")
      File.write!(new_file, "y")
      # Backdate the old file well past the TTL.
      old_posix = System.system_time(:second) - 1_000
      File.touch!(old_file, old_posix)

      assert :ok = Cache.prune()
      refute File.exists?(old_file)
      assert File.exists?(new_file)
    end

    test "caps the file count to cache_max_files, oldest-first", %{dir: dir} do
      Application.put_env(:phoenix_kit_og, :cache_ttl_seconds, 1_000_000)
      Application.put_env(:phoenix_kit_og, :cache_max_files, 2)

      base = System.system_time(:second)

      for {n, age} <- [{"1", 300}, {"2", 200}, {"3", 100}, {"4", 0}] do
        f = Path.join(dir, "ccccccccccccccc#{n}.png")
        File.write!(f, "z")
        File.touch!(f, base - age)
      end

      assert :ok = Cache.prune()
      # Only the 2 newest survive.
      survivors = File.ls!(dir) |> Enum.sort()
      assert length(survivors) == 2
      assert "ccccccccccccccc4.png" in survivors
      assert "ccccccccccccccc3.png" in survivors
    end

    test "never raises on a missing dir" do
      Application.put_env(:phoenix_kit_og, :cache_dir, "/nonexistent/og/cache/xyz")
      assert :ok = Cache.prune()
    end
  end
end
