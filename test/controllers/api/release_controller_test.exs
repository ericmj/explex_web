defmodule HexWeb.API.ReleaseControllerTest do
  use HexWeb.ConnCase, async: true

  alias HexWeb.User
  alias HexWeb.Package
  alias HexWeb.Release
  alias HexWeb.RegistryBuilder

  setup do
    user = create_user("eric", "eric@mail.com", "ericeric")
    package = Package.build(user, pkg_meta(%{name: "decimal", description: "Arbitrary precision decimal aritmetic for Elixir."})) |> HexWeb.Repo.insert!
    release = Release.build(package, rel_meta(%{version: "0.0.1", app: "decimal"}), "") |> HexWeb.Repo.insert!
    %{user: user, package: package, release: release}
  end

  test "create release", c do
    meta = %{name: "ecto", version: "1.0.0", description: "Domain-specific language."}
    conn = build_conn()
           |> put_req_header("content-type", "application/octet-stream")
           |> put_req_header("authorization", key_for(c.user))
           |> post("api/packages/ecto/releases", create_tar(meta, []))

    assert conn.status == 201
    body = Poison.decode!(conn.resp_body)
    assert body["url"] =~ "api/packages/ecto/releases/1.0.0"

    user_id = c.user.id
    package = assert HexWeb.Repo.get_by(Package, name: "ecto")
    assert package.name == "ecto"
    assert [%User{id: ^user_id}] = assoc(package, :owners) |> HexWeb.Repo.all

    log = HexWeb.Repo.one!(HexWeb.AuditLog)
    assert log.actor_id == user_id
    assert log.action == "release.publish"
    assert %{"package" => %{"name" => "ecto"}, "release" => %{"version" => "1.0.0"}} = log.params
  end

  test "update package", c do
    meta = %{name: c.package.name, version: "1.0.0", description: "awesomeness"}
    conn = build_conn()
           |> put_req_header("content-type", "application/octet-stream")
           |> put_req_header("authorization", key_for(c.user))
           |> post("api/packages/#{c.package.name}/releases", create_tar(meta, []))

    assert conn.status == 201
    body = Poison.decode!(conn.resp_body)
    assert body["url"] =~ "/api/packages/#{c.package.name}/releases/1.0.0"

    assert HexWeb.Repo.get_by(Package, name: c.package.name).meta.description == "awesomeness"
  end

  test "create release authorizes" do
    body = create_tar(%{name: :postgrex, version: "0.0.1"}, [])
    conn = build_conn()
           |> put_req_header("content-type", "application/octet-stream")
           |> put_req_header("authorization", "wrong")
           |> post("api/packages/postgrex/releases", body)

    assert conn.status == 401
    assert get_resp_header(conn, "www-authenticate") == ["Basic realm=hex"]
  end

  test "update package authorizes" do
    meta = %{name: "ecto", version: "1.0.0", description: "Domain-specific language."}
    conn = build_conn()
           |> put_req_header("content-type", "application/octet-stream")
           |> put_req_header("authorization", "wrong")
           |> post("api/packages/ecto/releases", create_tar(meta, []))

    assert conn.status == 401
    assert get_resp_header(conn, "www-authenticate") == ["Basic realm=hex"]
  end

  test "create package validates", c do
    meta = %{name: "ecto", version: "1.0.0", links: "invalid", description: "description"}
    conn = build_conn()
           |> put_req_header("content-type", "application/octet-stream")
           |> put_req_header("authorization", key_for(c.user))
           |> post("api/packages/ecto/releases", create_tar(meta, []))

    assert conn.status == 422
    body = Poison.decode!(conn.resp_body)
    assert body["message"] == "Validation error(s)"
    assert body["errors"]["meta"]["links"] == "expected type map(string)"
  end

  test "create releases", c do
    body = create_tar(%{name: :postgrex, app: "not_postgrex", version: "0.0.1", description: "description"}, [])
    conn = build_conn()
           |> put_req_header("content-type", "application/octet-stream")
           |> put_req_header("authorization", key_for(c.user))
           |> post("api/packages/postgrex/releases", body)

    assert conn.status == 201
    body = Poison.decode!(conn.resp_body)
    assert body["meta"]["app"] == "not_postgrex"
    assert body["url"] =~ "/api/packages/postgrex/releases/0.0.1"

    body = create_tar(%{name: :postgrex, version: "0.0.2", description: "description"}, [])
    conn = build_conn()
           |> put_req_header("content-type", "application/octet-stream")
           |> put_req_header("authorization", key_for(c.user))
           |> post("api/packages/postgrex/releases", body)

    assert conn.status == 201
    postgrex = HexWeb.Repo.get_by!(Package, name: "postgrex")
    postgrex_id = postgrex.id

    assert [%Release{package_id: ^postgrex_id, version: %Version{major: 0, minor: 0, patch: 2}},
            %Release{package_id: ^postgrex_id, version: %Version{major: 0, minor: 0, patch: 1}}] =
           Release.all(postgrex) |> HexWeb.Repo.all |> Release.sort

    HexWeb.Repo.get_by!(assoc(postgrex, :releases), version: "0.0.1")
  end

  test "create release also creates package", c do
    refute HexWeb.Repo.get_by(Package, name: "phoenix")

    body = create_tar(%{name: :phoenix, app: "phoenix", description: "Web framework", version: "1.0.0"}, [])
    conn = build_conn()
           |> put_req_header("content-type", "application/octet-stream")
           |> put_req_header("authorization", key_for(c.user))
           |> post("api/packages/phoenix/releases", body)

    assert conn.status == 201
    assert %Package{name: "phoenix"} = HexWeb.Repo.get_by(Package, name: "phoenix")
  end

  test "update release", c do
    body = create_tar(%{name: :postgrex, version: "0.0.1", description: "description"}, [])
    conn = build_conn()
           |> put_req_header("content-type", "application/octet-stream")
           |> put_req_header("authorization", key_for(c.user))
           |> post("api/packages/postgrex/releases", body)

    assert conn.status == 201

    conn = build_conn()
           |> put_req_header("content-type", "application/octet-stream")
           |> put_req_header("authorization", key_for(c.user))
           |> post("api/packages/postgrex/releases", body)

    assert conn.status == 200
    postgrex = HexWeb.Repo.get_by!(Package, name: "postgrex")
    release = HexWeb.Repo.get_by!(assoc(postgrex, :releases), version: "0.0.1")
    assert [%HexWeb.AuditLog{action: "release.publish"}, %HexWeb.AuditLog{action: "release.publish"}] =
           HexWeb.Repo.all(HexWeb.AuditLog)

    Ecto.Changeset.change(release, inserted_at: %{NaiveDateTime.utc_now | year: 2000})
    |> HexWeb.Repo.update!

    conn = build_conn()
           |> put_req_header("content-type", "application/octet-stream")
           |> put_req_header("authorization", key_for("eric"))
           |> post("api/packages/postgrex/releases", body)

    assert conn.status == 422
    assert %{"errors" => %{"inserted_at" => "can only modify a release up to one hour after creation"}} =
           Poison.decode!(conn.resp_body)
  end

  @tag isolation: :serializable
  test "delete release", c do
    body = create_tar(%{name: :postgrex, version: "0.0.1", description: "description"}, [])
    conn = build_conn()
           |> put_req_header("content-type", "application/octet-stream")
           |> put_req_header("authorization", key_for(c.user))
           |> post("api/packages/postgrex/releases", body)

    assert conn.status == 201
    package = HexWeb.Repo.get_by!(Package, name: "postgrex")
    release = HexWeb.Repo.get_by!(assoc(package, :releases), version: "0.0.1")
    Ecto.Changeset.change(release, inserted_at: %{NaiveDateTime.utc_now | year: 2000})
    |> HexWeb.Repo.update!

    conn = build_conn()
           |> put_req_header("content-type", "application/octet-stream")
           |> put_req_header("authorization", key_for(c.user))
           |> delete("api/packages/postgrex/releases/0.0.1")

    assert conn.status == 422
    assert %{"errors" => %{"inserted_at" => "can only delete a release up to one hour after creation"}} =
           Poison.decode!(conn.resp_body)

    Ecto.Changeset.change(release, inserted_at: %{NaiveDateTime.utc_now | year: 2030})
    |> HexWeb.Repo.update!

    conn = build_conn()
           |> put_req_header("content-type", "application/octet-stream")
           |> put_req_header("authorization", key_for(c.user))
           |> delete("api/packages/postgrex/releases/0.0.1")

    assert conn.status == 204
    refute HexWeb.Repo.get_by(Package, name: "postgrex")
    refute HexWeb.Repo.get_by(assoc(package, :releases), version: "0.0.1")

    [_, log] = HexWeb.Repo.all(HexWeb.AuditLog)
    assert log.actor_id == c.user.id
    assert log.action == "release.revert"
    assert %{"package" => %{"name" => "postgrex"}, "release" => %{"version" => "0.0.1"}} = log.params
  end

  test "create releases with requirements", c do
    reqs = [%{name: "decimal", requirement: "~> 0.0.1", app: "not_decimal", optional: false}]
    body = create_tar(%{name: :postgrex, version: "0.0.1", requirements: reqs, description: "description"}, [])
    conn = build_conn()
           |> put_req_header("content-type", "application/octet-stream")
           |> put_req_header("authorization", key_for(c.user))
           |> post("api/packages/postgrex/releases", body)

    assert conn.status == 201
    body = Poison.decode!(conn.resp_body)
    assert body["requirements"] == %{"decimal" => %{"app" => "not_decimal", "optional" => false, "requirement" => "~> 0.0.1"}}

    release = HexWeb.Repo.get_by(Package, name: "postgrex")
              |> assoc(:releases)
              |> HexWeb.Repo.get_by!(version: "0.0.1")
              |> HexWeb.Repo.preload(:requirements)

    assert [%{app: "not_decimal", requirement: "~> 0.0.1", optional: false}] =
           release.requirements
  end

  test "create releases with requirements validates", c do
    # invalid requirement
    reqs = [%{name: "decimal", requirement: "~> invalid", app: "not_decimal", optional: false}]
    body = create_tar(%{name: :postgrex, version: "0.0.1", requirements: reqs, description: "description"}, [])
    conn = build_conn()
           |> put_req_header("content-type", "application/octet-stream")
           |> put_req_header("authorization", key_for(c.user))
           |> post("api/packages/postgrex/releases", body)

    assert conn.status == 422
    body = Poison.decode!(conn.resp_body)
    assert body["message"] == "Validation error(s)"
    assert %{"requirements" => %{"decimal" => "invalid requirement: \"~> invalid\""}} = body["errors"]

    # invalid package
    reqs = [%{name: "not_decimal", requirement: "~> 1.0", app: "not_decimal", optional: false}]
    body = create_tar(%{name: :postgrex, version: "0.0.1", requirements: reqs, description: "description"}, [])
    conn = build_conn()
           |> put_req_header("content-type", "application/octet-stream")
           |> put_req_header("authorization", key_for(c.user))
           |> post("api/packages/postgrex/releases", body)

    assert conn.status == 422
    body = Poison.decode!(conn.resp_body)
    assert body["message"] == "Validation error(s)"
    assert %{"requirements" => %{"not_decimal" => "package does not exist"}} = body["errors"]

    # conflict
    reqs = [%{name: "decimal", requirement: "~> 1.0", app: "not_decimal", optional: false}]
    body = create_tar(%{name: :postgrex, version: "0.1.0", requirements: reqs, description: "description"}, [])
    conn = build_conn()
           |> put_req_header("content-type", "application/octet-stream")
           |> put_req_header("authorization", key_for(c.user))
           |> post("api/packages/postgrex/releases", body)

    assert conn.status == 422
    body = Poison.decode!(conn.resp_body)
    assert body["message"] == "Validation error(s)"
    assert %{"requirements" => %{"decimal" => "Failed to use \"decimal\" because\n  mix.exs specifies ~> 1.0\n"}} = body["errors"]
  end

  test "create release updates registry", c do
    RegistryBuilder.full_build
    registry_before = HexWeb.Store.get(nil, :s3_bucket, "registry.ets.gz", [])

    reqs = [%{name: c.package.name, app: c.package.name, requirement: "~> 0.0.1", optional: false}]
    body = create_tar(%{name: :postgrex, app: :postgrex, version: "0.0.1", requirements: reqs, description: "description"}, [])
    conn = build_conn()
           |> put_req_header("content-type", "application/octet-stream")
           |> put_req_header("authorization", key_for(c.user))
           |> post("api/packages/postgrex/releases", body)

    assert conn.status == 201

    registry_after = HexWeb.Store.get(nil, :s3_bucket, "registry.ets.gz", [])
    assert registry_before != registry_after
  end

  test "get release", c do
    conn = get build_conn(), "api/packages/#{c.package.name}/releases/#{c.release.version}"

    assert conn.status == 200
    body = Poison.decode!(conn.resp_body)
    assert body["url"] =~ "/api/packages/#{c.package.name}/releases/#{c.release.version}"
    assert body["version"] == "#{c.release.version}"
  end

  test "get unknown release", c do
    conn = get build_conn(), "api/packages/#{c.package.name}/releases/1.2.3"
    assert conn.status == 404

    conn = get build_conn(), "api/packages/unknown/releases/1.2.3"
    assert conn.status == 404
  end
end
