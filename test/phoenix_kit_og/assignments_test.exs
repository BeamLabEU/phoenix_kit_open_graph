defmodule PhoenixKitOG.AssignmentsTest do
  @moduledoc """
  Context tests for Assignments — the set/clear/update upsert paths, the
  concurrent-set constraint guard, and (the crown jewel) the
  most-specific-wins template resolution hierarchy.
  """
  use PhoenixKitOG.DataCase, async: false

  alias PhoenixKitOG.{Assignments, Canvas, Templates}
  alias PhoenixKitOG.Schemas.Assignment

  @module "publishing"

  defp template!(name \\ nil) do
    {:ok, t} =
      Templates.create(%{
        "name" => name || "T-#{System.unique_integer([:positive])}",
        "canvas" => Canvas.blank()
      })

    t
  end

  describe "set/5 — insert vs update" do
    test "inserts when none exists, updates when it does" do
      t1 = template!()
      t2 = template!()

      assert {:ok, %Assignment{template_uuid: uuid1}} =
               Assignments.set(@module, "default", nil, t1.uuid)

      assert uuid1 == t1.uuid

      # Same scope again → update, not a second row.
      assert {:ok, %Assignment{template_uuid: uuid2}} =
               Assignments.set(@module, "default", nil, t2.uuid)

      assert uuid2 == t2.uuid
      assert length(Assignments.list_for_module(@module)) == 1
    end

    test "a duplicate insert races to a changeset error, not a raised ConstraintError" do
      t = template!()
      g = Ecto.UUID.generate()
      {:ok, existing} = Assignments.set(@module, "group", g, t.uuid)

      # Simulate the concurrent-insert loser: a fresh insert for the same
      # scope. Without the unique_constraint this raises Ecto.ConstraintError
      # (crashing the LV); with it, it's a friendly changeset.
      assert {:error, %Ecto.Changeset{}} =
               %Assignment{}
               |> Assignment.changeset(%{
                 module_key: @module,
                 scope_type: "group",
                 scope_uuid: g,
                 template_uuid: t.uuid
               })
               |> PhoenixKitOG.Test.Repo.insert()

      assert existing.template_uuid == t.uuid
    end
  end

  describe "clear/4" do
    test "removes an existing assignment" do
      t = template!()
      {:ok, _} = Assignments.set(@module, "default", nil, t.uuid)
      assert {:ok, _} = Assignments.clear(@module, "default", nil)
      assert Assignments.list_for_module(@module) == []
    end

    test "returns {:error, :not_found} when there's nothing to clear" do
      assert {:error, :not_found} = Assignments.clear(@module, "default", nil)
    end
  end

  describe "resolve_template_with_mapping/2 — most-specific-wins hierarchy" do
    test "picks the most specific matching tier and skips nil scopes" do
      group_t = template!("group-winner")
      default_t = template!("default-fallback")

      g = Ecto.UUID.generate()
      {:ok, _} = Assignments.set(@module, "group", g, group_t.uuid)
      {:ok, _} = Assignments.set(@module, "default", nil, default_t.uuid)

      # Hierarchy: a nil-scoped post tier (skipped), then group, then default.
      hierarchy = [{"post", nil}, {"group", g}, {"default", nil}]

      assert {:ok, resolved, _mapping} =
               Assignments.resolve_template_with_mapping(@module, hierarchy)

      assert resolved.uuid == group_t.uuid
    end

    test "falls through to the default tier when no specific tier matches" do
      default_t = template!("default-only")
      {:ok, _} = Assignments.set(@module, "default", nil, default_t.uuid)

      hierarchy = [{"group", Ecto.UUID.generate()}, {"default", nil}]

      assert {:ok, resolved, _} =
               Assignments.resolve_template_with_mapping(@module, hierarchy)

      assert resolved.uuid == default_t.uuid
    end

    test "returns :none when nothing in the hierarchy is assigned" do
      assert :none =
               Assignments.resolve_template_with_mapping(@module, [
                 {"group", Ecto.UUID.generate()},
                 {"default", nil}
               ])
    end

    test "carries the winning tier's slot_mapping" do
      t = template!()
      g = Ecto.UUID.generate()
      {:ok, _} = Assignments.set(@module, "group", g, t.uuid)
      a = Assignments.get(@module, "group", g)
      {:ok, _} = Assignments.update_slot_mapping(a, %{"Title" => "post_title"})

      assert {:ok, _t, %{"Title" => "post_title"}} =
               Assignments.resolve_template_with_mapping(@module, [{"group", g}])
    end
  end
end
