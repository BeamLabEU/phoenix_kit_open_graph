defmodule PhoenixKitOG.AssignmentsTest do
  alias PhoenixKitOG.Test.Repo

  @moduledoc """
  Context tests for Assignments — the set/clear/update upsert paths, the
  concurrent-set constraint guard, and (the crown jewel) the
  most-specific-wins template resolution hierarchy.
  """
  use PhoenixKitOG.DataCase, async: false

  alias PhoenixKitOG.{Assignments, SceneStore, Templates}
  alias PhoenixKitOG.Schemas.Assignment

  @module "publishing"

  defp template!(name \\ nil) do
    {:ok, t} =
      Templates.create(%{
        "name" => name || "T-#{System.unique_integer([:positive])}",
        "canvas" => SceneStore.dump(SceneStore.blank())
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
               |> Repo.insert()

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

  describe "create/6" do
    alias PhoenixKitOG.ActivityRows

    test "writes the template and the slot mapping in one row and one activity entry" do
      actor = Ecto.UUID.generate()
      t = template!()

      assert {:ok, a} =
               Assignments.create(
                 "publishing",
                 "default",
                 nil,
                 t.uuid,
                 %{"Title" => "post_title"},
                 actor_uuid: actor
               )

      assert a.slot_mapping == %{"Title" => "post_title"}

      assert [%{resource_uuid: uuid, actor_uuid: ^actor}] =
               ActivityRows.rows("assignment.created")

      assert uuid == a.uuid
      assert ActivityRows.rows("assignment.slot_mapping_updated") == []
    end

    test "refuses a scope that already has an assignment instead of replacing it" do
      t1 = template!()
      t2 = template!()
      {:ok, first} = Assignments.create("publishing", "default", nil, t1.uuid, %{})

      assert {:error, %Ecto.Changeset{}} =
               Assignments.create("publishing", "default", nil, t2.uuid, %{})

      assert Assignments.get("publishing", "default", nil).template_uuid == first.template_uuid
    end
  end

  describe "update/4" do
    alias PhoenixKitOG.ActivityRows

    test "changes the template and mapping of that row with one activity entry" do
      actor = Ecto.UUID.generate()
      group = Ecto.UUID.generate()
      t1 = template!()
      t2 = template!()
      {:ok, a} = Assignments.create("publishing", "group", group, t1.uuid, %{})

      assert {:ok, updated} =
               Assignments.update(a, t2.uuid, %{"Title" => "custom:Hi"}, actor_uuid: actor)

      assert updated.uuid == a.uuid
      assert updated.scope_uuid == group
      assert updated.template_uuid == t2.uuid
      assert updated.slot_mapping == %{"Title" => "custom:Hi"}

      assert [%{resource_uuid: uuid, actor_uuid: ^actor}] =
               ActivityRows.rows("assignment.updated")

      assert uuid == a.uuid
      assert ActivityRows.rows("assignment.slot_mapping_updated") == []
    end
  end

  describe "get_by_uuid/1 + count_by_template/0 + list_for_template/1" do
    test "get_by_uuid finds the row with its template, and nil for anything else" do
      t = template!()
      {:ok, a} = Assignments.create("publishing", "default", nil, t.uuid, %{})

      assert %{uuid: uuid, template: %{uuid: template_uuid}} = Assignments.get_by_uuid(a.uuid)
      assert uuid == a.uuid
      assert template_uuid == t.uuid
      assert Assignments.get_by_uuid(Ecto.UUID.generate()) == nil
      assert Assignments.get_by_uuid("new") == nil
    end

    test "counts and lists assignments per template" do
      used = template!()
      unused = template!()
      {:ok, _} = Assignments.create("publishing", "default", nil, used.uuid, %{})
      {:ok, _} = Assignments.create("publishing", "group", Ecto.UUID.generate(), used.uuid, %{})

      assert Assignments.count_by_template() == %{used.uuid => 2}
      assert length(Assignments.list_for_template(used.uuid)) == 2
      assert Assignments.list_for_template(unused.uuid) == []
    end
  end
end
