defmodule Hexpm.Accounts.Key do
  use Hexpm.Web, :schema

  @derive Hexpm.Web.Stale
  @derive {Phoenix.Param, key: :name}

  @days_30 60 * 60 * 24 * 30

  schema "keys" do
    field :name, :string
    field :secret_first, :string
    field :secret_second, :string
    field :public, :boolean, default: true
    field :revoke_at, :naive_datetime
    field :revoked_at, :naive_datetime
    timestamps()

    embeds_one :last_use, Use, on_replace: :delete do
      field :used_at, :naive_datetime
      field :user_agent, :string
      field :ip, :string
    end

    belongs_to :user, User
    belongs_to :organization, Organization
    embeds_many :permissions, KeyPermission

    # Only used after key creation to hold the user's key (not hashed)
    # the user key will never be retrievable after this
    field :user_secret, :string, virtual: true
  end

  def changeset(key, user_or_organization, params) do
    cast(key, params, ~w(name)a)
    |> validate_required(~w(name)a)
    |> add_keys()
    |> prepare_changes(&unique_name/1)
    |> cast_embed(:permissions, with: &KeyPermission.changeset(&1, user_or_organization, &2))
    |> put_default_embed(:permissions, [%KeyPermission{domain: "api"}])
  end

  def build(user_or_organization, params) do
    build_assoc(user_or_organization, :keys)
    |> associate_owner(user_or_organization)
    |> changeset(user_or_organization, params)
  end

  def build_for_docs(user, organization) do
    permission =
      KeyPermission.changeset(%KeyPermission{}, user, %{
        "domain" => "docs",
        "resource" => organization
      })

    revoke_at = NaiveDateTime.add(NaiveDateTime.utc_now(), @days_30)

    build_assoc(user, :keys)
    |> change()
    |> add_keys()
    |> put_change(:revoke_at, revoke_at)
    |> put_embed(:permissions, [permission])
  end

  defmacrop query_revoked(key) do
    quote do
      not is_nil(unquote(key).revoked_at) or
        (not is_nil(unquote(key).revoke_at) and unquote(key).revoke_at < fragment("NOW()"))
    end
  end

  def all(user_or_organization) do
    from(
      k in assoc(user_or_organization, :keys),
      where: not query_revoked(k),
      where: k.public
    )
  end

  def get(user_or_organization, name) do
    from(
      k in assoc(user_or_organization, :keys),
      where: k.name == ^name,
      where: not query_revoked(k)
    )
  end

  def get_revoked(user_or_organization, name) do
    from(
      k in assoc(user_or_organization, :keys),
      where: k.name == ^name,
      where: query_revoked(k)
    )
  end

  def revoke(key, revoked_at \\ NaiveDateTime.utc_now()) do
    key
    |> change()
    |> put_change(:revoked_at, key.revoked_at || revoked_at)
    |> validate_required(:revoked_at)
  end

  def revoke_by_name(user_or_organization, key_name, revoked_at \\ NaiveDateTime.utc_now()) do
    from(
      k in assoc(user_or_organization, :keys),
      where: k.name == ^key_name and not query_revoked(k),
      update: [
        set: [
          revoked_at: fragment("?", ^revoked_at),
          updated_at: ^NaiveDateTime.utc_now()
        ]
      ]
    )
  end

  def revoke_all(user_or_organization, revoked_at \\ NaiveDateTime.utc_now()) do
    from(
      k in assoc(user_or_organization, :keys),
      where: not query_revoked(k),
      update: [
        set: [
          revoked_at: fragment("?", ^revoked_at),
          updated_at: ^NaiveDateTime.utc_now()
        ]
      ]
    )
  end

  def gen_key() do
    user_secret = Auth.gen_key()
    app_secret = Application.get_env(:hexpm, :secret)

    <<first::binary-size(32), second::binary-size(32)>> =
      :crypto.hmac(:sha256, app_secret, user_secret)
      |> Base.encode16(case: :lower)

    {user_secret, first, second}
  end

  def update_last_use(key, params) do
    key
    |> change()
    |> put_embed(:last_use, struct(Key.Use, params))
  end

  defp add_keys(changeset) do
    {user_secret, first, second} = gen_key()

    changeset
    |> put_change(:user_secret, user_secret)
    |> put_change(:secret_first, first)
    |> put_change(:secret_second, second)
  end

  defp unique_name(changeset) do
    {:ok, name} = fetch_change(changeset, :name)

    source =
      if changeset.data.organization_id do
        assoc(changeset.data, :organization)
      else
        assoc(changeset.data, :user)
      end

    names =
      from(
        s in source,
        join: k in assoc(s, :keys),
        where: not query_revoked(k),
        select: k.name
      )
      |> changeset.repo.all
      |> Enum.into(MapSet.new())

    name = if MapSet.member?(names, name), do: find_unique_name(name, names), else: name

    put_change(changeset, :name, name)
  end

  defp find_unique_name(name, names, counter \\ 2) do
    name_counter = "#{name}-#{counter}"

    if MapSet.member?(names, name_counter) do
      find_unique_name(name, names, counter + 1)
    else
      name_counter
    end
  end

  def verify_permissions?(key, "api", resource) do
    Enum.any?(key.permissions, fn permission ->
      permission.domain == "api" and
        (is_nil(permission.resource) or permission.resource == resource)
    end)
  end

  def verify_permissions?(key, "repositories", _resource) do
    Enum.any?(key.permissions, &(&1.domain == "repositories"))
  end

  def verify_permissions?(key, "repository", resource) do
    Enum.any?(key.permissions, fn permission ->
      (permission.domain == "repository" and permission.resource == resource) or
        permission.domain == "repositories"
    end)
  end

  def verify_permissions?(key, "docs", resource) do
    Enum.any?(key.permissions, fn permission ->
      permission.domain == "docs" and permission.resource == resource
    end)
  end

  def verify_permissions?(_key, nil, _resource) do
    false
  end

  def revoked?(%Key{} = key) do
    not is_nil(key.revoked_at) or
      (not is_nil(key.revoke_at) and
         NaiveDateTime.compare(key.revoke_at, NaiveDateTime.utc_now()) == :lt)
  end

  def associate_owner(nil, _owner), do: nil
  def associate_owner(%Key{} = key, %User{} = user), do: %{key | user: user, organization: nil}

  def associate_owner(%Key{} = key, %Organization{} = organization),
    do: %{key | user: nil, organization: organization}
end
