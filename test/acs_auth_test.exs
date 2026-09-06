defmodule Caretaker.ACS.AuthTest do
  use ExUnit.Case, async: true

  alias Caretaker.ACS.Auth
  alias Caretaker.HTTP.Auth, as: Client

  describe "basic" do
    setup do
      %{config: Auth.prepare(%{scheme: :basic, realm: "acs", username: "u", password: "p"})}
    end

    test "accepts correct credentials", %{config: config} do
      header = Client.basic("u", "p")
      assert Auth.verify(header, "POST", "/cwmp", config)
    end

    test "rejects wrong credentials and missing header", %{config: config} do
      refute Auth.verify(Client.basic("u", "wrong"), "POST", "/cwmp", config)
      refute Auth.verify(nil, "POST", "/cwmp", config)
    end

    test "challenge names the scheme and realm", %{config: config} do
      assert Auth.challenge(config) == ~s(Basic realm="acs")
    end
  end

  describe "digest" do
    setup do
      %{config: Auth.prepare(%{scheme: :digest, realm: "acs", username: "u", password: "p"})}
    end

    test "a client response computed from our challenge verifies", %{config: config} do
      challenge = Auth.challenge(config)
      auth = Client.authorization(challenge, %{username: "u", password: "p"}, :post, "/cwmp")
      assert is_binary(auth)
      assert Auth.verify(auth, "POST", "/cwmp", config)
    end

    test "a wrong password does not verify", %{config: config} do
      challenge = Auth.challenge(config)
      auth = Client.authorization(challenge, %{username: "u", password: "nope"}, :post, "/cwmp")
      refute Auth.verify(auth, "POST", "/cwmp", config)
    end

    test "a forged nonce (not issued by us) is rejected", %{config: config} do
      forged =
        ~s(Digest username="u", realm="acs", nonce="ZmFrZQ", uri="/cwmp", response="deadbeef")

      refute Auth.verify(forged, "POST", "/cwmp", config)
    end

    test "per-device lookup credentials verify", %{config: _} do
      config =
        Auth.prepare(%{
          scheme: :digest,
          realm: "acs",
          lookup: fn
            "dev-1" -> {:ok, "secret1"}
            _ -> :error
          end
        })

      challenge = Auth.challenge(config)
      ok = Client.authorization(challenge, %{username: "dev-1", password: "secret1"}, :post, "/cwmp")
      bad = Client.authorization(challenge, %{username: "dev-2", password: "secret1"}, :post, "/cwmp")

      assert Auth.verify(ok, "POST", "/cwmp", config)
      refute Auth.verify(bad, "POST", "/cwmp", config)
    end
  end
end
