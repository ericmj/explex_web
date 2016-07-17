defmodule HexWeb.ControllerHelpers do
  import Plug.Conn
  import Phoenix.Controller
  import Ecto

  @max_cache_age 60

  def cache(conn, control, vary) do
    conn
    |> maybe_put_resp_header("cache-control", parse_control(control))
    |> maybe_put_resp_header("vary", parse_vary(vary))
  end

  def api_cache(conn, privacy) do
    control = [privacy] ++ ["max-age": @max_cache_age]
    vary    = ["accept", "accept-encoding"]
    cache(conn, control, vary)
  end

  defp parse_vary(nil),  do: nil
  defp parse_vary(vary), do: Enum.map_join(vary, ", ", &"#{&1}")

  defp parse_control(nil), do: nil
  defp parse_control(control) do
    Enum.map_join(control, ", ", fn
      atom when is_atom(atom) -> "#{atom}"
      {key, value}          -> "#{key}=#{value}"
    end)
  end

  defp maybe_put_resp_header(conn, _header, nil),
    do: conn
  defp maybe_put_resp_header(conn, header, value),
    do: put_resp_header(conn, header, value)

  def render_error(conn, status, assigns \\ []) do
    conn
    |> put_status(status)
    |> put_layout(false)
    |> render(HexWeb.ErrorView, :"#{status}", assigns)
    |> halt
  end

  def validation_failed(conn, %Ecto.Changeset{} = changeset) do
    errors =
      Ecto.Changeset.traverse_errors(changeset, fn
        {"is invalid", [type: type]} ->
          "expected type #{pretty_type(type)}"
        {err, _} ->
          err
      end)
      |> normalize_errors

    render_error(conn, 422, errors: errors)
  end
  def validation_failed(conn, errors) do
    render_error(conn, 422, errors: errors_to_map(errors))
  end

  defp pretty_type({:array, type}),
    do: "list(#{pretty_type(type)})"
  defp pretty_type({:map, type}),
    do: "map(#{pretty_type(type)})"
  defp pretty_type(type),
    do: to_string(type)

  # TODO: remove when requirements are handled with cast_assoc
  defp errors_to_map(errors) when is_list(errors) do
    Enum.into(errors, %{}, fn {key, value} -> {key, errors_to_map(value)} end)
  end
  defp errors_to_map(other), do: other

  # TODO: Fix clients instead
  # Since Changeset.traverse_errors returns `{field: [err], ...}`
  # but Hex client expects `{field1: err1, ...}` we normalize to the latter.
  defp normalize_errors(errors) do
    Enum.flat_map(errors, fn
      {_key, val}     when val == %{}  -> []
      {_key, [val|_]} when val == %{}  -> []
      {_key, []}                       -> []
      {key, val}      when is_map(val) -> [{key, normalize_errors(val)}]
      {key, [val|_]}  when is_map(val) -> [{key, normalize_errors(val)}]
      {key, [val|_]}                   -> [{key, val}]
    end)
    |> Enum.into(%{})
  end

  def not_found(conn) do
    render_error(conn, 404)
  end

  def when_stale(conn, entities, opts \\ [], fun) do
    etag = etag(entities)
    modified = if Keyword.get(opts, :modified, true), do: last_modified(entities)

    conn =
      conn
      |> put_etag(etag)
      |> put_last_modified(modified)

    if fresh?(conn, etag: etag, modified: modified) do
      send_resp(conn, 304, "")
    else
      fun.(conn)
    end
  end

  defp put_etag(conn, nil),
    do: conn
  defp put_etag(conn, etag),
    do: put_resp_header(conn, "etag", etag)

  defp put_last_modified(conn, nil),
    do: conn
  defp put_last_modified(conn, modified),
    do: put_resp_header(conn, "last-modified", :cowboy_clock.rfc1123(modified))

  defp fresh?(conn, opts) do
    not expired?(conn, opts)
  end

  defp expired?(conn, opts) do
    modified_since = List.first get_req_header(conn, "if-modified-since")
    none_match     = List.first get_req_header(conn, "if-none-match")

    if modified_since || none_match do
      modified_since?(modified_since, opts[:modified]) or
        none_match?(none_match, opts[:etag])
    else
      true
    end
  end

  defp modified_since?(header, last_modified) do
    if header && last_modified do
      modified_since = :cowboy_http.rfc1123_date(header)
      modified_since = :calendar.datetime_to_gregorian_seconds(modified_since)
      last_modified  = :calendar.datetime_to_gregorian_seconds(last_modified)
      last_modified > modified_since
    else
      false
    end
  end

  defp none_match?(none_match, etag) do
    if none_match && etag do
      none_match = Plug.Conn.Utils.list(none_match)
      not(etag in none_match) and not("*" in none_match)
    else
      false
    end
  end

  defp etag(nil), do: nil
  defp etag([]),  do: nil
  defp etag(models) do
    list = Enum.map(List.wrap(models), fn model ->
      [model.__struct__, model.id, model.updated_at]
    end)

    binary = :erlang.term_to_binary(list)
    :crypto.hash(:md5, binary)
    |> Base.encode16(case: :lower)
  end

  def last_modified(nil), do: nil
  def last_modified([]),  do: nil
  def last_modified(models) do
    Enum.map(List.wrap(models), fn model ->
      Ecto.DateTime.to_erl(model.updated_at)
    end)
    |> Enum.max
  end

  def maybe_fetch_package(conn, _opts) do
    if package = HexWeb.Repo.get_by(HexWeb.Package, name: conn.params["name"]) do
      assign(conn, :package, package)
    else
      conn
    end
  end

  def fetch_package(conn, _opts) do
    package = HexWeb.Repo.get_by!(HexWeb.Package, name: conn.params["name"])
    assign(conn, :package, package)
  end

  def fetch_release(conn, _opts) do
    package = HexWeb.Repo.get_by!(HexWeb.Package, name: conn.params["name"])
    release = HexWeb.Repo.get_by!(assoc(package, :releases), version: conn.params["version"])
    release = %{release | package: package}

    conn
    |> assign(:package, package)
    |> assign(:release, release)
  end

  def authorize(conn, opts) do
    fun = Keyword.get(opts, :fun, fn _, _ -> true end)
    HexWeb.AuthHelpers.authorized(conn, opts, &fun.(conn, &1))
  end

  def audit_data(conn) do
    {conn.assigns.user, conn.assigns.user_agent}
  end

  # TODO: remove once auditing is moved out of all controllers
  def audit(multi, conn, action, fun) when is_function(fun, 1) do
    Ecto.Multi.merge(multi, fn data ->
      Ecto.Multi.insert(Ecto.Multi.new, :log, audit(conn, action, fun.(data)))
    end)
  end
  def audit(multi, conn, action, params) do
    Ecto.Multi.insert(multi, :log, audit(conn, action, params))
  end
  def audit(conn, action, params) do
    user = conn.assigns.user
    user_agent = conn.assigns.user_agent
    do_audit(user, user_agent, action, params)
  end

  defp do_audit(user, user_agent, action, params) do
    Ecto.Changeset.change(HexWeb.AuditLog.build(user, user_agent, action, params), %{})
  end

  def audit_many(multi, conn, action, list, opts \\ []) do
    fields = HexWeb.AuditLog.__schema__(:fields) -- [:id]
    extra = %{inserted_at: Ecto.DateTime.utc}
    entry = fn (element) ->
      conn
      |> audit(action, element)
      |> Ecto.Changeset.apply_changes()
      |> Map.take(fields)
      |> Map.merge(extra)
    end
    Ecto.Multi.insert_all(multi, :log, HexWeb.AuditLog, Enum.map(list, entry), opts)
  end
end
