defmodule Multix.Extractor do
  @moduledoc false

  @doc """
  Extracts all types implemented for the given dispatcher from
  the given paths.
  The paths can be either a charlist or a string. Internally
  they are worked on as charlists, so passing them as lists
  avoid extra conversion.
  Does not load any of the implementations.
  ## Examples
      # Get Elixir's ebin and retrieve all implementations
      iex> path = :code.get_path()
      iex> mods = Multix.Extractor.extract_impls(path)
  """
  @spec extract_impls([charlist | String.t()]) :: [atom]
  def extract_impls(paths \\ :code.get_path()) do
    paths
    |> Stream.flat_map(fn path ->
      for file <- list_dir(path), mod = extract_from_file(path, file), do: mod
    end)
  end

  defp list_dir(path) when is_list(path) do
    case :file.list_dir(path) do
      {:ok, files} -> files
      _ -> []
    end
  end

  defp list_dir(path), do: list_dir(to_charlist(path))

  def extract_from_file(file) do
    if :filename.extension(file) == '.beam' do
      extract_from_beam(file)
    end
  end

  def extract_from_file(path, file) do
    extract_from_file(:filename.join(path, file))
  end

  defp extract_from_beam(file) do
    case :beam_lib.chunks(file, [:attributes]) do
      {:ok, {module, [attributes: attributes]}} ->
        case attributes[:multix_impl] do
          nil ->
            nil

          targets ->
            {module, targets}
        end

      _ ->
        nil
    end
  end
end
