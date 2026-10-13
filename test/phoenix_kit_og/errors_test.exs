defmodule PhoenixKitOG.ErrorsTest do
  use ExUnit.Case, async: true

  alias PhoenixKitOG.Errors

  describe "message/1 — known atoms" do
    test "each supported atom has its own exact message" do
      assert Errors.message(:not_found) == "Not found."

      assert Errors.message(:rasterizer_missing) ==
               "Preview render needs the resvg NIF — check that the dep resolved on this build."

      assert Errors.message(:template_missing) == "Pick a template first."
      assert Errors.message(:group_missing) == "Pick a publishing group."
    end
  end

  describe "message/1 — tagged tuples" do
    test "{:render_failed, reason} interpolates the reason" do
      assert Errors.message({:render_failed, :timeout}) == "Preview render failed: :timeout"
    end

    test "very long reasons are truncated with an ellipsis" do
      long_reason = String.duplicate("a", 500)
      msg = Errors.message({:render_failed, long_reason})
      # 100-char cap + trailing ellipsis; the raw 500-char blob never
      # reaches a flash.
      assert String.contains?(msg, "…")
      refute String.contains?(msg, String.duplicate("a", 200))
    end
  end

  describe "message/1 — pass-through shapes" do
    test "an %Ecto.Changeset{} is returned as-is (renderable by <.input>)" do
      cs = %Ecto.Changeset{}
      assert Errors.message(cs) == cs
    end

    test "a plain string is returned unchanged" do
      assert Errors.message("already translated") == "already translated"
    end
  end

  describe "message/1 — fallback" do
    test "unexpected shapes are wrapped, not raised" do
      assert Errors.message({:some_new_reason, :with_data}) ==
               "Unexpected error: {:some_new_reason, :with_data}"
    end
  end
end
