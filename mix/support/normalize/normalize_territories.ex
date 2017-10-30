# credo:disable-for-this-file
defmodule Cldr.Normalize.Territories do
  @moduledoc """
  Takes the territories part of the locale map and transforms the formats into a more easily
  processable structure that is then stored in map managed by `Cldr.Locale`
  """

  def normalize(content, locale) do
    content
    |> normalize_territories(locale)
  end

  def normalize_territories(content, locale) do
    locale
    |> territories_for_locale()
    |> get_in(["main", locale, "localeDisplayNames"])
    |> Map.merge(content)
  end

  def territories_for_locale(locale) do
    if File.exists?(locale_path(locale)) do
      locale
      |> locale_path
      |> File.read!
      |> Poison.decode!
    else
      {:error, {:territories_file_not_found, locale_path(locale)}}
    end
  end

  @spec locale_path(binary) :: String.t
  def locale_path(locale) when is_binary(locale) do
    Path.join([territories_dir(), locale, "territories.json"])
  end

  @territories_dir Path.join([Cldr.Config.download_data_dir, "cldr-localenames-full", "main"])

  @spec territories_dir :: String.t
  def territories_dir do
    @territories_dir
  end
end
