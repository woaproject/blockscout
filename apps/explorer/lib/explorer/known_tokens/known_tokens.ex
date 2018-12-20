defmodule Explorer.KnownTokens do
  @moduledoc """
  Local cache for known tokens addresses.

  Data is updated every 1 hour.
  """

  use GenServer

  require Logger

  alias Explorer.Chain.Hash
  alias Explorer.KnownTokens.Source

  @interval :timer.hours(1)
  @table_name :known_tokens

  @impl GenServer
  def handle_info(:update, state) do
    Logger.debug(fn -> "Updating cached known tokens" end)

    fetch_known_tokens()

    {:noreply, state}
  end

  # Callback for successful fetch
  @impl GenServer
  def handle_info({_ref, {:ok, addresses}}, state) do
    if store() == :ets do
      records = Enum.map(addresses, fn x -> {x["symbol"], x["address"]} end)

      :ets.insert(table_name(), records)
    end

    broadcast_event(:known_token)

    {:noreply, state}
  end

  # Callback for errored fetch
  @impl GenServer
  def handle_info({_ref, {:error, reason}}, state) do
    Logger.warn(fn -> "Failed to get known tokens with reason '#{reason}'." end)

    fetch_known_tokens()

    {:noreply, state}
  end

  # Callback that a monitored process has shutdown
  @impl GenServer
  def handle_info({:DOWN, _, :process, _, _}, state) do
    {:noreply, state}
  end

  @impl GenServer
  def init(_) do
    send(self(), :update)
    :timer.send_interval(@interval, :update)

    table_opts = [
      :set,
      :named_table,
      :public,
      read_concurrency: true,
      write_concurrency: true
    ]

    if store() == :ets do
      :ets.new(table_name(), table_opts)
    end

    {:ok, %{}}
  end

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Lists known tokens.
  """
  @spec list :: [{String.t(), Hash.Address.t()}]
  def list do
    list_from_store(store())
  end

  @doc """
  Returns a specific address from the known tokens by symbol
  """
  @spec lookup(String.t()) :: Hash.Address.t() | nil
  def lookup(symbol) do
    if store() == :ets do
      case :ets.lookup(table_name(), symbol) do
        [{_symbol, address} | _] -> Hash.Address.cast(address)
        _ -> nil
      end
    end
  end

  @doc false
  @spec table_name() :: atom()
  def table_name do
    config(:table_name) || @table_name
  end

  @spec broadcast_event(atom()) :: :ok
  defp broadcast_event(event_type) do
    Registry.dispatch(Registry.ChainEvents, event_type, fn entries ->
      for {pid, _registered_val} <- entries do
        send(pid, {:chain_event, event_type})
      end
    end)
  end

  @spec config(atom()) :: term
  defp config(key) do
    Application.get_env(:explorer, __MODULE__, [])[key]
  end

  @spec fetch_known_tokens :: Task.t()
  defp fetch_known_tokens do
    Task.Supervisor.async_nolink(Explorer.MarketTaskSupervisor, fn ->
      Source.fetch_known_tokens()
    end)
  end

  defp list_from_store(:ets) do
    table_name()
    |> :ets.tab2list()
    |> Enum.map(&elem(&1, 1))
    |> Enum.map(&Hash.Address.cast/1)
    |> Enum.sort()
  end

  defp list_from_store(_), do: []

  defp store do
    config(:store) || :ets
  end
end
