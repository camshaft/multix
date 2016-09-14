defmodule Multix.Consolidator do
  @doc """
  Receives a protocol and a list of implementations and
  consolidates the given protocol.

  Consolidation happens by changing the protocol `impl_for`
  in the abstract format to have fast lookup rules. Usually
  the list of implementations to use during consolidation
  are retrieved with the help of `extract_impls/2`.

  It returns the updated version of the protocol bytecode.
  A given bytecode or protocol implementation can be checked
  to be consolidated or not by analyzing the protocol
  attribute:

      Protocol.consolidated?(Enumerable)

  If the first element of the tuple is `true`, it means
  the protocol was consolidated.

  This function does not load the protocol at any point
  nor loads the new bytecode for the compiled module.
  However each implementation must be available and
  it will be loaded.
  """
  @spec consolidate(module, [module]) ::
    {:ok, binary} |
    {:error, :not_a_protocol} |
    {:error, :no_beam_info}
  def consolidate(protocol, types) when is_atom(protocol) do
    with {:ok, info} <- beam_protocol(protocol),
         {:ok, code, docs} <- change_debug_info(info, types),
         do: compile(code, types, docs)
  end

  @docs_chunk 'ExDc'

  defp beam_protocol(protocol) do
    chunk_ids = [:abstract_code, :attributes, @docs_chunk]
    opts = [:allow_missing_chunks]
    case :beam_lib.chunks(beam_file(protocol), chunk_ids, opts) do
      {:ok, {^protocol, [{:abstract_code, {_raw, abstract_code}},
                         {:attributes, attributes},
                         {@docs_chunk, docs}]}} ->
        case attributes[:multix] do
          [] ->
            {:ok, {protocol, abstract_code, docs}}
          _ ->
            {:error, :not_a_protocol}
        end
      _ ->
        {:error, :no_beam_info}
    end
  end

  defp beam_file(module) when is_atom(module) do
    case :code.which(module) do
      atom when is_atom(atom) -> module
      file -> file
    end
  end

  # Change the debug information to the optimized
  # impl_for/1 dispatch version.
  defp change_debug_info({protocol, code, docs}, types) do
    case change_impl_for(code, protocol, types, false, []) do
      {:ok, ret} -> {:ok, ret, docs}
      other      -> other
    end
  end

  defp change_impl_for([], protocol, _types, is_protocol, acc) do
    if is_protocol do
      {:ok, {protocol, Enum.reverse(acc)}}
    else
      {:error, :not_a_protocol}
    end
  end
  defp change_impl_for([{:function, line, :__multix__, 1, clauses} | t], protocol, types, _, acc) do
    clauses = :lists.map(fn
      {:clause, l, [{:atom, _, :consolidated?}], [], [{:atom, _, _}]} ->
        {:clause, l, [{:atom, 0, :consolidated?}], [], [{:atom, 0, true}]}
      {:clause, _, _, _, _} = c ->
        c
    end, clauses)

    acc = [{:function, line, :__multix__, 1, clauses} | acc]

    change_impl_for(t, protocol, types, true, acc)
  end
  defp change_impl_for([{:function, line, :impl_for, 1, _} | t], protocol, types, is_protocol, acc) do
    clauses = types
    |> Stream.with_index()
    |> Enum.map(fn({type, line}) ->
      type.__multix_clause__()
      |> put_elem(1, line)
    end)

    acc = [{:function, line, :impl_for, 1, clauses} | acc]

    change_impl_for(t, protocol, types, is_protocol, acc)
  end
  defp change_impl_for([h | t], protocol, types, is_protocol, acc) do
    change_impl_for(t, protocol, types, is_protocol, [h | acc])
  end

  # Finally compile the module and emit its bytecode.
  defp compile({protocol, code}, types, docs) do
    opts = if Code.compiler_options[:debug_info], do: [:debug_info], else: []
    {:ok, ^protocol, binary, warnings} = :compile.forms(code, [:return | opts])
    if length(warnings) > 0, do: format_warning(protocol, warnings, types)
    {:ok,
      case docs do
        :missing_chunk -> binary
        _ -> :elixir_module.add_beam_chunk(binary, @docs_chunk, docs)
      end}
  end

  defp format_warning(name, [{_file, warnings}], types) do
    lines = warnings
    |> Stream.map(fn({idx, _, _}) ->
      {idx, true}
    end)
    |> Enum.into(%{})

    patterns = types
    |> Stream.with_index()
    |> Stream.map(fn({type, idx}) ->
      prefix = if lines[idx], do: [:red, ">"], else: " "
      %{pattern_s: pattern_s, file: file, line: line, index: index} = type.__multix_info__
      file =  Path.relative_to_cwd(file)
      location = Exception.format_file_line(file, line)

      ["  ", location, " ", inspect(index: index), "\n  ", prefix, " ", pattern_s, "  "]
      |> IO.ANSI.format()
    end)
    |> Enum.join("\n")

    :elixir_errors.warn("""
    #{inspect(name)} has unreachable dispatch patterns:

    #{patterns}

      This can be fixed by reordering the dispatches with the index option.
    """ |> String.trim)
  end
end
