if File.exists?(Cldr.Config.download_data_dir()) do
  defmodule Mix.Tasks.Cldr.Install.Locales do
    @moduledoc """
    Installs the cldr core data and configured locales into the application.  By
    default it installs into the ./priv/cldr directory.
    """

    use Mix.Task

    @shortdoc "Install all configured `Cldr` locales."

    @doc false
    def run([]) do
      raise ArgumentError, "A Cldr backend module must be provided"
    end

    def run([backend]) do
      config = backend.__cldr__(:config)
      Cldr.Install.install_known_locale_names(config)
    end
  end
end
