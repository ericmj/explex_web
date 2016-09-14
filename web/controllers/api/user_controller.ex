defmodule HexWeb.API.UserController do
  use HexWeb.Web, :controller

  plug :authorize, [fun: &correct_user?/2] when action == :show

  def create(conn, params) do
    case Users.add(params) do
      {:ok, user} ->
        location = user_url(conn, :show, user.username)

        conn
        |> put_resp_header("location", location)
        |> api_cache(:private)
        |> put_status(201)
        |> render(:show, user: user)
      {:error, changeset} ->
        validation_failed(conn, changeset)
    end
  end

  def show(conn, _params) do
    user = Users.with_owned_packages(conn.assigns.user)

    when_stale(conn, user, fn conn ->
      conn
      |> api_cache(:private)
      |> render(:show, user: user)
    end)
  end

  def reset(conn, %{"name" => name}) do
    case Users.reset(name) do
      :ok ->
        conn
        |> api_cache(:private)
        |> send_resp(204, "")
      {:error, :not_found} ->
        not_found(conn)
    end
  end
end
