defmodule Hexpm.Web.API.UserController do
  use Hexpm.Web, :controller

  plug :authorize, [domain: "api"] when action in [:test]
  plug :authorize, [domain: "api"] when action in [:me]

  def create(conn, params) do
    params = email_param(params)

    case Users.add(params, audit: audit_data(conn)) do
      {:ok, user} ->
        location = Routes.api_user_url(conn, :show, user.username)

        conn
        |> put_resp_header("location", location)
        |> api_cache(:private)
        |> put_status(201)
        |> render(:show, user: user)
      {:error, changeset} ->
        validation_failed(conn, changeset)
    end
  end

  def me(conn, _params) do
    user = Users.put_repositories(conn.assigns.current_user)

    when_stale(conn, user, fn conn ->
      conn
      |> api_cache(:private)
      |> render(:show, user: user)
    end)
  end

  def show(conn, %{"name" => username}) do
    user = Users.get(username, [:owned_packages, :emails])
    user = filter_packages(user)

    if user do
      when_stale(conn, user, fn conn ->
        conn
        |> api_cache(:private)
        |> render(:show, user: user)
      end)
    else
      not_found(conn)
    end
  end

  # TODO: enable other repository users to see private packages
  # TODO: add tests
  defp filter_packages(nil), do: nil
  defp filter_packages(user) do
    %{user | owned_packages: Enum.filter(user.owned_packages, & &1.repository_id == 1)}
  end

  def test(conn, params) do
    show(conn, params)
  end

  def reset(conn, %{"name" => name}) do
    Users.password_reset_init(name, audit: audit_data(conn))

    conn
    |> api_cache(:private)
    |> send_resp(204, "")
  end

  defp email_param(params) do
    if email = params["email"] do
      Map.put_new(params, "emails", [%{"email" => email}])
    else
      params
    end
  end
end
