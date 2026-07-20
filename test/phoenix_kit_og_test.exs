defmodule PhoenixKitOGTest do
  use ExUnit.Case, async: true

  describe "behaviour implementation" do
    test "implements PhoenixKit.Module" do
      behaviours =
        PhoenixKitOG.__info__(:attributes)
        |> Keyword.get_values(:behaviour)
        |> List.flatten()

      assert PhoenixKit.Module in behaviours
    end

    test "has @phoenix_kit_module attribute for auto-discovery" do
      attrs = PhoenixKitOG.__info__(:attributes)
      assert Keyword.get(attrs, :phoenix_kit_module) == [true]
    end
  end

  describe "required callbacks" do
    test "module_key/0" do
      assert PhoenixKitOG.module_key() == "phoenix_kit_og"
    end

    test "module_name/0" do
      assert PhoenixKitOG.module_name() == "OpenGraph"
    end

    test "enabled?/0 returns a boolean" do
      # No DB in the unit-test env — falls back to false via the rescue clause.
      assert is_boolean(PhoenixKitOG.enabled?())
    end

    test "enable_system/0 and disable_system/0 are exported" do
      # function_exported?/3 does NOT load the module — without this,
      # the assertion flakes under seed orderings where no earlier test
      # has touched PhoenixKitOG yet.
      assert Code.ensure_loaded?(PhoenixKitOG)
      assert function_exported?(PhoenixKitOG, :enable_system, 0)
      assert function_exported?(PhoenixKitOG, :disable_system, 0)
    end
  end

  describe "version/0" do
    test "matches the version in mix.exs" do
      mix_version = Mix.Project.config()[:version]
      assert PhoenixKitOG.version() == mix_version
    end
  end

  describe "permission_metadata/0" do
    test "returns a map with required fields, key matching module_key" do
      assert %{key: key, label: label, icon: icon, description: desc} =
               PhoenixKitOG.permission_metadata()

      assert key == PhoenixKitOG.module_key()
      assert is_binary(label)
      assert String.starts_with?(icon, "hero-")
      assert is_binary(desc)
    end
  end

  describe "admin_tabs/0" do
    test "returns the OpenGraph, Templates, and Assignments tabs" do
      tabs = PhoenixKitOG.admin_tabs()

      assert [
               %{id: :admin_phoenix_kit_og},
               %{id: :admin_phoenix_kit_og_templates},
               %{id: :admin_phoenix_kit_og_assignments}
             ] = tabs

      assert Enum.all?(tabs, &(&1.permission == PhoenixKitOG.module_key()))
    end
  end

  describe "css_sources/0" do
    test "registers :phoenix_kit_og for Tailwind scanning" do
      assert PhoenixKitOG.css_sources() == [:phoenix_kit_og]
    end
  end

  describe "route_module/0" do
    test "points at PhoenixKitOG.Routes" do
      assert PhoenixKitOG.route_module() == PhoenixKitOG.Routes
    end
  end
end
