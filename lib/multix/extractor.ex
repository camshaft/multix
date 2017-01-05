defmodule Multix.Extractor do
  @moduledoc false

  @doc """
  Extracts all dispatchers from the given paths.
  The paths can be either a charlist or a string. Internally
  they are worked on as charlists, so passing them as lists
  avoid extra conversion.
  Does not load any of the dispatchers.
  ## Examples
      # Get Elixir's ebin and retrieve all dispatchers
      iex> path = :code.lib_dir(:elixir, :ebin)
      iex> mods = Multix.Extractor.extract_dispatchers([path])
      iex> Enumerable in mods
      true
  """
  @spec extract_dispatchers([charlist | String.t]) :: [atom]
  def extract_dispatchers(paths) do
    extract_matching_by_attribute paths, 'Multix.',
      fn module, attributes ->
        case attributes[:multix] do
          methods when is_list(methods) and length(methods) > 0 -> [module]
          _ -> nil
        end
      end
  end

  @doc """
  Extracts all types implemented for the given dispatcher from
  the given paths.
  The paths can be either a charlist or a string. Internally
  they are worked on as charlists, so passing them as lists
  avoid extra conversion.
  Does not load any of the implementations.
  ## Examples
      # Get Elixir's ebin and retrieve all implementations
      iex> path = :code.lib_dir(:elixir, :ebin)
      iex> mods = Multix.Extractor.extract_impls(:"MyMod.my_fun/1", [path])
      iex> List in mods
      true
  """
  @spec extract_impls(module, [charlist | String.t]) :: [atom]
  def extract_impls(dispatch, paths) when is_atom(dispatch) do
    extract_matching_by_attribute(paths, 'Elixir.', fn
      _mod, attributes ->
        case attributes[dispatch] do
          nil ->
            nil
          clauses ->
            clauses
        end
    end)
  end

  defp extract_matching_by_attribute(paths, prefix, callback) do
    paths
    |> Stream.flat_map(fn
      (:in_memory) ->
        for {module, :in_memory} <- :code.all_loaded(),
            mod = callback.(module, module.module_info(:attributes)),
            do: mod
      (path) ->
        for file <- list_dir(path),
            mod = extract_from_file(path, file, prefix, callback),
            do: mod
    end)
    |> Stream.flat_map(fn(clauses) ->
      clauses
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
end
