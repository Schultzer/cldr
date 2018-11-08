defmodule Cldr.Config do
  @moduledoc false

  alias Cldr.Locale
  alias Cldr.LanguageTag
  alias Cldr.Number.System

  defstruct default_locale: "en-001",
    locales: ["en-001"],
    backend: nil,
    gettext: nil,
    data_dir: "./priv/cldr",
    precompile_number_formats: [],
    precompile_transliterations: [],
    otp_app: nil

  @type t :: %__MODULE__{
    default_locale: binary(),
    locales: [binary(), ...],
    backend: module(),
    gettext: module() | nil,
    data_dir: binary(),
    precompile_number_formats: [binary(), ...],
    precompile_transliterations: [{atom(), atom()}, ...],
    otp_app: atom() | nil
  }

  @default_locale "en-001"

  @cldr_modules [
    "number_formats",
    "list_formats",
    "currencies",
    "number_systems",
    "number_symbols",
    "minimum_grouping_digits",
    "rbnf",
    "units",
    "date_fields",
    "dates",
    "territories",
    "languages"
  ]

  @doc false
  @non_language_locale_names []
  def non_language_locale_names do
    @non_language_locale_names
  end

  @doc false
  defmacro is_alphabetic(char) do
    quote do
      unquote(char) in ?a..?z or unquote(char) in ?A..?Z
    end
  end


  Module.put_attribute(
    __MODULE__,
    :poison,
    if(Code.ensure_loaded?(Poison), do: Poison, else: nil)
  )

  Module.put_attribute(
    __MODULE__,
    :jason,
    if(Code.ensure_loaded?(Jason), do: Jason, else: nil)
  )

  @doc """
  Return the configured application name
  """
  @app_name Mix.Project.config()[:app]
  def app_name do
    @app_name
  end

  @doc """
  Return the configured json lib
  """
  @jason_lib Application.get_env(:ex_cldr, :json_library) || @jason || @poison
  def json_library do
    @jason_lib
  end

  @doc """
  Check that the configured json library is
  configured and available for use
  """
  def check_jason_lib_is_available! do
    unless Code.ensure_loaded?(json_library()) && function_exported?(json_library(), :decode!, 1) do
      message =
        if is_nil(json_library()) do
          """
           A json library has not been configured.  Please configure one in
           your `mix.exs` file.  The preferred library is `:jason`.
           For example in your `mix.exs`:

             def deps() do
               [
                 {:jason, "~> 1.0"},
                 ...
               ]
             end
          """
        else
          """
          The json library #{inspect(json_library())} is either
          not configured or does not define the function decode!/1
          """
        end

      raise ArgumentError, message
    end
  end

  @doc """
  Return the root path of the cldr application
  """
  def cldr_home do
    Path.join(__DIR__, "/../../..") |> Path.expand()
  end

  @doc """
  Return the directory where `Cldr` stores its source core data,  This
  directory should not be expected to be available other than when developing
  Cldr since it points to a source directory.
  """
  @cldr_relative_dir "/priv/cldr"
  def source_data_dir do
    Path.join(cldr_home(), @cldr_relative_dir)
  end

  @doc """
  Returns the path of the CLDR data directory for the ex_cldr app
  """
  def cldr_data_dir do
    [:code.priv_dir(app_name()), "/cldr"] |> :erlang.iolist_to_binary()
  end

  @doc """
  Return the path name of the CLDR data directory for a client application.
  """
  @default_client_data_dir Path.join(".", @cldr_relative_dir)
  def client_data_dir do
    Application.get_env(app_name(), :data_dir, @default_client_data_dir)
    |> Path.expand()
  end

  @doc """
  Returns the directory where the CLDR locales files are located.
  """
  def client_locales_dir do
    Path.join(client_data_dir(), "locales")
  end

  @doc """
  Returns the version string of the CLDR data repository
  """
  def version do
    cldr_data_dir()
    |> Path.join("version.json")
    |> File.read!()
    |> json_library().decode!
  end

  @doc """
  Returns the filename that contains the json representation of a locale
  """
  def locale_filename(locale) do
    "#{locale}.json"
  end

  @doc """
  Returns the directory where the downloaded CLDR repository files
  are stored.
  """
  def download_data_dir do
    Path.join(cldr_home(), "data")
  end

  @doc """
  Return the configured `Gettext` module name or `nil`.
  """
  @spec gettext(t()) :: module() | nil
  def gettext(config) do
    Map.get(config, :gettext)
  end

  @doc """
  Returns the default backend module
  """
  def default_backend do
    Application.get_env(app_name(), :default_backend)
  end

  @doc """
  Return the default locale.

  In order of priority return either:

  * The default locale specified in the `mix.exs` file
  * The `Gettext.get_locale/1` for the current configuration
  * "en"
  """
  @spec default_locale(t()) :: Locale.locale_name()
  def default_locale(config) do
    Map.get(config, :default_locale) ||
    Application.get_env(app_name(), :default_locale) ||
    gettext_default_locale(config) ||
    @default_locale
  end

  defp gettext_default_locale(config) do
    if gettext_configured?(config) do
      Gettext
      |> apply(:get_locale, [gettext(config)])
      |> locale_name_from_posix()
    else
      nil
    end
  end

  @doc """
  Return a list of the locales defined in `Gettext`.

  Return a list of locales configured in `Gettext` or
  `[]` if `Gettext` is not configured.

  """
  @spec known_gettext_locale_names(t()) :: [Locale.locale_name()]
  def known_gettext_locale_names(config) do
    if gettext_configured?(config) && Application.ensure_all_started(:gettext) do
      otp_app = gettext(config).__gettext__(:otp_app)
      gettext_backend = gettext(config)

      backend_default =
        otp_app
        |> Application.get_env(gettext_backend)
        |> Keyword.get(:default_locale)

      global_default =
        Application.get_env(:gettext, :default_locale)

      locales =
        apply(Gettext, :known_locales, [gettext_backend]) ++
        [backend_default, global_default]

      locales
      |> Enum.reject(&is_nil/1)
      |> Enum.map(&locale_name_from_posix/1)
      |> Enum.uniq()
      |> Enum.sort()
    else
      []
    end
  end

  @doc """
  Returns a list of all locales in the CLDR repository.

  Returns a list of the complete locales list in CLDR, irrespective
  of whether they are configured for use in the application.

  Any configured locales that are not present in this list will
  raise an exception at compile time.
  """
  @spec all_locale_names :: [Locale.locale_name(), ...]
  def all_locale_names do
    Path.join(cldr_data_dir(), "available_locales.json")
    |> File.read!()
    |> json_library().decode!
    |> Enum.sort()
  end

  @doc """
  Returns the map of language tags for all
  available locales
  """
  @tag_file "language_tags.ebin"
  def all_language_tags do
    Path.join(cldr_data_dir(), @tag_file)
    |> File.read!()
    |> :erlang.binary_to_term()
  rescue
    _e in File.Error -> %{}
  end

  def all_language_tags? do
    cldr_data_dir()
    |> Path.join(@tag_file)
    |> File.exists?()
  end

  @doc """
  Return the saved language tag for the
  given locale name
  """
  def language_tag(locale_name) do
    Map.get(all_language_tags(), locale_name)
  end

  @doc """
  Returns a list of all locales configured in the `config.exs`
  file.

  In order of priority return either:

  * The list of locales configured configured in mix.exs if any

  * The default locale

  If the configured locales is `:all` then all locales
  in CLDR are configured.

  The locale "root" is always added to the list of configured locales since it
  is required to support some RBNF functions.

  The use of `:all` is not recommended since all 537 locales take
  quite some time (minutes) to compile. It is however
  helpful for testing Cldr.
  """
  @spec configured_locale_names(t()) :: [Locale.locale_name()]
  def configured_locale_names(config) do
    locale_names =
      case app_locale_names = Map.get(config, :locales) do
        :all -> all_locale_names()
        nil -> expand_locale_names([default_locale(config)])
        _ -> expand_locale_names(app_locale_names)
      end

    ["root" | locale_names]
    |> Enum.uniq()
    |> Enum.sort()
  end

  @doc """
  Returns a list of all locales that are configured and available
  in the CLDR repository.
  """
  @spec known_locale_names(t()) :: [Locale.locale_name()]
  def known_locale_names(config) do
    requested_locale_names(config)
    |> MapSet.new()
    |> MapSet.intersection(MapSet.new(all_locale_names()))
    |> MapSet.to_list()
    |> Enum.sort()
  end

  def known_rbnf_locale_names(config) do
    known_locale_names(config)
    |> Enum.filter(fn locale -> Map.get(get_locale(locale), :rbnf) != %{} end)
  end

  def known_locale_name(locale_name, config) do
    if locale_name in known_locale_names(config) do
      locale_name
    else
      false
    end
  end

  def known_rbnf_locale_name(locale_name, config) do
    if locale_name in known_rbnf_locale_names(config) do
      locale_name
    else
      false
    end
  end

  @doc """
  Returns a list of all locales that are configured but not available
  in the CLDR repository.
  """
  @spec unknown_locale_names(t()) :: [Locale.locale_name()]
  def unknown_locale_names(config) do
    requested_locale_names(config)
    |> MapSet.new()
    |> MapSet.difference(MapSet.new(all_locale_names()))
    |> MapSet.to_list()
    |> Enum.sort()
  end

  @doc """
  Returns a list of all configured locales.

  The list contains locales configured both in `Gettext` and
  specified in the mix.exs configuration file as well as the
  default locale.
  """
  @spec requested_locale_names(t()) :: [Locale.locale_name()]
  def requested_locale_names(config) do
    (configured_locale_names(config) ++ known_gettext_locale_names(config) ++ [default_locale(config)])
    |> Enum.uniq()
    |> Enum.sort()
  end

  @doc """
  Returns a list of strings representing the calendars known to `Cldr`.

  ## Example

      iex> Cldr.Config.known_calendars
      [:buddhist, :chinese, :coptic, :dangi, :ethiopic, :ethiopic_amete_alem,
       :gregorian, :hebrew, :indian, :islamic, :islamic_civil, :islamic_rgsa,
       :islamic_tbla, :islamic_umalqura, :japanese, :persian, :roc]

  """
  def known_calendars do
    calendar_info() |> Map.keys() |> Enum.sort()
  end

  @doc """
  Returns a list of the currencies known in `Cldr` in
  upcased atom format.

  ## Example

      iex> Cldr.Config.known_currencies
      [:XBB, :XEU, :SKK, :AUD, :CZK, :ISJ, :BRC, :IDR, :UYP, :VEF, :UAH, :KMF, :NGN,
       :NAD, :LUC, :AWG, :BRZ, :AOK, :SHP, :DEM, :UGS, :ECS, :BRR, :HUF, :INR, :TPE,
       :GYD, :MCF, :USS, :ALK, :TJR, :BGO, :BUK, :DKK, :LSL, :AZM, :ZRN, :MKN, :GHC,
       :JMD, :NOK, :GWP, :CVE, :RUR, :BDT, :NIC, :LAK, :XFO, :KHR, :SRD, :ESB, :PGK,
       :YUD, :BRN, :MAD, :PYG, :QAR, :MOP, :BOB, :CHW, :PHP, :SDG, :SEK, :KZT, :SDP,
       :ZWD, :XTS, :SRG, :ANG, :CLF, :BOV, :XBA, :TMT, :TJS, :CUC, :SUR, :MAF, :BRL,
       :PLZ, :PAB, :AOA, :ZWR, :UGX, :PTE, :NPR, :BOL, :MRO, :MXN, :ATS, :ARP, :KWD,
       :CLE, :NLG, :TMM, :SAR, :PEN, :PKR, :RUB, :AMD, :MDL, :XRE, :AOR, :MZN, :ESA,
       :XOF, :CNX, :ILR, :KRW, :CDF, :VND, :DJF, :FKP, :BIF, :FJD, :MYR, :BBD, :GEK,
       :PES, :CNY, :GMD, :SGD, :MTP, :ZMW, :MWK, :BGN, :GEL, :TTD, :LVL, :XCD, :ARL,
       :EUR, :UYU, :ZAL, :CSD, :ECV, :GIP, :CLP, :KRH, :CYP, :TWD, :SBD, :SZL, :IRR,
       :LRD, :CRC, :XDR, :SYP, :YUM, :SIT, :DOP, :MVP, :BWP, :KPW, :GNS, :ZMK, :BZD,
       :TRY, :MLF, :KES, :MZE, :ALL, :JOD, :HTG, :TND, :ZAR, :LTT, :BGL, :XPD, :CSK,
       :SLL, :BMD, :BEF, :FIM, :ARA, :ZRZ, :CHF, :SOS, :KGS, :GWE, :LTL, :ITL, :DDM,
       :ERN, :BAM, :BRB, :ARS, :RHD, :STD, :RWF, :GQE, :HRD, :ILP, :YUR, :AON, :BYR,
       :RSD, :ZWL, :XBD, :XFU, :GBP, :VEB, :BTN, :UZS, :BGM, :BAD, :MMK, :XBC, :LUF,
       :BSD, :XUA, :GRD, :CHE, :JPY, :EGP, :XAG, :LYD, :XAU, :USD, :BND, :XPT, :BRE,
       :ROL, :PLN, :MZM, :FRF, :MGF, :LUL, :SSP, :DZD, :IEP, :SDD, :ADP, :AFN, :IQD,
       :GHS, :TOP, :LVR, :YUN, :MRU, :MKD, :GNF, :MXP, :THB, :CNH, :TZS, :XPF, :AED,
       :SVC, :RON, :BEC, :CUP, :USN, :LBP, :BOP, :BHD, :UYW, :BAN, :MDC, :VUV, :MGA,
       :ISK, :COP, :BYN, :UAK, :TRL, :SCR, :KRO, :ILS, :ETB, :CAD, :AZN, :VNN, :NIO,
       :COU, :EEK, :KYD, :MNT, :HNL, :WST, :PEI, :YER, :MTL, :STN, :AFA, :ARM, :HKD,
       :NZD, :VES, :UYI, :MXV, :GTQ, :BYB, :XXX, :XSU, :HRK, :OMR, :BEL, :MUR, :ESP,
       :YDD, :MVR, :LKR, :XAF]

  """
  def known_currencies do
    cldr_data_dir()
    |> Path.join("currencies.json")
    |> File.read!()
    |> json_library().decode!
    |> Enum.map(&String.to_atom/1)
  end

  @doc """
  Returns a list of strings representing the number systems known to `Cldr`.

  ## Example

      iex> Cldr.Config.known_number_systems
      [:adlm, :ahom, :arab, :arabext, :armn, :armnlow, :bali, :beng, :bhks, :brah,
       :cakm, :cham, :cyrl, :deva, :ethi, :fullwide, :geor, :gong, :gonm, :grek,
       :greklow, :gujr, :guru, :hanidays, :hanidec, :hans, :hansfin, :hant, :hantfin,
       :hebr, :hmng, :java, :jpan, :jpanfin, :kali, :khmr, :knda, :lana, :lanatham,
       :laoo, :latn, :lepc, :limb, :mathbold, :mathdbl, :mathmono, :mathsanb,
       :mathsans, :mlym, :modi, :mong, :mroo, :mtei, :mymr, :mymrshan, :mymrtlng,
       :newa, :nkoo, :olck, :orya, :osma, :rohg, :roman, :romanlow, :saur, :shrd,
       :sind, :sinh, :sora, :sund, :takr, :talu, :taml, :tamldec, :telu, :thai, :tibt,
       :tirh, :vaii, :wara]

  """
  def known_number_systems do
    number_systems()
    |> Map.keys()
    |> Enum.sort()
  end

  @doc """
  Returns locale and number systems that have the same digits and
  separators as the supplied one.

  Transliterating between locale & number systems is expensive.  To avoid
  unncessary transliteration we look for locale and number systems that have
  the same digits and separators.  Typically we are comparing to locale "en"
  and number system "latn" since this is what the number formatting routines use
  as placeholders.
  """
  @spec known_number_systems_like(LanguageTag.t() | Locale.locale_name(), Cldr.Number.System.system_name, t()) ::
          {:ok, List.t()} | {:error, tuple}

  def known_number_systems_like(locale_name, number_system, config) do
    with {:ok, %{digits: digits}} <- number_system_for(locale_name, number_system),
         {:ok, symbols} <- number_symbols_for(locale_name, number_system),
         {:ok, names} <- number_system_names_for(locale_name) do
      likes = do_number_systems_like(digits, symbols, names, config)
      {:ok, likes}
    end
  end

  defp do_number_systems_like(digits, symbols, names, config) do
    Enum.map(known_locale_names(config), fn this_locale ->
      Enum.reduce(names, [], fn this_system, acc ->
        case number_system_for(this_locale, this_system) do
          {:error, _} ->
            acc

          {:ok, %{digits: these_digits}} ->
            {:ok, these_symbols} = number_symbols_for(this_locale, this_system)

            if digits == these_digits && symbols == these_symbols do
              acc ++ {this_locale, this_system}
            end
        end
      end)
    end)
    |> Enum.reject(&(is_nil(&1) || &1 == []))
  end

  @max_concurrency :'Elixir.System'.schedulers_online() * 2
  def known_number_system_types(config) do
    config
    |> known_locale_names()
    |> Task.async_stream(__MODULE__, :number_systems_for, [], max_concurrency: @max_concurrency)
    |> Enum.to_list()
    |> Enum.flat_map(fn {:ok, {:ok, systems}} -> Map.keys(systems) end)
    |> Enum.uniq()
    |> Enum.sort()
  end

  def number_systems_for(locale_name) do
    number_systems =
      locale_name
      |> get_locale
      |> Map.get(:number_systems)

    {:ok, number_systems}
  end

  def number_system_for(locale_name, number_system) do
    with {:ok, system_name} <- system_name_from(number_system, locale_name) do
      {:ok, Map.get(number_systems(), system_name)}
    end
  end

  def number_systems_for!(locale_name) do
    with {:ok, systems} <- number_systems_for(locale_name) do
      systems
    end
  end

  def number_system_names_for(locale_name) do
    with {:ok, number_systems} <- number_systems_for(locale_name) do
      names =
        number_systems
        |> Enum.map(&elem(&1, 1))
        |> Enum.uniq

      {:ok, names}
    end
  end

  def number_system_types_for(locale_name) do
    with {:ok, number_systems} <- number_systems_for(locale_name) do
      types =
        number_systems
        |> Enum.map(&elem(&1, 0))

      {:ok, types}
    end
  end

  @doc """
  Returns a number system name for a given locale and number system reference.

  ## Arguments

  * `system_name` is any number system name returned by
    `Cldr.known_number_systems/0` or a number system type
    returned by `Cldr.known_number_system_types/0`

  * `locale` is any valid locale name returned by `Cldr.known_locale_names/0`
    or a `Cldr.LanguageTag` struct returned by `Cldr.Locale.new!/1`

  Number systems can be references in one of two ways:

  * As a number system type such as :default, :native, :traditional and
    :finance. This allows references to a number system for a locale in a
    consistent fashion for a given use

  * With the number system name directly, such as :latn, :arab or any of the
    other 80 or so

  This function dereferences the supplied `system_name` and returns the
  actual system name.

  ## Examples

      iex> Cldr.Config.system_name_from(:default, "en")
      {:ok, :latn}

      iex> Cldr.Config.system_name_from("latn", "en")
      {:ok, :latn}

      iex> Cldr.Config.system_name_from(:native, "en")
      {:ok, :latn}

      iex> Cldr.Config.system_name_from(:nope, "en")
      {
        :error,
        {Cldr.UnknownNumberSystemError, "The number system :nope is unknown"}
      }

  Note that return value is not guaranteed to be a valid
  number system for the given locale as demonstrated in the third example.

  """
  @spec system_name_from(System.system_name, Locale.locale_name() | LanguageTag.t()) :: atom
  def system_name_from(number_system, locale_name) do
    with {:ok, number_systems} <- number_systems_for(locale_name),
         {:ok, number_system} <- validate_number_system_or_type(number_system, locale_name) do
      cond do
        Map.has_key?(number_systems, number_system) ->
          {:ok, Map.get(number_systems, number_system)}

        number_system in Map.values(number_systems) ->
          {:ok, number_system}

        true ->
          {:error, Cldr.unknown_number_system_error(number_system)}
      end
    else
      {:error, reason} -> {:error, reason}
    end
  end

  defp validate_number_system_or_type(number_system, locale_name) do
    with {:ok, number_system} <- Cldr.validate_number_system(number_system) do
      {:ok, number_system}
    else
      {:error, _} ->
        with {:ok, number_system} <- validate_number_system_type(number_system, locale_name) do
          {:ok, number_system}
        else
          {:error, _reason} -> {:error, Cldr.unknown_number_system_error(number_system)}
        end
    end
  end

  defp validate_number_system_type(number_system_type, locale_name) when is_atom(number_system_type) do
    known_types =
      locale_name
      |> get_locale
      |> known_number_system_types

    if number_system_type in known_types do
      {:ok, number_system_type}
    else
      {:error, Cldr.unknown_number_system_type_error(number_system_type)}
    end
  end

  defp validate_number_system_type(number_system_type, locale_name) when is_binary(number_system_type) do
    number_system_type
    |> String.downcase()
    |> String.to_existing_atom()
    |> validate_number_system_type(locale_name)
  rescue
    ArgumentError ->
      {:error, Cldr.unknown_number_system_type_error(number_system_type)}
  end

  @doc """
  Get the number symbol definitions
  for a locale

  """
  def number_symbols_for(locale) do
    symbols =
      locale
      |> get_locale
      |> Map.get(:number_symbols)
      |> Enum.map(fn
        {k, nil} -> {k, nil}
        {k, v} -> {k, struct(Cldr.Number.Symbol, v)}
      end)

    {:ok, symbols}
  end

  def number_symbols_for(locale, number_system) do
    with {:ok, symbols} <- number_symbols_for(locale) do
      {:ok, Keyword.get(symbols, number_system)}
    end
  end

  def number_symbols_for!(locale_name) do
    with {:ok, symbols} <- number_symbols_for(locale_name) do
      symbols
    end
  end

  @doc """
  Returns a list of atoms representing the territories known to `Cldr`.

  ## Example

      iex> Cldr.Config.known_territories
      [:"001", :"002", :"003", :"005", :"009", :"011", :"013", :"014", :"015", :"017",
       :"018", :"019", :"021", :"029", :"030", :"034", :"035", :"039", :"053", :"054",
       :"057", :"061", :"142", :"143", :"145", :"150", :"151", :"154", :"155", :"202",
       :"419", :AC, :AD, :AE, :AF, :AG, :AI, :AL, :AM, :AO, :AQ, :AR, :AS, :AT, :AU,
       :AW, :AX, :AZ, :BA, :BB, :BD, :BE, :BF, :BG, :BH, :BI, :BJ, :BL, :BM, :BN, :BO,
       :BQ, :BR, :BS, :BT, :BV, :BW, :BY, :BZ, :CA, :CC, :CD, :CF, :CG, :CH, :CI, :CK,
       :CL, :CM, :CN, :CO, :CP, :CR, :CU, :CV, :CW, :CX, :CY, :CZ, :DE, :DG, :DJ, :DK,
       :DM, :DO, :DZ, :EA, :EC, :EE, :EG, :EH, :ER, :ES, :ET, :EU, :EZ, :FI, :FJ, :FK,
       :FM, :FO, :FR, :GA, :GB, :GD, :GE, :GF, :GG, :GH, :GI, :GL, :GM, :GN, :GP, :GQ,
       :GR, :GS, :GT, :GU, :GW, :GY, :HK, :HM, :HN, :HR, :HT, :HU, :IC, :ID, :IE, :IL,
       :IM, :IN, :IO, :IQ, :IR, :IS, :IT, :JE, :JM, :JO, :JP, :KE, :KG, :KH, :KI, :KM,
       :KN, :KP, :KR, :KW, :KY, :KZ, :LA, :LB, :LC, :LI, :LK, :LR, :LS, :LT, :LU, :LV,
       :LY, :MA, :MC, :MD, :ME, :MF, :MG, :MH, :MK, :ML, :MM, :MN, :MO, :MP, :MQ, :MR,
       :MS, :MT, :MU, :MV, :MW, :MX, :MY, :MZ, :NA, :NC, :NE, :NF, :NG, :NI, :NL, :NO,
       :NP, :NR, :NU, :NZ, :OM, :PA, :PE, :PF, :PG, :PH, :PK, :PL, :PM, :PN, :PR, :PS,
       :PT, :PW, :PY, :QA, :QO, :RE, :RO, :RS, :RU, :RW, :SA, :SB, :SC, :SD, :SE, :SG,
       :SH, :SI, :SJ, :SK, :SL, :SM, :SN, :SO, :SR, :SS, :ST, :SV, :SX, :SY, :SZ, :TA,
       :TC, :TD, :TF, :TG, :TH, :TJ, :TK, :TL, :TM, :TN, :TO, :TR, :TT, :TV, :TW, :TZ,
       :UA, :UG, :UM, :UN, :US, :UY, :UZ, :VA, :VC, :VE, :VG, :VI, :VN, :VU, :WF, :WS,
       :XK, :YE, :YT, :ZA, :ZM, :ZW]

  """
  def known_territories do
    territory_containment()
    |> Enum.map(fn {k, v} -> [k, v] end)
    |> List.flatten()
    |> Enum.uniq()
    |> Enum.sort()
  end

  @doc """
  Returns true if a `Gettext` module is configured in Cldr and
  the `Gettext` module is available.

  ## Example

      iex> test_config = TestBackend.Cldr.__cldr__(:config)
      iex> Cldr.Config.gettext_configured?(test_config)
      true

  """
  @spec gettext_configured?(t()) :: boolean
  def gettext_configured?(config) do
    gettext(config) && Code.ensure_loaded?(Gettext) && Code.ensure_loaded?(gettext(config))
  end

  @doc """
  Expands wildcards in locale names.

  Locales often have region variants (for example en-AU is one of 104
  variants in CLDR).  To make it easier to configure a language and all
  its variants, a locale can be specified as a regex which will
  then do a match against all CLDR locales.

  For locale names that have a Script or Vairant component the base
  language is also configured since plural rules will fall back to the
  language for these locale names.

  ## Examples

      iex> Cldr.Config.expand_locale_names(["en-A+"])
      ["en", "en-AG", "en-AI", "en-AS", "en-AT", "en-AU"]

      iex> Cldr.Config.expand_locale_names(["fr-*"])
      ["fr", "fr-BE", "fr-BF", "fr-BI", "fr-BJ", "fr-BL", "fr-CA", "fr-CD", "fr-CF",
       "fr-CG", "fr-CH", "fr-CI", "fr-CM", "fr-DJ", "fr-DZ", "fr-GA", "fr-GF",
       "fr-GN", "fr-GP", "fr-GQ", "fr-HT", "fr-KM", "fr-LU", "fr-MA", "fr-MC",
       "fr-MF", "fr-MG", "fr-ML", "fr-MQ", "fr-MR", "fr-MU", "fr-NC", "fr-NE",
       "fr-PF", "fr-PM", "fr-RE", "fr-RW", "fr-SC", "fr-SN", "fr-SY", "fr-TD",
       "fr-TG", "fr-TN", "fr-VU", "fr-WF", "fr-YT"]
  """
  @wildcard_matchers ["*", "+", ".", "["]
  @spec expand_locale_names([Locale.locale_name(), ...]) :: [Locale.locale_name(), ...]
  def expand_locale_names(locale_names) do
    Enum.map(locale_names, fn locale_name ->
      if String.contains?(locale_name, @wildcard_matchers) do
        case Regex.compile(locale_name) do
          {:ok, regex} ->
            Enum.filter(all_locale_names(), &Regex.match?(regex, &1))

          {:error, reason} ->
            raise ArgumentError,
                  "Invalid regex in locale name #{inspect(locale_name)}: #{inspect(reason)}"
        end
      else
        locale_name
      end
    end)
    |> List.flatten()
    |> Enum.map(fn locale_name ->
      case String.split(locale_name, "-") do
        [language] -> language
        [language | _rest] -> [language, locale_name]
      end
    end)
    |> List.flatten()
    |> Enum.uniq()
  end

  @doc """
  Returns the location of the json data for a locale or `nil`
  if the locale can't be found.

  * `locale` is any locale returned from `Cldr.known_locale_names()`
  """
  @spec locale_path(String.t()) :: {:ok, String.t()} | {:error, :not_found}
  def locale_path(locale) do
    relative_locale_path = ["locales/", "#{locale}.json"]
    client_path = Path.join(client_data_dir(), relative_locale_path)
    cldr_path = Path.join(cldr_data_dir(), relative_locale_path)

    cond do
      File.exists?(client_path) -> {:ok, client_path}
      File.exists?(cldr_path) -> {:ok, cldr_path}
      true -> {:error, :not_found}
    end
  end

  @doc """
  Read the locale json, decode it and make any necessary transformations.

  This is the only place that we read the locale and we only
  read it once.  All other uses of locale data are references
  to this data.

  Additionally the intention is that this is read only at compile time
  and used to construct accessor functions in other modules so that
  during production run there is no file access or decoding.
  """
  def get_locale(locale) do
    {:ok, path} =
      case locale_path(locale) do
        {:ok, path} ->
          {:ok, path}

        {:error, :not_found} ->
          raise RuntimeError, message: "Locale definition was not found for #{locale}"
      end

    do_get_locale(locale, path, Cldr.Locale.Cache.compiling?)
  end

  @doc false
  def do_get_locale(locale, path, compiling? \\ false)

  def do_get_locale(locale, path, false) do
    path
    |> File.read!()
    |> json_library().decode!
    |> assert_valid_keys!(locale)
    |> structure_units
    |> atomize_keys(required_modules() -- ["languages"])
    |> structure_rbnf
    |> atomize_number_systems
    |> atomize_languages
    |> structure_date_formats
    |> Map.put(:name, locale)
  end

  @doc false
  def do_get_locale(locale, path, true) do
    Cldr.Locale.Cache.get_locale(locale, path)
  end

  defp atomize_keys(content, modules) do
    Enum.map(content, fn {module, values} ->
      if module in modules do
        {String.to_atom(module), Cldr.Map.atomize_keys(values)}
      else
        {String.to_atom(module), values}
      end
    end)
    |> Enum.into(%{})
  end

  @doc """
  Returns a map of territory containments
  """
  def territory_containment do
    cldr_data_dir()
    |> Path.join("territory_containment.json")
    |> File.read!()
    |> json_library().decode!
    |> Cldr.Map.atomize_keys()
    |> Cldr.Map.atomize_values()
  end

  @doc """
  Returns a map of territory info for all territories
  known to CLDR.

  The territory information is independent of the
  `ex_cldr` configuration.

  ## Example

      iex> Cldr.Config.territory_info[:GB]
      %{
        currency: [GBP: %{from: ~D[1694-07-27]}],
        gdp: 2788000000000,
        language_population: %{
          "bn" => %{population_percent: 0.67},
          "cy" => %{
            official_status: "official_regional",
            population_percent: 0.77
          },
          "de" => %{population_percent: 6},
          "el" => %{population_percent: 0.34},
          "en" => %{official_status: "official", population_percent: 99},
          "fr" => %{population_percent: 19},
          "ga" => %{
            official_status: "official_regional",
            population_percent: 0.026
          },
          "gd" => %{
            official_status: "official_regional",
            population_percent: 0.099,
            writing_percent: 5
          },
          "it" => %{population_percent: 0.34},
          "ks" => %{population_percent: 0.19},
          "kw" => %{population_percent: 0.0031},
          "ml" => %{population_percent: 0.035},
          "pa" => %{population_percent: 0.79},
          "sco" => %{population_percent: 2.7, writing_percent: 5},
          "syl" => %{population_percent: 0.51},
          "yi" => %{population_percent: 0.049},
          "zh-Hant" => %{population_percent: 0.54}
        },
        literacy_percent: 99,
        measurement_system: "UK",
        paper_size: "A4",
        population: 64769500,
        telephone_country_code: 44,
        temperature_measurement: "metric"
      }

  """
  def territory_info do
    cldr_data_dir()
    |> Path.join("territory_info.json")
    |> File.read!()
    |> json_library().decode!
    |> Enum.map(fn {k, v} -> {String.to_atom(k), v} end)
    |> atomize_territory_keys
    |> adjust_currency_codes
    |> atomize_language_population
    |> Enum.into(%{})
  end

  @doc """
  Get territory info for a specific territory.

  * `territory` is a string, atom or language_tag representation
    of a territory code in the list returned by `Cldr.known_territories`

  Returns:

  * A map of the territory information or
  * `{:error, reason}`

  ## Example

      iex> Cldr.Config.territory_info "au"
      %{
        currency: [AUD: %{from: ~D[1966-02-14]}],
        gdp: 1189000000000,
        language_population: %{
          "en" => %{
            official_status: "de_facto_official",
            population_percent: 96
          },
          "it" => %{population_percent: 1.9},
          "wbp" => %{population_percent: 0.011},
          "zh-Hant" => %{population_percent: 2.1}
        },
        literacy_percent: 99,
        measurement_system: "metric",
        paper_size: "A4",
        population: 23232400,
        telephone_country_code: 61,
        temperature_measurement: "metric"
      }

      iex> Cldr.Config.territory_info "abc"
      {:error, {Cldr.UnknownTerritoryError, "The territory \\"abc\\" is unknown"}}

  """
  @spec territory_info(String.t() | atom() | LanguageTag.t()) ::
          %{} | {:error, {Exception.t(), String.t()}}
  def territory_info(territory) do
    with {:ok, territory_code} <- Cldr.validate_territory(territory) do
      territory_info()
      |> Map.get(territory_code)
    else
      {:error, reason} -> {:error, reason}
    end
  end

  defp atomize_territory_keys(territories) do
    territories
    |> Enum.map(fn {k, v} ->
      {k, Enum.map(v, fn {k1, v1} -> {String.to_atom(k1), v1} end) |> Enum.into(%{})}
    end)
    |> Enum.into(%{})
  end

  defp atomize_languages(content) do
    languages =
      content
      |> Map.get(:languages)
      |> Enum.map(fn {k, v} -> {k, Cldr.Map.atomize_keys(v)} end)
      |> Enum.into(%{})

    Map.put(content, :languages, languages)
  end

  defp adjust_currency_codes(territories) do
    territories
    |> Enum.map(fn {territory, data} ->
      currencies =
        data
        |> Map.get(:currency)
        |> Cldr.Map.atomize_keys()
        |> into_keyword_list
        |> Enum.map(fn {currency, data} ->
          data =
            if data[:tender] == "false" do
              Map.put(data, :tender, false)
            else
              data
            end

          data =
            if data[:from] do
              Map.put(data, :from, Date.from_iso8601!(data[:from]))
            else
              data
            end

          data =
            if data[:to] do
              Map.put(data, :to, Date.from_iso8601!(data[:to]))
            else
              data
            end

          {currency, data}
        end)

      {territory, Map.put(data, :currency, currencies)}
    end)
    |> Enum.into(%{})
  end

  defp into_keyword_list(list) do
    Enum.reduce(list, Keyword.new(), fn map, acc ->
      currency = Map.to_list(map) |> hd
      [currency | acc]
    end)
  end

  defp atomize_language_population(territories) do
    territories
    |> Enum.map(fn {territory, data} ->
      languages =
        data
        |> Map.get(:language_population)
        |> atomize_language_keys
        |> Enum.into(%{})

      {territory, Map.put(data, :language_population, languages)}
    end)
    |> Enum.into(%{})
  end

  defp atomize_language_keys(nil), do: []

  defp atomize_language_keys(lang) do
    Enum.map(lang, fn {language, values} -> {language, Cldr.Map.atomize_keys(values)} end)
  end

  @doc """
  Returns the map of aliases for languages,
  scripts and regions
  """
  def aliases do
    cldr_data_dir()
    |> Path.join("aliases.json")
    |> File.read!()
    |> json_library().decode!
    |> Enum.map(fn {k, v} -> {String.to_atom(k), v} end)
    |> Enum.into(%{})
    |> structify_languages
  end

  defp structify_languages(map) do
    languages =
      Enum.map(map.language, fn {k, v} ->
        values = Cldr.Map.atomize_keys(v)
        {k, struct(Cldr.LanguageTag, values)}
      end)
      |> Enum.into(%{})

    Map.put(map, :language, languages)
  end

  @doc """
  Returns the likely subtags map which maps a
  locale string to %LaguageTag{} representing
  the likely subtags for that locale string
  """
  def likely_subtags do
    cldr_data_dir()
    |> Path.join("likely_subtags.json")
    |> File.read!()
    |> json_library().decode!
    |> Enum.map(fn {k, v} -> {k, struct(Cldr.LanguageTag, Cldr.Map.atomize_keys(v))} end)
    |> Enum.into(%{})
  end

  @doc """
  Returns the data that defines start and end of
  calendar weeks, weekends and years
  """
  def week_info do
    cldr_data_dir()
    |> Path.join("week_data.json")
    |> File.read!()
    |> json_library().decode!
    |> Cldr.Map.underscore_keys()
    |> Enum.map(&upcase_territory_codes/1)
    |> Enum.into(%{})
    |> Cldr.Map.atomize_keys()
    |> Cldr.Map.integerize_values()
    |> Map.take([:weekend_start, :weekend_end, :min_days, :first_day])
  end

  defp upcase_territory_codes({k, content}) do
    content =
      content
      |> Enum.map(fn {territory, rest} -> {String.upcase(territory), rest} end)
      |> Enum.into(%{})

    {k, content}
  end

  @doc """
  Returns the data that defines time periods of
  a day for a language.

  Time period rules are used to define the meaning
  of "morning", "evening", "noon", "midnight" and
  potentially other periods on a per-language basis.

  ## Example

      iex> Cldr.Config.day_period_info |> Map.get("fr")
      %{"afternoon1" => %{"before" => [18, 0], "from" => [12, 0]},
        "evening1" => %{"before" => [24, 0], "from" => [18, 0]},
        "midnight" => %{"at" => [0, 0]},
        "morning1" => %{"before" => [12, 0], "from" => [4, 0]},
        "night1" => %{"before" => [4, 0], "from" => [0, 0]},
        "noon" => %{"at" => [12, 0]}}

  """
  def day_period_info do
    cldr_data_dir()
    |> Path.join("day_periods.json")
    |> File.read!()
    |> json_library().decode!
  end

  @doc """
  Returns the data that defines start and end of
  calendar epochs.

  ## Example

      iex> Cldr.Config.calendar_info |> Map.get(:gregorian)
      %{calendar_system: "solar", eras: %{0 => %{end: 0}, 1 => %{start: 1}}}

  """
  def calendar_info do
    cldr_data_dir()
    |> Path.join("calendar_data.json")
    |> File.read!()
    |> json_library().decode!
    |> Cldr.Map.atomize_keys()
    |> Cldr.Map.integerize_keys()
    |> add_era_end_dates
  end

  @doc """
  Returns the calendars available for a given locale name

  ## Example

      iex> Cldr.Config.calendars_for_locale "en"
      [:buddhist, :chinese, :coptic, :dangi, :ethiopic, :ethiopic_amete_alem,
       :generic, :gregorian, :hebrew, :indian, :islamic, :islamic_civil,
       :islamic_rgsa, :islamic_tbla, :islamic_umalqura, :japanese, :persian, :roc]

  """
  def calendars_for_locale(locale_name) when is_binary(locale_name) do
    locale_name
    |> get_locale()
    |> Map.get(:dates)
    |> Map.get(:calendars)
    |> Map.keys()
  end

  def calendars_for_locale(%{} = locale_data) do
    locale_data
    |> Map.get(:dates)
    |> Map.get(:calendars)
    |> Map.keys()
  end

  defp add_era_end_dates(calendars) do
    Enum.map(calendars, fn {calendar, content} ->
      new_content =
        Enum.map(content, fn
          {:eras, eras} -> {:eras, add_end_dates(eras)}
          {k, v} -> {k, v}
        end)
        |> Enum.into(%{})

      {calendar, new_content}
    end)
    |> Enum.into(%{})
  end

  defp add_end_dates(%{} = eras) do
    eras
    |> Enum.sort_by(fn {k, _v} -> k end, fn a, b -> a < b end)
    |> add_end_dates
    |> Enum.into(%{})
  end

  defp add_end_dates([{_, %{start: _start_1}} = era_1, {_, %{start: start_2}} = era_2]) do
    {era, dates} = era_1
    [{era, Map.put(dates, :end, start_2 - 1)}, era_2]
  end

  defp add_end_dates([{_, %{start: _start_1}} = era_1 | [{_, %{start: start_2}} | _] = tail]) do
    {era, dates} = era_1
    [{era, Map.put(dates, :end, start_2 - 1)}] ++ add_end_dates(tail)
  end

  defp add_end_dates(other) do
    other
  end

  @doc """
  Get the configured number formats that should be precompiled at application
  compilation time.

  """
  def get_precompile_number_formats(config) do
    Map.get(config, :precompile_number_formats, [])
  end

  # Extract number formats from short and long lists
  @doc false
  def extract_formats(formats) when is_map(formats) do
    formats
    |> Map.values()
    |> Enum.map(&hd/1)
  end

  @doc false
  def extract_formats(format) do
    format
  end

  @doc false
  def decimal_format_list(config) do
    config
    |> known_locale_names
    |> Enum.map(&decimal_formats_for/1)
    |> Kernel.++(get_precompile_number_formats(config))
    |> List.flatten()
    |> Enum.uniq()
    |> Enum.reject(&is_nil/1)
    |> Enum.sort()
  end

  @doc false
  def decimal_formats_for(locale) do
    locale
    |> get_locale
    |> Map.get(:number_formats)
    |> Map.values()
    |> Enum.map(&Map.delete(&1, :currency_spacing))
    |> Enum.map(&Map.delete(&1, :currency_long))
    |> Enum.map(&Map.values/1)
    |> List.flatten()
    |> Enum.reject(&is_integer/1)
    |> Enum.map(&extract_formats/1)
    |> List.flatten()
    |> Enum.uniq()
    |> Enum.sort()
  end

  @doc false
  def number_systems do
    cldr_data_dir()
    |> Path.join("number_systems.json")
    |> File.read!()
    |> json_library().decode!
    |> Cldr.Map.atomize_keys()
    |> Enum.map(fn {k, v} -> {k, %{v | type: String.to_atom(v.type)}} end)
    |> Enum.into(%{})
  end

  @doc false
  def rbnf_rule_function(rule_name, backend) do
    case String.split(rule_name, "/") do
      [locale_name, ruleset, rule] ->
        ruleset_module =
          ruleset
          |> String.trim_trailing("Rules")

        function =
          rule
          |> locale_name_to_posix
          |> String.to_atom()

        locale_name =
          locale_name
          |> locale_name_from_posix

        module = Module.concat(backend, Rbnf) |> Module.concat(ruleset_module)
        {module, function, locale_name}

      [rule] ->
        function =
          rule
          |> locale_name_to_posix
          |> String.to_atom()

        {Module.concat(backend, Rbnf.NumberSystem), function, "root"}
    end
  end

  @doc """
  Transforms a locale name from the Posix format to the Cldr format
  """
  def locale_name_from_posix(nil), do: nil
  def locale_name_from_posix(name) when is_binary(name), do: String.replace(name, "_", "-")

  @doc """
  Transforms a locale name from the CLDR format to the Posix format
  """
  def locale_name_to_posix(nil), do: nil
  def locale_name_to_posix(name) when is_binary(name), do: String.replace(name, "-", "_")

  # ------ Helpers ------

  # Simple check that the locale content contains what we expect
  # by checking it has the keys we used when the locale was consolidated.
  defp assert_valid_keys!(content, locale) do
    for module <- required_modules() do
      if !Map.has_key?(content, module) and !:'Elixir.System'.get_env("DEV") do
        raise RuntimeError,
          message:
            "Locale file #{inspect(locale)} is invalid - map key #{inspect(module)} was not found."
      end
    end

    content
  end

  @doc """
  Identifies the top level keys in the consolidated locale file.

  These keys represent difference dimensions of content in the CLDR
  repository and serve three purposes:

  1. To structure the content in the locale file

  2. To provide a rudimentary way to validate that some json represents a
  valid locale file

  3. To allow conditional inclusion of CLDR content at compile time to help
  manage memory footprint.  This capability is not yet built into `Cldr`.
  """
  @spec required_modules :: [String.t()]
  def required_modules do
    @cldr_modules
  end

  # Number systems are stored as atoms, no new
  # number systems are ever added at runtime so
  # risk to overflowing the atom table is very low.
  defp atomize_number_systems(content) do
    number_systems =
      content
      |> Map.get(:number_systems)
      |> Enum.map(fn {k, v} -> {k, atomize(v)} end)
      |> Enum.into(%{})

    Map.put(content, :number_systems, number_systems)
  end

  defp structure_date_formats(content) do
    dates =
      content.dates
      |> Cldr.Map.integerize_keys()

    Map.put(content, :dates, dates)
  end

  # Put the rbnf rules into a %Rule{} struct
  defp structure_rbnf(content) do
    rbnf =
      content[:rbnf]
      |> Enum.map(fn {group, sets} ->
        {group, structure_sets(sets)}
      end)
      |> Enum.into(%{})

    Map.put(content, :rbnf, rbnf)
  end

  def structure_units(content) do
    units =
      content["units"]
      |> Enum.map(fn {style, units} -> {style, group_units(units)} end)
      |> Enum.into(%{})

    Map.put(content, "units", units)
  end

  defp group_units(units) do
    units
    |> Enum.map(fn {k, v} ->
      [group | key] = String.split(k, "_", parts: 2)

      if key == [] do
        nil
      else
        [key] = key
        {group, key, v}
      end
    end)
    |> Enum.reject(&is_nil/1)
    |> Enum.group_by(fn {group, _key, _value} -> group end, fn {_group, key, value} ->
      {key, value}
    end)
    |> Enum.map(fn {k, v} -> {k, Enum.into(v, %{})} end)
    |> Enum.into(%{})
  end

  defp structure_sets(sets) do
    Enum.map(sets, fn {name, set} ->
      name = underscore(name)
      {underscore(name), Map.put(set, :rules, set[:rules])}
    end)
    |> Enum.into(%{})
  end

  defp underscore(string) when is_binary(string) do
    string
    |> String.replace("-", "_")
  end

  defp underscore(other), do: other

  # Convert to an atom but only if
  # its a binary.
  defp atomize(nil), do: nil
  defp atomize(v) when is_binary(v), do: String.to_atom(v)
  defp atomize(v), do: v

  @doc false
  def true_false() do
    ["true", "false"]
  end

  @doc false
  def days_of_week() do
    ["sun", "mon", "tue", "wed", "thu", "fri", "sat", "sun"]
  end

  @doc false
  def collations() do
    [
      "big5han",
      "dict",
      "direct",
      "gb2312",
      "phonebk",
      "pinyin",
      "reformed",
      "standard",
      "stroke",
      "trad",
      "unihan"
    ]
  end

  @doc false
  def config_from_opts(module_config) do
    global_config =
      Application.get_all_env(app_name())

    otp_config =
      if otp_app = module_config[:otp_app] do
        Application.get_env(otp_app, app_name(), [])
      else
        []
      end

    config =
      global_config
      |> Keyword.merge(otp_config)
      |> Keyword.merge(module_config)
      |> Map.new

    config =
      config
      |> Map.put(:default_locale, Cldr.Config.default_locale(config))

    struct(__MODULE__, config)
  end

  # Returns the AST of any configured plugins
  @doc false
  def define_plugin_modules(config) do
    for {module, function, _args} <-  Cldr.Config.Dependents.cldr_provider_modules do
      apply(module, function, [config])
    end
  end
end
