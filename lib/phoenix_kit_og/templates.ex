defmodule PhoenixKitOg.Templates do
  @moduledoc """
  Context for managing OpenGraph templates. CRUD only — the editor and
  renderer live elsewhere.
  """

  import Ecto.Query, warn: false

  alias PhoenixKit.RepoHelper, as: Repo
  alias PhoenixKitOg.Schemas.Template

  @doc "Returns all templates, ordered by name."
  @spec list() :: [Template.t()]
  def list do
    Repo.all(from t in Template, order_by: [asc: t.name])
  end

  @doc "Returns `nil` when no template matches."
  @spec get(binary()) :: Template.t() | nil
  def get(uuid) when is_binary(uuid), do: Repo.get(Template, uuid)

  @spec create(map()) :: {:ok, Template.t()} | {:error, Ecto.Changeset.t()}
  def create(attrs) do
    %Template{}
    |> Template.changeset(attrs)
    |> Repo.insert()
  end

  @spec update(Template.t(), map()) :: {:ok, Template.t()} | {:error, Ecto.Changeset.t()}
  def update(%Template{} = template, attrs) do
    template
    |> Template.changeset(attrs)
    |> Repo.update()
  end

  @spec delete(Template.t()) :: {:ok, Template.t()} | {:error, Ecto.Changeset.t()}
  def delete(%Template{} = template), do: Repo.delete(template)

  @spec change(Template.t(), map()) :: Ecto.Changeset.t()
  def change(%Template{} = template, attrs \\ %{}),
    do: Template.changeset(template, attrs)
end
