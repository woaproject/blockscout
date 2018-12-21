defmodule Explorer.Market do
  @moduledoc """
  Context for data related to the cryptocurrency market.
  """

  import Ecto.Query

  alias Explorer.{ExchangeRates, KnownTokens, Repo}
  alias Explorer.Chain.Hash
  alias Explorer.Chain.Address.CurrentTokenBalance
  alias Explorer.ExchangeRates.Token
  alias Explorer.Market.MarketHistory

  @doc """
  Get most recent exchange rate for the given symbol.
  """
  @spec get_exchange_rate(String.t()) :: Token.t() | nil
  def get_exchange_rate(symbol) do
    ExchangeRates.lookup(symbol)
  end

  @doc """
  Get the address of the token with the given symbol.
  """
  @spec get_known_address(String.t()) :: Hash.Address.t() | nil
  def get_known_address(symbol) do
    case KnownTokens.lookup(symbol) do
      {:ok, address} -> address
      nil -> nil
    end
  end

  @doc """
  Retrieves the history for the recent specified amount of days.

  Today's date is include as part of the day count
  """
  @spec fetch_recent_history(non_neg_integer()) :: [MarketHistory.t()]
  def fetch_recent_history(days) when days >= 1 do
    day_diff = days * -1

    query =
      from(
        mh in MarketHistory,
        where: mh.date > date_add(^Date.utc_today(), ^day_diff, "day"),
        order_by: [desc: mh.date]
      )

    Repo.all(query)
  end

  @doc false
  def bulk_insert_history(records) do
    Repo.insert_all(MarketHistory, records, on_conflict: :replace_all, conflict_target: [:date])
  end

  def add_price(%{symbol: symbol} = token) do
    known_address = get_known_address(symbol)

    matches_known_address = known_address && known_address == token.contract_address_hash

    usd_value =
      if matches_known_address do
        case get_exchange_rate(symbol) do
          %{usd_value: usd_value} -> usd_value
          nil -> nil
        end
      else
        nil
      end

    Map.put(token, :usd_value, usd_value)
  end

  def add_price(%CurrentTokenBalance{token: token} = token_balance) do
    token_with_price = add_price(token)

    Map.put(token_balance, :token, token_with_price)
  end

  def add_price(tokens) when is_list(tokens) do
    Enum.map(tokens, &add_price/1)
  end
end
