defmodule Explorer.KnownTokens.Source do
  @moduledoc """
  Module for fetching list of known tokens.
  """

  alias Explorer.Chain.Hash
  alias HTTPoison.{Error, Response}

  @doc """
  Fetches known tokens
  """
  @spec fetch_known_tokens() :: {:ok, [Hash.Address.t()]} | {:error, any}
  def fetch_known_tokens() do
    case HTTPoison.get(source_url(), headers()) do
      {:ok, %Response{body: body, status_code: 200}} ->
        {:ok, decode_json(body)}

      {:ok, %Response{body: body, status_code: status_code}} when status_code in 400..499 ->
        {:error, decode_json(body)["error"]}

      {:error, %Error{reason: reason}} ->
        {:error, reason}
    end
  end

  @doc """
  Url for querying the list of known tokens.
  """
  @spec source_url() :: String.t()
  def source_url() do
    "https://raw.githubusercontent.com/kvhnuke/etherwallet/mercury/app/scripts/tokens/ethTokens.json"
  end

  def headers do
    [{"Content-Type", "application/json"}]
  end

  def decode_json(data) do
    Jason.decode!(data)
  end
end
