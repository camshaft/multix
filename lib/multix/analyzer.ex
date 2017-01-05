defmodule Multix.Analyzer do
  @moduledoc false

  def sort(impls, _module) do
    impls
    |> Enum.sort(&sort_analysis/2)
    |> Enum.map(&elem(&1, 1))
  end

  defp sort_analysis({{{_, a_l}, p, m, _}, _},
                     {{{_, b_l}, p, m, _}, _}) do
    # Sort clauses in the same module by line
    a_l <= b_l
  end
  defp sort_analysis({{a_fl, p, _, a}, _},
                     {{b_fl, p, _, b}, _}) do
    try do
      sort_type(a, b)
    catch
      :equal ->
        IO.puts "CONFLICT #{inspect(a_fl)} <> #{inspect(b_fl)}"
        false
    end
  end
  defp sort_analysis({{_, a_p, _, _}, _},
                     {{_, b_p, _, _}, _}) do
    # Sort prioritized patterns
    a_p <= b_p
  end

  defp sort_type({:literal, a}, {:literal, a}), do: throw :equal
  defp sort_type({:literal, a}, {:literal, b}), do: a >= b
  defp sort_type({:literal, _}, _            ), do: true
  defp sort_type(_,             {:literal, _}), do: false
  defp sort_type({:var, _},     {:var, _}    ), do: throw :equal
  defp sort_type({:var, _},     _            ), do: false
  defp sort_type(_,             {:var, _}    ), do: true
  defp sort_type([],            []           ), do: throw :equal
  defp sort_type([a | a_r],     [b | b_r]    ) do
    sort_type(a, b)
  catch
    :equal ->
      sort_type(a_r, b_r)
  end
  defp sort_type({:bin, s, a_els}, {:bin, s, b_els}) do
    a_els <= b_els
  end
  defp sort_type({:bin, a_s, _}, {:bin, b_s, _}) do
    a_s >= b_s
  end
  defp sort_type({:bin, _, _},   _           ), do: true
  defp sort_type(_,              {:bin, _, _}), do: false
  defp sort_type(a,             b            ) when is_map(a) and is_map(b) do
    map_size(a) >= map_size(b)
  end
  defp sort_type(a, b) do
    IO.puts "UNHANDLED COMPARISON:"
    IO.inspect a
    IO.inspect b

    false
  end

  def analyze({:clause, line, [{:tuple, _, args}], clauses, _body}, caller, priority) do
    assertions = analyze_clause(clauses, %{})
    %{file: file, module: module} = caller
    case analyze_type(args, assertions) do
      {:var, _} = var ->
        # Demote standalone variables
        {{file, line}, priority || -100, module, var}
      analysis ->
        {{file, line}, priority || 0, module, analysis}
    end
  end

  bifs = [
    :atom, :binary, :bitstring, :boolean, :float, :function, :integer, :list,
    :map, :number, :pid, :port, :process_alive, :record, :reference, :tuple
  ]

  for t <- bifs do
    defp analyze_clause({:call, _, {:remote, _, _, {:atom, _, unquote(:"is_#{t}")}},
                            [{:var, _, var}]}, acc) do
      assertion = unquote([t] |> MapSet.new() |> Macro.escape())
      Map.update(acc, var, assertion, &(MapSet.union(&1, assertion)))
    end
  end
  defp analyze_clause(l, acc) when is_list(l) do
    Enum.reduce(l, acc, &analyze_clause/2)
  end
  defp analyze_clause({:atom, _, _}, acc) do
    acc
  end
  defp analyze_clause(other, acc) do
    IO.inspect other
    acc
  end

  defp analyze_type({:var, _, name}, assertions) do
    case Map.fetch(assertions, name) do
      {:ok, a} ->
        {:guarded_var, name, MapSet.to_list(a)}
      _ ->
        {:var, name}
    end
  end
  defp analyze_type({type, _, v}, _) when type in [:integer, :atom, :float] do
    {:literal, v}
  end
  defp analyze_type({:map, _, []}, _) do
    {:literal, %{}}
  end
  defp analyze_type({:map, _, fields}, assertions) do
    fields
    |> Stream.map(fn({:map_field_exact, _, key, value}) ->
      {analyze_type(key, assertions), analyze_type(value, assertions)}
    end)
    |> Enum.into(%{})
  end
  defp analyze_type({:tuple, _, elements}, assertions) do
    {:tuple, analyze_type(elements, assertions)}
  end
  defp analyze_type({:match, _, lhs, rhs}, a) do
    case {analyze_type(lhs, a), analyze_type(rhs, a)} do
      {{:literal, _} = l, _} ->
        l
      {_, {:literal, _} = l} ->
        l
      {a, b} ->
        {:union, a, b}
    end
  end
  defp analyze_type({:bin, _, [{:bin_element, _, {:string, _, s}, _, _}]}, _) do
    {:literal, to_string(s)}
  end
  defp analyze_type({:bin, _, elements}, a) do
    {elements, size} = Enum.map_reduce(elements, 0, fn
      ({:bin_element, _, {:string, _, s}, _, _}, size) ->
        s = to_string(s)
        {{:literal, s}, size + byte_size(s)}
      ({:bin_element, _, {:var, _, _} = v, :default, [:binary]}, size) ->
        {analyze_type(v, a), size}
    end)
    {:bin, size, elements}
  end
  defp analyze_type(list, assertions) when is_list(list) do
    Enum.map(list, &analyze_type(&1, assertions))
  end
end
