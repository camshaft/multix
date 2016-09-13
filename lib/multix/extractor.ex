defmodule Multix.Extractor do
  @doc """
  Extracts all protocols from the given paths.
  The paths can be either a charlist or a string. Internally
  they are worked on as charlists, so passing them as lists
  avoid extra conversion.
  Does not load any of the protocols.
  ## Examples
      # Get Elixir's ebin and retrieve all protocols
      iex> path = :code.lib_dir(:elixir, :ebin)
      iex> mods = Protocol.extract_protocols([path])
      iex> Enumerable in mods
      true
  """
  @spec extract_protocols([charlist | String.t]) :: [atom]
  def extract_protocols(paths) do
    extract_matching_by_attribute paths, 'Elixir.',
      fn module, attributes ->
        case attributes[:multix] do
          [] -> module
          _ -> nil
        end
      end
  end

  @doc """
  Extracts all types implemented for the given protocol from
  the given paths.
  The paths can be either a charlist or a string. Internally
  they are worked on as charlists, so passing them as lists
  avoid extra conversion.
  Does not load any of the implementations.
  ## Examples
      # Get Elixir's ebin and retrieve all protocols
      iex> path = :code.lib_dir(:elixir, :ebin)
      iex> mods = Protocol.extract_impls(Enumerable, [path])
      iex> List in mods
      true
  """
  @spec extract_impls(module, [charlist | String.t]) :: [atom]
  def extract_impls(protocol, paths) when is_atom(protocol) do
    prefix = Atom.to_charlist(protocol) ++ '.'
    extract_matching_by_attribute(paths, prefix, fn
      _mod, attributes ->
        case attributes[:multix_dispatch] do
          [multix: ^protocol, for: for, index: index] -> {for, index}
          _ -> nil
        end
    end)
    |> Enum.sort_by(&elem(&1, 1), &Kernel.>=/2)
    |> Enum.map(&elem(&1, 0))
  end

  defp extract_matching_by_attribute(paths, prefix, callback) do
    Enum.flat_map(paths, fn
      (:in_memory) ->
        for {module, :in_memory} <- :code.all_loaded(),
            mod = callback.(module, module.module_info(:attributes)),
            do: mod
      (path) ->
        for file <- list_dir(path),
            mod = extract_from_file(path, file, prefix, callback),
            do: mod
    end)
  end

  defp list_dir(path) when is_list(path) do
    case :file.list_dir(path) do
      {:ok, files} -> files
      _ -> []
    end
  end

  defp list_dir(path), do: list_dir(to_charlist(path))

  defp extract_from_file(path, file, prefix, callback) do
    if :lists.prefix(prefix, file) and :filename.extension(file) == '.beam' do
      extract_from_beam(:filename.join(path, file), callback)
    end
  end

  defp extract_from_beam(file, callback) do
    case :beam_lib.chunks(file, [:attributes]) do
      {:ok, {module, [attributes: attributes]}} ->
        callback.(module, attributes)
       _ ->
         nil
    end
  end

  @doc """
  Returns `true` if the protocol was consolidated.
  """
  @spec consolidated?(module) :: boolean
  def consolidated?(module) do
    module.__multi__(:consolidated?)
  end
end
