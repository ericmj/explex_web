defmodule HexpmWeb.API.PackageController do
  use HexpmWeb, :controller

  plug :fetch_repository when action in [:index]
  plug :maybe_fetch_package when action in [:show]

  plug :maybe_authorize,
       [domain: "api", resource: "read", fun: &maybe_repository_access/2]
       when action in [:index]

  plug :maybe_authorize,
       [domain: "api", resource: "read", fun: &repository_access/2]
       when action in [:show]

  @sort_params ~w(name recent_downloads total_downloads inserted_at updated_at)

  def index(conn, params) do
    repositories = repositories(conn)
    page = Hexpm.Utils.safe_int(params["page"])
    search = Hexpm.Utils.parse_search(params["search"])
    sort = sort(params["sort"])
    packages = Packages.search_with_versions(repositories, page, 100, search, sort)

    when_stale(conn, packages, [modified: false], fn conn ->
      conn
      |> api_cache(:public)
      |> render(:index, packages: packages)
    end)
  end

  def show(conn, _params) do
    if package = conn.assigns.package do
      when_stale(conn, package, fn conn ->
        package = Packages.preload(package)
        owners = Enum.map(Owners.all(package, user: :emails), & &1.user)
        package = %{package | owners: owners}

        conn
        |> api_cache(:public)
        |> render(:show, package: package)
      end)
    else
      not_found(conn)
    end
  end

  defp sort(nil), do: sort("name")
  defp sort("downloads"), do: sort("total_downloads")
  defp sort(param), do: Hexpm.Utils.safe_to_atom(param, @sort_params)

  defp repositories(conn) do
    cond do
      repository = conn.assigns.repository ->
        [repository]

      user = conn.assigns.current_user ->
        Enum.map(Users.all_organizations(user), & &1.repository)

      organization = conn.assigns.current_organization ->
        [Repository.hexpm(), organization.repository]

      true ->
        [Repository.hexpm()]
    end
  end
end
