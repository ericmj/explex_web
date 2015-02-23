defmodule HexWeb.Package do
  use Ecto.Model

  import Ecto.Query, only: [from: 2]
  import HexWeb.Validation
  require Ecto.Validator
  alias HexWeb.Util

  schema "packages" do
    field :name, :string
    has_many :owners, HexWeb.PackageOwner
    field :meta, :string
    has_many :releases, HexWeb.Release
    field :created_at, :datetime
    field :updated_at, :datetime
    has_many :downloads, HexWeb.Stats.PackageDownload
  end

  @elixir_names ~w(eex elixir ex_unit iex logger mix hex)
  @otp_names ~w(
    appmon asn1 common_test compiler cosEvent cosEventDomain cosFileTransfer
    cosNotification cosProperty cosTime cosTransactions crypto debugger
    dialyzer diameter edoc eldap erl_docgen erl_interface et eunit gs hipe
    ic inets jinterface kernel Makefile megaco mnesia observer odbc orber
    os_mon ose otp_mibs parsetools percept pman public_key reltool runtime_tools
    sasl snmp ssh ssl stdlib syntax_tools test_server toolbar tools tv typer
    webtool wx xmerl)

  @reserved_names @elixir_names ++ @otp_names

  validatep validate_create(package),
    also: validate(),
    also: unique([:name], case_sensitive: false, on: HexWeb.Repo)

  validatep validate(package),
    name: present() and type(:string) and has_format(~r"^[a-z]\w*$") and
          not_member_of(@reserved_names),
    meta: validate_meta()

  defp validate_meta(field, arg) do
    errors =
      Ecto.Validator.bin_dict(arg,
        contributors: type({:array, :string}),
        licenses:     type({:array, :string}),
        links:        type({:dict, :string, :string}),
        description:  type(:string))

    if errors == [], do: [], else: [{field, errors}]
  end

  @meta_fields [:contributors, :description, :links, :licenses]
  @meta_fields @meta_fields ++ Enum.map(@meta_fields, &Atom.to_string/1)

  def create(name, owner, meta) do
    now = Util.ecto_now
    meta = Dict.take(meta, @meta_fields)
    package = %HexWeb.Package{name: name, meta: meta, created_at: now,
                              updated_at: now}

    case validate_create(package) do
      [] ->
        package = %{package | meta: Poison.encode!(package.meta)}

        {:ok, package} = HexWeb.Repo.transaction(fn ->
          package = HexWeb.Repo.insert(package)

          %HexWeb.PackageOwner{package_id: package.id, owner_id: owner.id}
          |> HexWeb.Repo.insert
          package
        end)

        {:ok, %{package | meta: meta}}
      errors ->
        {:error, errors_to_map(errors)}
    end
  end

  def update(package, meta) do
    meta = Dict.take(meta, @meta_fields)

    case validate(%{package | meta: meta}) do
      [] ->
        package = %{package | updated_at: Util.ecto_now, meta: Poison.encode!(meta)}
        HexWeb.Repo.update(package)
        {:ok, %{package | meta: meta}}
      errors ->
        {:error, errors_to_map(errors)}
    end
  end

  def get(name) do
    package =
      from(p in HexWeb.Package,
           where: p.name == ^name,
           limit: 1)
      |> HexWeb.Repo.one

    if package do
      %{package | meta: Poison.decode!(package.meta)}
    end
  end

  def delete(package) do
    package = %{package | meta: ""}
    HexWeb.Repo.transaction(fn ->
      HexWeb.Repo.delete_all(package.owners)
      HexWeb.Repo.delete(package)
    end)
  end

  def owners(package) do
    from(p in HexWeb.PackageOwner,
         where: p.package_id == ^package.id,
         join: u in HexWeb.User, on: u.id == p.owner_id,
         select: u)
    |> HexWeb.Repo.all
  end

  def owner?(package, user) do
    from(p in HexWeb.PackageOwner,
         where: p.package_id == ^package.id,
         where: p.owner_id == ^user.id,
         select: true)
    |> HexWeb.Repo.all
    |> Enum.any?
  end

  def add_owner(package, user) do
    %HexWeb.PackageOwner{package_id: package.id, owner_id: user.id}
    |> HexWeb.Repo.insert
  end

  def delete_owner(package, user) do
    from(p in HexWeb.PackageOwner,
         where: p.package_id == ^package.id,
         where: p.owner_id == ^user.id)
    |> HexWeb.Repo.delete_all
  end

  def all(page, count, search \\ nil) do
    from(p in HexWeb.Package,
         order_by: p.name)
    |> Util.paginate(page, count)
    |> search(search, true)
    |> HexWeb.Repo.all
    |> Enum.map(& %{&1 | meta: Poison.decode!(&1.meta)})
  end

  def recent(count) do
    from(p in HexWeb.Package,
        order_by: [desc: p.created_at],
        limit: count,
        select: {p.name, p.created_at})
    |> HexWeb.Repo.all
  end

  def recent_full(count) do
    from(p in HexWeb.Package,
         order_by: [desc: p.created_at],
         limit: count)
    |> HexWeb.Repo.all
    |> Enum.map(& %{&1 | meta: Poison.decode!(&1.meta)})
  end

  def count(search \\ nil) do
    from(p in HexWeb.Package, select: count(p.id))
    |> search(search, false)
    |> HexWeb.Repo.one!
  end

  def versions(package) do
    from(r in HexWeb.Release, where: r.package_id == ^package.id, select: r.version)
    |> HexWeb.Repo.all
  end

  def last_version(package_name) do
    from(r in HexWeb.Release,
          join: p in r.package,
         where: p.name == ^package_name,
      order_by: r.updated_at,
         limit: 1,
        select: r.version)
    |> HexWeb.Repo.one
  end

  def awesomeness(count, repo \\ "h4cc/awesome-elixir") do
    HexWeb.GithubApi.last_awesome_packages(repo, count)
      |> Enum.map(fn(package_name) ->
        version = __MODULE__.last_version(package_name)
        if version do
          {version, package_name}
        else
          nil
        end
      end)
      |> Enum.filter(fn(x) -> x end)
  end


  defp search(query, nil, _order?) do
    query
  end

  defp search(query, search, order?) do
    name_search = "%" <> like_escape(search, ~r"(%|_)") <> "%"
    desc_search = String.replace(search, ~r"\s+", " & ")

    query = from(var in query,
         where: ilike(var.name, ^name_search) or
                text_match(to_tsvector("english", json_access(var.meta, "description")),
                           to_tsquery("english", ^desc_search)))
    if order? do
      query = from(var in query, order_by: ilike(var.name, ^name_search))
    end

    query
  end

  defp like_escape(string, escape) do
    String.replace(string, escape, "\\\\\\1")
  end

  defp errors_to_map(errors) do
    if meta = errors[:meta] do
      errors = Dict.put(errors, :meta, Enum.into(meta, %{}))
    end
    Enum.into(errors, %{})
  end
end

defimpl HexWeb.Render, for: HexWeb.Package do
  import HexWeb.Util

  def render(package) do
    dict =
      HexWeb.Package.__schema__(:keywords, package)
      |> Dict.take([:name, :meta, :created_at, :updated_at])
      |> Dict.update!(:created_at, &to_iso8601/1)
      |> Dict.update!(:updated_at, &to_iso8601/1)
      |> Dict.put(:url, api_url(["packages", package.name]))
      |> Enum.into(%{})

    if package.releases.loaded? do
      releases =
        Enum.map(package.releases.all, fn release ->
          HexWeb.Release.__schema__(:keywords, release)
          |> Dict.take([:version, :created_at, :updated_at])
          |> Dict.update!(:created_at, &to_iso8601/1)
          |> Dict.update!(:updated_at, &to_iso8601/1)
          |> Dict.put(:url, api_url(["packages", package.name, "releases", release.version]))
          |> Enum.into(%{})
        end)
      dict = Dict.put(dict, :releases, releases)
    end

    if package.downloads.loaded? do
      downloads = Enum.into(package.downloads.all, %{})
      dict = Dict.put(dict, :downloads, downloads)
    end

    dict
  end
end
