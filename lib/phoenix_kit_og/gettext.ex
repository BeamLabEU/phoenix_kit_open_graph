defmodule PhoenixKitOG.Gettext do
  @moduledoc """
  Gettext backend for OpenGraph-module-specific UI strings.

  Modules wrapping domain strings (template editor, assignments,
  variable/global labels, save-state badges, sample copy) declare
  `use Gettext, backend: PhoenixKitOG.Gettext` and call `gettext(...)`.
  Translations live in this repo's `priv/gettext/` — keep them in sync
  with `mix gettext.extract` + `mix gettext.merge priv/gettext`.

  The Phoenix pipeline sets the locale once via `Gettext.put_locale/1`
  (read from the process dictionary), so a single locale switch in the
  host drives this backend and core's `PhoenixKitWeb.Gettext` together.
  """

  # Each locale's generated plural-index function (`<locale>_default_plural/1`)
  # hands `Gettext.Plural.plural/2` the compiled `Expo.PluralForms` struct as
  # a literal, which dialyzer reports as an opaque-type mismatch
  # (`call_without_opaque`) in code this module does not write. Scoped to
  # those generated functions; a new locale under `priv/gettext` joins the
  # list here.
  @dialyzer {:no_opaque, Enum.map(~w(de es et fr it pl ru), &{:"#{&1}_default_plural", 1})}

  use Gettext.Backend, otp_app: :phoenix_kit_og
end
