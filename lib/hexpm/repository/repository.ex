defmodule Hexpm.Repository.Repository do
  use Hexpm.Web, :schema

  @derive Hexpm.Web.Stale
  @derive {Phoenix.Param, key: :name}

  schema "repositories" do
    field :name, :string
    field :public, :boolean
    field :billing_active, :boolean, default: false
    timestamps()

    has_many :packages, Package
    has_many :repository_users, RepositoryUser
    has_many :users, through: [:repository_users, :user]
    has_many :audit_logs, AuditLog, foreign_key: :repository_id
  end

  @name_regex ~r"^[a-z0-9_\-\.]+$"
  @roles ~w(admin write read)

  def changeset(struct, params) do
    cast(struct, params, ~w(name)a)
    |> validate_required(~w(name)a)
    |> unique_constraint(:name)
    |> update_change(:name, &String.downcase/1)
    |> validate_length(:name, min: 3)
    |> validate_format(:name, @name_regex)
    |> put_change(:public, false)
  end

  def add_member(struct, params) do
    cast(struct, params, ~w(role)a)
    |> validate_required(~w(role)a)
    |> validate_inclusion(:role, @roles)
    |> unique_constraint(
      :user_id,
      name: "repository_users_repository_id_user_id_index",
      message: "is already member"
    )
  end

  def change_role(struct, params) do
    cast(struct, params, ~w(role)a)
    |> validate_required(~w(role)a)
    |> validate_inclusion(:role, @roles)
  end

  def has_access(repository, user, role) do
    from(
      ro in RepositoryUser,
      where: ro.repository_id == ^repository.id,
      where: ro.user_id == ^user.id,
      where: ro.role in ^role_or_higher(role),
      select: count(ro.id) >= 1
    )
  end

  def role_or_higher("read"), do: ["read", "write", "admin"]
  def role_or_higher("write"), do: ["write", "admin"]
  def role_or_higher("admin"), do: ["admin"]

  def hexpm() do
    %__MODULE__{
      id: 1,
      name: "hexpm",
      public: true
    }
  end
end
