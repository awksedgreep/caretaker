defmodule Caretaker.HTTP.Auth do
  @moduledoc """
  HTTP Basic and Digest (RFC 7616, MD5) authentication helpers for the CPE
  client. ACSes commonly challenge the CPE with Digest authentication.
  """

  @type credentials :: %{username: String.t(), password: String.t()}

  @doc """
  Build an `authorization` header value for the given challenge.

  `challenge` is the value of the `www-authenticate` response header.
  Returns `nil` when the scheme is not supported.
  """
  @spec authorization(String.t(), credentials(), atom(), String.t()) :: String.t() | nil
  def authorization(challenge, %{username: user, password: pass}, method, uri) do
    {scheme, params} = parse_challenge(challenge)

    case String.downcase(scheme) do
      "basic" ->
        basic(user, pass)

      "digest" ->
        digest(params, user, pass, method, uri)

      _ ->
        nil
    end
  end

  @doc "Build a Basic authorization value."
  @spec basic(String.t(), String.t()) :: String.t()
  def basic(user, pass), do: "Basic " <> Base.encode64(user <> ":" <> pass)

  @doc "Parse a `www-authenticate` value into `{scheme, params}`."
  @spec parse_challenge(String.t()) :: {String.t(), map()}
  def parse_challenge(challenge) do
    case String.split(String.trim(challenge), ~r/\s+/, parts: 2) do
      [scheme] ->
        {scheme, %{}}

      [scheme, rest] ->
        params =
          ~r/(\w+)=(?:"([^"]*)"|([^,\s]*))/
          |> Regex.scan(rest)
          |> Map.new(fn
            [_, k, quoted, ""] -> {String.downcase(k), quoted}
            [_, k, quoted] -> {String.downcase(k), quoted}
            [_, k, _, bare] -> {String.downcase(k), bare}
          end)

        {scheme, params}
    end
  end

  defp digest(params, user, pass, method, uri) do
    realm = Map.get(params, "realm", "")
    nonce = Map.get(params, "nonce", "")
    opaque = Map.get(params, "opaque")
    algorithm = Map.get(params, "algorithm", "MD5")
    qop = params |> Map.get("qop", "") |> String.split(",", trim: true) |> Enum.map(&String.trim/1)
    method_str = method |> to_string() |> String.upcase()

    cnonce = Base.encode16(:crypto.strong_rand_bytes(8), case: :lower)
    nc = "00000001"

    ha1 =
      case String.upcase(algorithm) do
        "MD5-SESS" -> md5([md5([user, realm, pass]), nonce, cnonce])
        _ -> md5([user, realm, pass])
      end

    ha2 = md5([method_str, uri])

    {response, qop_fields} =
      if "auth" in qop do
        {md5([ha1, nonce, nc, cnonce, "auth", ha2]),
         [{"qop", "auth", false}, {"nc", nc, false}, {"cnonce", cnonce, true}]}
      else
        {md5([ha1, nonce, ha2]), []}
      end

    fields =
      [
        {"username", user, true},
        {"realm", realm, true},
        {"nonce", nonce, true},
        {"uri", uri, true},
        {"response", response, true},
        {"algorithm", algorithm, false}
      ] ++
        qop_fields ++
        if(opaque, do: [{"opaque", opaque, true}], else: [])

    "Digest " <>
      Enum.map_join(fields, ", ", fn
        {k, v, true} -> ~s(#{k}="#{v}")
        {k, v, false} -> "#{k}=#{v}"
      end)
  end

  defp md5(parts) do
    :crypto.hash(:md5, Enum.join(parts, ":")) |> Base.encode16(case: :lower)
  end
end
