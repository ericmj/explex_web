defmodule Hexpm.Application do
  use Application

  def start(_type, _args) do
    import Supervisor.Spec, warn: false

    topologies = cluster_topologies()
    read_only_mode()
    Hexpm.BlockAddress.start()

    children = [
      supervisor(Hexpm.RepoBase, []),
      supervisor(Task.Supervisor, [[name: Hexpm.Tasks]]),
      supervisor(Cluster.Supervisor, [[topologies, [name: Hexpm.ClusterSupervisor]]]),
      supervisor(Phoenix.PubSub.PG2, [[name: Hexpm.PubSub]]),
      worker(HexpmWeb.RateLimitPubSub, []),
      worker(PlugAttack.Storage.Ets, [HexpmWeb.Plugs.Attack, [clean_period: 60_000]]),
      worker(Hexpm.Throttle, [[name: Hexpm.SESThrottle, rate: ses_rate(), unit: 1000]]),
      worker(Hexpm.Billing.Report, [[name: Hexpm.Billing.Report, interval: 60_000]]),
      supervisor(HexpmWeb.Endpoint, [])
    ]

    File.mkdir_p(Application.get_env(:hexpm, :tmp_dir))
    shutdown_on_eof()

    opts = [strategy: :one_for_one, name: Hexpm.Supervisor]
    Supervisor.start_link(children, opts)
  end

  def config_change(changed, _new, removed) do
    HexpmWeb.Endpoint.config_change(changed, removed)
    :ok
  end

  def ses_rate() do
    if rate = Application.get_env(:hexpm, :ses_rate) do
      String.to_integer(rate)
    else
      :infinity
    end
  end

  # Make sure we exit after hex client tests are finished running
  if Mix.env() == :hex do
    def shutdown_on_eof() do
      spawn_link(fn ->
        IO.gets(:stdio, '') == :eof && System.halt(0)
      end)
    end
  else
    def shutdown_on_eof(), do: nil
  end

  defp read_only_mode() do
    mode = System.get_env("HEXPM_READ_ONLY_MODE") == "1"
    Application.put_env(:hexpm, :read_only_mode, mode)
  end

  defp cluster_topologies() do
    if System.get_env("HEXPM_CLUSTER") == "1" do
      Application.get_env(:hexpm, :topologies) || []
    else
      []
    end
  end
end
