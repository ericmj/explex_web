defmodule HexWeb.Web.RouterTest do
  use HexWebTest.Case
  import Plug.Test
  alias HexWeb.Router
  alias HexWeb.Package
  alias HexWeb.Release
  alias HexWeb.User
  alias HexWeb.PackageOwner

  defp release_create(package, version, app, requirements, checksum, inserted_at) do
    {:ok, release} = Release.create(package, rel_meta(%{version: version, app: app, requirements: requirements}), checksum)
    %{release | inserted_at: inserted_at}
    |> HexWeb.Repo.update
  end

  setup do
    first_date  = Ecto.DateTime.from_erl({{2014, 5, 1}, {10, 11, 12}})
    second_date = Ecto.DateTime.from_erl({{2014, 5, 2}, {10, 11, 12}})
    last_date   = Ecto.DateTime.from_erl({{2014, 5, 3}, {10, 11, 12}})

    foo = HexWeb.Repo.insert(%Package{name: "foo", inserted_at: first_date, updated_at: first_date})
    bar = HexWeb.Repo.insert(%Package{name: "bar", inserted_at: second_date, updated_at: second_date})
    other = HexWeb.Repo.insert(%Package{name: "other", inserted_at: last_date, updated_at: last_date})

    release_create(foo, "0.0.1", "foo", [], "", Ecto.DateTime.from_erl({{2014, 5, 3}, {10, 11, 1}}))
    release_create(foo, "0.0.2", "foo", [], "", Ecto.DateTime.from_erl({{2014, 5, 3}, {10, 11, 2}}))
    release_create(foo, "0.1.0", "foo", [], "", Ecto.DateTime.from_erl({{2014, 5, 3}, {10, 11, 3}}))
    release_create(bar, "0.0.1", "bar", [], "", Ecto.DateTime.from_erl({{2014, 5, 3}, {10, 11, 4}}))
    release_create(bar, "0.0.2", "bar", [], "", Ecto.DateTime.from_erl({{2014, 5, 3}, {10, 11, 5}}))
    release_create(other, "0.0.1", "other", [], "", Ecto.DateTime.from_erl({{2014, 5, 3}, {10, 11, 6}}))
    :ok
  end

  test "front page" do
    path     = Path.join([__DIR__, "..", "..", "fixtures"])
    logfile1 = File.read!(Path.join(path, "s3_logs_1.txt"))
    logfile2 = File.read!(Path.join(path, "s3_logs_2.txt"))
    store    = Application.get_env(:hex_web, :store)

    store.put_logs("hex/2013-11-01-21-32-16-E568B2907131C0C0", logfile1)
    store.put_logs("hex/2013-11-01-21-32-19-E568B2907131C0C0", logfile2)
    HexWeb.Stats.Job.run({2013, 11, 1})

    conn = conn(:get, "/")
    conn = Router.call(conn, [])

    assert conn.status == 200
    assert conn.assigns[:total][:all] == 9
    assert conn.assigns[:total][:week] == 0
    assert conn.assigns[:package_top] == [{"foo", 7}, {"bar", 2}]
    assert conn.assigns[:num_packages] == 3
    assert conn.assigns[:num_releases] == 6
    assert Enum.count(conn.assigns[:releases_new]) == 6
    assert Enum.count(conn.assigns[:package_new]) == 3
  end

  test "user page" do
    {:ok, joe} = User.create(%{username: "joe", email: "joe@example.com", password: "joe"}, true)
    HexWeb.Repo.insert(%PackageOwner{package_id: Package.get("foo").id, owner_id: joe.id})
    HexWeb.Repo.insert(%PackageOwner{package_id: Package.get("bar").id, owner_id: joe.id})

    conn = conn(:get, "/users/#{joe.id}")
    conn = Router.call(conn, [])

    assert conn.status == 200
    assert conn.assigns[:user].username == "joe"
    assert Enum.count(conn.assigns[:packages]) == 2
  end
end
