defmodule Caretaker.ACS.Auth do
  @moduledoc """
  Inbound HTTP authentication for `Caretaker.ACS.Server`.

  Supports HTTP Basic and Digest (RFC 7616, MD5 / MD5-sess, `qop=auth`).
  Configured at mount time:

      {Bandit, plug: {Caretaker.ACS.Server,
        auth: %{scheme: :digest, realm: "acs", username: "u", password: "p"}}}

  For fleets that provision unique per-device credentials, pass a lookup
  function instead of a fixed username/password:

      auth: %{scheme: :digest, realm: "acs",
              lookup: fn username -> {:ok, password} | :error end}

  Digest nonces are stateless: each carries an issue timestamp and an HMAC over
  it, so validity and freshness are checked without server-side nonce storage.
  """

  @type config :: %{
          required(:scheme) => :basic | :digest,
          optional(:realm) => String.t(),
          optional(:username) => String.t(),
          optional(:password) => String.t(),
          optional(:lookup) => (String.t() -> {:ok, String.t()} | :error),
          optional(:nonce_secret) => binary(),
          optional(:nonce_max_age_ms) => non_neg_integer()
        }

  @default_realm "caretaker-acs"
  @default_max_age_ms 300_000

  @doc "Attach a per-server random nonce secret to the auth config (call once at mount)."
  @spec prepare(config()) :: config()
  def prepare(%{} = config) do
    Map.put_new_lazy(config, :nonce_secret, fn -> :crypto.strong_rand_bytes(32) end)
  end

  def prepare(other), do: other

  @doc "The `www-authenticate` header value for a 401 challenge."
  @spec challenge(config()) :: String.t()
  def challenge(%{scheme: :basic} = c), do: ~s(Basic realm="#{realm(c)}")

  def challenge(%{scheme: :digest} = c) do
    nonce = make_nonce(c)
    ~s(Digest realm="#{realm(c)}", qop="auth", nonce="#{nonce}", algorithm=MD5)
  end

  @doc """
  Verify an `authorization` header value against the config for the given HTTP
  method and request URI. Returns `true` when authentication succeeds.
  """
  @spec verify(String.t() | nil, String.t(), String.t(), config()) :: boolean()
  def verify(nil, _method, _uri, _config), do: false

  def verify(header, _method, _uri, %{scheme: :basic} = config) do
    case String.split(String.trim(header), " ", parts: 2) do
      [scheme, encoded] ->
        with true <- String.downcase(scheme) == "basic",
             {:ok, decoded} <- Base.decode64(encoded),
             [user, pass] <- String.split(decoded, ":", parts: 2),
             {:ok, expected} <- password_for(config, user) do
          Plug.Crypto.secure_compare(pass, expected)
        else
          _ -> false
        end

      _ ->
        false
    end
  end

  def verify(header, method, uri, %{scheme: :digest} = config) do
    case parse_digest(header) do
      {:ok, params} -> verify_digest(params, method, uri, config)
      :error -> false
    end
  end

  def verify(_header, _method, _uri, _config), do: false

  # -- digest --

  defp verify_digest(p, method, uri, config) do
    with {:ok, expected} <- password_for(config, p["username"]),
         true <- valid_nonce?(p["nonce"], config),
         true <- p["realm"] == realm(config) do
      ha1 = ha1(p, p["username"], expected, config)
      ha2 = md5([String.upcase(method), p["uri"] || uri])

      computed =
        case p["qop"] do
          "auth" -> md5([ha1, p["nonce"], p["nc"], p["cnonce"], "auth", ha2])
          _ -> md5([ha1, p["nonce"], ha2])
        end

      Plug.Crypto.secure_compare(computed, p["response"] || "")
    else
      _ -> false
    end
  end

  defp ha1(p, user, pass, config) do
    base = md5([user, realm(config), pass])

    case String.downcase(p["algorithm"] || "md5") do
      "md5-sess" -> md5([base, p["nonce"], p["cnonce"]])
      _ -> base
    end
  end

  defp parse_digest(header) do
    case String.split(String.trim(header), " ", parts: 2) do
      [scheme, rest] ->
        if String.downcase(scheme) == "digest" do
          params =
            ~r/(\w+)=(?:"([^"]*)"|([^,\s]+))/
            |> Regex.scan(rest)
            |> Map.new(fn
              [_, k, quoted, ""] -> {String.downcase(k), quoted}
              [_, k, "", bare] -> {String.downcase(k), bare}
              [_, k, quoted] -> {String.downcase(k), quoted}
            end)

          {:ok, params}
        else
          :error
        end

      _ ->
        :error
    end
  end

  # -- stateless nonce --

  defp make_nonce(config) do
    ts = System.system_time(:millisecond)
    payload = Integer.to_string(ts)
    mac = :crypto.mac(:hmac, :sha256, nonce_secret(config), payload) |> Base.encode16(case: :lower)
    Base.url_encode64(payload <> ":" <> mac, padding: false)
  end

  defp valid_nonce?(nil, _config), do: false

  defp valid_nonce?(nonce, config) do
    with {:ok, raw} <- Base.url_decode64(nonce, padding: false),
         [payload, mac] <- String.split(raw, ":", parts: 2),
         expected <-
           :crypto.mac(:hmac, :sha256, nonce_secret(config), payload) |> Base.encode16(case: :lower),
         true <- Plug.Crypto.secure_compare(mac, expected),
         {ts, ""} <- Integer.parse(payload) do
      System.system_time(:millisecond) - ts <= max_age(config)
    else
      _ -> false
    end
  end

  # -- config helpers --

  defp password_for(%{lookup: fun}, username) when is_function(fun, 1) and is_binary(username),
    do: fun.(username)

  defp password_for(%{username: u, password: p}, username) when is_binary(username) do
    if Plug.Crypto.secure_compare(username, u), do: {:ok, p}, else: :error
  end

  defp password_for(_, _), do: :error

  defp realm(config), do: Map.get(config, :realm, @default_realm)
  defp nonce_secret(config), do: Map.get(config, :nonce_secret, "caretaker-nonce")
  defp max_age(config), do: Map.get(config, :nonce_max_age_ms, @default_max_age_ms)

  defp md5(parts), do: :crypto.hash(:md5, Enum.join(parts, ":")) |> Base.encode16(case: :lower)
end
