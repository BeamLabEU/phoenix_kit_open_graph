defmodule PhoenixKitOG.VariablesTest do
  use ExUnit.Case, async: true

  alias PhoenixKitOG.Variables

  describe "global/0" do
    test "returns the fixed catalogue of OG-owned globals" do
      names = Variables.global() |> Enum.map(& &1.name)
      assert "site_host" in names
      assert "site_url" in names
      assert "site_name" in names
      assert "page_url" in names
      assert "page_locale" in names
    end
  end

  describe "global_values/1" do
    test "reads scheme/host/port from a Plug.Conn" do
      conn = %Plug.Conn{scheme: :https, host: "example.com", port: 443}
      values = Variables.global_values(%{conn: conn})

      assert values["site_host"] == "example.com"
      # 443 is default for https — no port suffix.
      assert values["site_url"] == "https://example.com"
    end

    test "keeps a non-default port in site_url" do
      conn = %Plug.Conn{scheme: :http, host: "localhost", port: 4000}
      values = Variables.global_values(%{conn: conn})
      assert values["site_url"] == "http://localhost:4000"
    end

    test "page_url falls back to conn.request_path when not passed" do
      conn = %Plug.Conn{scheme: :https, host: "example.com", port: 443, request_path: "/blog/x"}
      values = Variables.global_values(%{conn: conn})
      assert values["page_url"] == "https://example.com/blog/x"
    end

    test "explicit page_url wins over the conn-derived one" do
      conn = %Plug.Conn{scheme: :https, host: "example.com", port: 443, request_path: "/derived"}
      values = Variables.global_values(%{conn: conn, page_url: "/explicit"})
      assert values["page_url"] == "/explicit"
    end

    test "a nil page_url in the context still falls back to the request path" do
      conn = %Plug.Conn{scheme: :https, host: "example.com", port: 443, request_path: "/blog/x"}
      values = Variables.global_values(%{conn: conn, page_url: nil})
      assert values["page_url"] == "https://example.com/blog/x"
    end

    test "handles no conn gracefully" do
      values = Variables.global_values(%{})
      assert Map.has_key?(values, "site_host")
      assert Map.has_key?(values, "site_url")
    end

    test "a configured endpoint URL beats the request's Host header" do
      conn = %Plug.Conn{scheme: :http, host: "evil.example", port: 80, request_path: "/blog/x"}

      values =
        Variables.global_values(%{conn: conn, endpoint: PhoenixKitOG.VariablesTest.Configured})

      assert values["site_host"] == "configured.example"
      assert values["site_url"] == "https://configured.example"
      assert values["page_url"] == "https://configured.example/blog/x"
    end

    test "an endpoint that was never given a URL does not beat the request" do
      conn = %Plug.Conn{scheme: :https, host: "real.example", port: 443}

      values =
        Variables.global_values(%{conn: conn, endpoint: PhoenixKitOG.VariablesTest.Unconfigured})

      assert values["site_host"] == "real.example"
    end

    test "without a request the endpoint's URL is used as it is (the editor preview)" do
      values = Variables.global_values(%{endpoint: PhoenixKitOG.VariablesTest.Unconfigured})
      assert values["site_url"] == "http://localhost:4000"
      assert values["site_host"] == "localhost"
    end
  end

  describe "referenced_globals/3" do
    @globals %{
      "site_host" => "a.example",
      "site_url" => "https://a.example",
      "site_name" => "Acme",
      "page_url" => "https://a.example/p",
      "page_locale" => "en"
    }

    test "a scene that names no global references none" do
      scene = %{"elements" => [%{"type" => "text", "value" => "Hello {{Title}}"}]}
      assert Variables.referenced_globals(@globals, scene, %{"Title" => "x"}) == %{}
    end

    test "a [[token]] in the scene references exactly that global" do
      scene = %{"elements" => [%{"type" => "text", "value" => "on [[site_host]]"}]}

      assert Variables.referenced_globals(@globals, scene, %{}) ==
               %{"site_host" => "a.example"}
    end

    test "a [[token]] typed into a slot value counts too" do
      scene = %{"elements" => [%{"type" => "text", "value" => %{"placeholder" => "Line"}}]}

      assert Variables.referenced_globals(@globals, scene, %{"Line" => "read [[page_url]]"}) ==
               %{"page_url" => "https://a.example/p"}
    end

    test "a slot named like a global references it (both brackets share one map)" do
      whole = %{"elements" => [%{"type" => "text", "value" => %{"placeholder" => "site_name"}}]}
      inline = %{"elements" => [%{"type" => "text", "value" => "by {{site_name}}"}]}

      assert Variables.referenced_globals(@globals, whole, %{}) == %{"site_name" => "Acme"}
      assert Variables.referenced_globals(@globals, inline, %{}) == %{"site_name" => "Acme"}
    end
  end

  describe "resolve/3" do
    test "custom: prefix passes through verbatim" do
      slots = [%{name: "Title", type: :text}]
      mapping = %{"Title" => "custom:Hardcoded"}
      resolved = Variables.resolve(slots, mapping, %{module_key: "publishing"})
      assert resolved == %{"Title" => "Hardcoded"}
    end

    test "empty custom: entry resolves to empty string" do
      slots = [%{name: "Title", type: :text}]
      mapping = %{"Title" => "custom:"}
      resolved = Variables.resolve(slots, mapping, %{module_key: "publishing"})
      assert resolved == %{"Title" => ""}
    end

    test "unmapped slots are omitted from the result" do
      slots = [%{name: "Title", type: :text}, %{name: "Missing", type: :text}]
      mapping = %{"Title" => "custom:Hi"}
      resolved = Variables.resolve(slots, mapping, %{module_key: "publishing"})
      assert Map.keys(resolved) == ["Title"]
    end

    test "global variable name resolves from globals_values context" do
      slots = [%{name: "TheHost", type: :text}]
      # Wire the slot to the "site_host" global name.
      mapping = %{"TheHost" => "site_host"}

      conn = %Plug.Conn{scheme: :https, host: "example.com", port: 443}
      resolved = Variables.resolve(slots, mapping, %{module_key: "publishing", conn: conn})
      assert resolved == %{"TheHost" => "example.com"}
    end
  end

  defmodule Configured do
    def url, do: "https://configured.example"
  end

  defmodule Unconfigured do
    def url, do: "http://localhost:4000"
  end
end
