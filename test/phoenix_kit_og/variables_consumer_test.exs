defmodule PhoenixKitOG.VariablesConsumerTest do
  @moduledoc """
  `Variables` against a discoverable consumer module and the host's
  `:canonical_host_resolver` — both live in the application env, so this
  file is not async.
  """
  use ExUnit.Case, async: false

  alias PhoenixKitOG.Test.Publishing
  alias PhoenixKitOG.Variables

  setup do
    Publishing.register()

    on_exit(fn ->
      Publishing.reset()
      Application.delete_env(:phoenix_kit, :canonical_host_resolver)
    end)

    :ok
  end

  def home_host("et"), do: "et.example"
  def home_host("boom"), do: raise("resolver down")
  def home_host(_), do: nil

  @slots [%{name: "Title", type: :text}, %{name: "Description", type: :text}]
  @mapping %{"Title" => "post_title", "Description" => "post_description"}

  defp context(post), do: %{module_key: "publishing", resource: post, conn: nil, language: "en"}

  describe "resolve/4 — a wired slot whose variable has no value" do
    test "is left out by default, so a preview keeps its placeholder" do
      post = Publishing.post(%{metadata: %{title: "Hello", description: nil}})

      assert Variables.resolve(@slots, @mapping, context(post)) == %{"Title" => "Hello"}
    end

    test "resolves to an empty string with unresolved: :empty" do
      post = Publishing.post(%{metadata: %{title: "Hello", description: nil}})

      assert Variables.resolve(@slots, @mapping, context(post), unresolved: :empty) ==
               %{"Title" => "Hello", "Description" => ""}
    end

    test "an unknown variable name follows the same rule" do
      post = Publishing.post()
      mapping = %{"Title" => "no_such_variable"}

      assert Variables.resolve(@slots, mapping, context(post)) == %{}

      assert Variables.resolve(@slots, mapping, context(post), unresolved: :empty) ==
               %{"Title" => ""}
    end

    test "an UNWIRED slot stays out under both settings" do
      post = Publishing.post(%{metadata: %{title: "Hello"}})
      mapping = %{"Title" => "post_title"}

      assert Variables.resolve(@slots, mapping, context(post), unresolved: :empty) ==
               %{"Title" => "Hello"}
    end
  end

  describe "global_values/1 with a canonical host resolver" do
    setup do
      Application.put_env(:phoenix_kit, :canonical_host_resolver, {__MODULE__, :home_host})
      :ok
    end

    test "the language's home host wins over the request and the endpoint" do
      conn = %Plug.Conn{scheme: :http, host: "evil.example", port: 80, request_path: "/p"}

      values =
        Variables.global_values(%{
          conn: conn,
          language: "et",
          endpoint: PhoenixKitOG.VariablesTest.Configured
        })

      assert values["site_host"] == "et.example"
      assert values["site_url"] == "https://et.example"
      assert values["page_url"] == "https://et.example/p"
    end

    test "a language without a home host falls through to the configured origin" do
      values =
        Variables.global_values(%{
          language: "en",
          endpoint: PhoenixKitOG.VariablesTest.Configured
        })

      assert values["site_host"] == "configured.example"
    end

    test "a raising resolver falls through instead of raising" do
      values =
        Variables.global_values(%{
          language: "boom",
          endpoint: PhoenixKitOG.VariablesTest.Configured
        })

      assert values["site_host"] == "configured.example"
    end
  end
end
