defmodule Multix.Analyzer do
  @moduledoc false

  def analyze({:clause, _line, args, clauses, _body}, opts \\ %{}) do
    assertions = analyze_clause(clauses)
    type = analyze_type(args, assertions)
    # TODO analyze body for anything that could throw and mark pure?: true
    pure? = false
    vars = []

    Map.merge(opts, %{
      type: type,
      vars: vars,
      pure?: pure?
    })
  end

  defp analyze_clause(clause, arg_assertions \\ nil, logic \\ :and, assertions \\ %{})

  defp analyze_clause([], _, _, acc), do: acc

  defp analyze_clause(clauses, arg_assertions, logic, acc) when is_list(clauses) do
    clauses
    |> Stream.zip(arg_assertions || Stream.cycle([nil]))
    |> Enum.reduce(acc, fn {clause, arg_assertion}, acc ->
      analyze_clause(clause, arg_assertion, logic, acc)
    end)
  end

  defp analyze_clause({:var, _, name}, assertions, logic, acc) do
    Map.update(acc, name, assertions, &Map.merge(&1, assertions))
  end

  Multix.Sorter.Bif.get()
  |> Enum.each(fn {{f, a}, arg_assertions} ->
    acc = Macro.var(:acc, nil)
    logic = Macro.var(:logic, nil)
    arg_vars = Macro.generate_arguments(a, nil)

    match =
      quote do
        {:call, _, {:remote, _, _module, {:atom, _, unquote(f)}}, unquote(arg_vars)}
      end

    calls =
      arg_vars
      |> Stream.zip(arg_assertions)
      |> Enum.map(fn {var, assertions} ->
        assertions = assertions |> Enum.into(%{}) |> Macro.escape()

        quote do
          unquote(acc) =
            analyze_clause(unquote(var), unquote(assertions), unquote(logic), unquote(acc))
        end
      end)

    defp analyze_clause(unquote(match), _assertions, unquote(logic), unquote(acc)) do
      unquote_splicing(calls)
      unquote(acc)
    end
  end)

  defp analyze_type({:var, _, name}, assertions) do
    case Map.fetch(assertions, name) do
      {:ok, a} ->
        {:guarded_var, {name, a}}

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
    {:map,
     fields
     |> Stream.map(fn {:map_field_exact, _, key, value} ->
       {:tuple, [analyze_type(key, assertions), analyze_type(value, assertions)]}
     end)
     |> Enum.sort(fn a, b ->
       try do
         Multix.Sorter.sort_type(a, b)
       catch
         :equal ->
           true
       end
     end)}
  end

  defp analyze_type({:tuple, _, elements}, assertions) do
    {:tuple, analyze_type(elements, assertions)}
  end

  defp analyze_type({nil, _}, _assertions) do
    {:list, []}
  end

  defp analyze_type({:cons, _, head, tail}, assertions) do
    head = analyze_type(head, assertions)

    case analyze_type(tail, assertions) do
      {:list, tail} ->
        {:list, [head | tail]}

      other ->
        {:list, [head | other]}
    end
  end

  defp analyze_type({:match, _, lhs, rhs}, a) do
    case {analyze_type(lhs, a), analyze_type(rhs, a)} do
      {{:literal, _} = l, _} ->
        l

      {_, {:literal, _} = l} ->
        l

      {a, b} ->
        {:match, [a, b]}
    end
  end

  defp analyze_type({:bin, _, [{:bin_element, _, {:string, _, s}, _, _}]}, _) do
    {:literal, to_string(s)}
  end

  defp analyze_type({:bin, _, elements}, a) do
    {elements, size} =
      Enum.map_reduce(elements, [], fn
        {:bin_element, _, {:string, _, s}, _, _}, sizes ->
          s = to_string(s)
          {{:literal, s}, [byte_size(s) | sizes]}

        {:bin_element, _, {:var, _, _} = v, :default, [:binary]}, sizes ->
          {analyze_type(v, a), [:_ | sizes]}
      end)

    {:binary, {size, elements}}
  end

  defp analyze_type(list, assertions) when is_list(list) do
    Enum.map(list, &analyze_type(&1, assertions))
  end
end
