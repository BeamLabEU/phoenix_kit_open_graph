defmodule PhoenixKitOG.GettextCatalogTest do
  @moduledoc """
  The shipped catalogues against the template: every message translated
  in every locale, with the interpolations and template tokens of its
  msgid intact.
  """
  use ExUnit.Case, async: true

  alias Expo.Message

  @root Path.expand("../../priv/gettext", __DIR__)
  @locales ~w(de es et fr it pl ru)
  @plural_forms %{"de" => 2, "es" => 2, "et" => 2, "fr" => 2, "it" => 2, "pl" => 3, "ru" => 3}

  defp text(parts), do: IO.iodata_to_binary(parts)

  defp tokens(string) do
    ~r/%\{\w+\}|\{\{\w+\}\}|\[\[\w+\]\]/ |> Regex.scan(string) |> List.flatten() |> Enum.sort()
  end

  defp messages(locale) do
    Expo.PO.parse_file!(Path.join([@root, locale, "LC_MESSAGES", "default.po"])).messages
  end

  defp msgids(messages), do: messages |> Enum.map(&text(&1.msgid)) |> Enum.sort()

  test "ships exactly the documented locales" do
    assert @root |> File.ls!() |> Enum.reject(&(&1 == "default.pot")) |> Enum.sort() == @locales
  end

  for locale <- @locales do
    test "#{locale} carries every msgid of the template" do
      template = Expo.PO.parse_file!(Path.join(@root, "default.pot")).messages
      assert msgids(messages(unquote(locale))) == msgids(template)
    end

    test "#{locale} has no empty, fuzzy or token-dropping translation" do
      for message <- messages(unquote(locale)) do
        msgid = text(message.msgid)
        refute "fuzzy" in List.flatten(message.flags), "#{msgid} is fuzzy"

        case message do
          %Message.Singular{msgstr: msgstr} ->
            assert text(msgstr) != "", "#{msgid} is untranslated"
            assert tokens(text(msgstr)) == tokens(msgid), "#{msgid} lost a token"

          %Message.Plural{msgstr: forms, msgid_plural: plural} ->
            assert map_size(forms) == @plural_forms[unquote(locale)], "#{msgid} plural forms"

            for {_index, form} <- forms do
              assert text(form) != "", "#{msgid} has an untranslated plural form"
              assert tokens(text(form)) == tokens(text(plural)), "#{msgid} lost a token"
            end
        end
      end
    end
  end

  describe "rendered through the backend" do
    test "an error message follows the locale" do
      assert Gettext.with_locale(PhoenixKitOG.Gettext, "et", fn ->
               PhoenixKitOG.Errors.message(:template_missing)
             end) == "Valige esmalt mall."

      assert Gettext.with_locale(PhoenixKitOG.Gettext, "de", fn ->
               PhoenixKitOG.Errors.message(:group_missing)
             end) == "Wählen Sie eine Publishing-Gruppe."
    end

    test "a global's label and description follow the locale" do
      Gettext.with_locale(PhoenixKitOG.Gettext, "ru", fn ->
        assert PhoenixKitOG.Variables.global_label("site_name") == "Название сайта"

        assert PhoenixKitOG.Variables.global_description("site_name") ==
                 "Из настройки project_title"
      end)
    end
  end
end
