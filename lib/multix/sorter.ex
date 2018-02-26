defmodule Multix.Sorter do
  @moduledoc false

  def sort(impls, fa \\ nil) do
    impls
    |> Enum.sort(&sort_analysis(&1, &2, fa))
    |> Enum.map(&elem(&1, 0))
  end

  defp sort_analysis(
         {_clause_a, %{file: file, line: a}},
         {_clause_b, %{file: file, line: b}},
         _fa
       )
       when a !== b do
    a <= b
  end

  defp sort_analysis({_clause_a, %{priority: a}}, {_clause_b, %{priority: b}}, _fa) when a !== b do
    a <= b
  end

  defp sort_analysis(
         {clause_a, %{type: a}},
         {clause_b, %{type: b}},
         fa
       ) do
    try do
      sort_type(a, b)
    catch
      :equal ->
        raise Multix.ConflictError, a: clause_a, b: clause_b, fa: fa
    end
  end

  def sort_type({:literal, a}, {:literal, b}) when a !== b, do: a >= b

  def sort_type({:guarded_var, {_, a}}, {:guarded_var, {_, b}}) do
    sort_assertions(a, b)
  end

  def sort_type([], []), do: throw(:equal)
  def sort_type([], _), do: false
  def sort_type(_, []), do: true

  def sort_type([a | a_r], [b | b_r]) do
    sort_type(a, b)
  catch
    :equal ->
      sort_type(a_r, b_r)
  end

  def sort_type(a, b) when is_list(a) do
    sort_type({:list, a}, b)
  end

  def sort_type(a, b) when is_list(b) do
    sort_type(a, {:list, b})
  end

  def sort_type({:binary, {s, a_els}}, {:binary, {s, b_els}}) do
    sort_type(a_els, b_els)
  end

  def sort_type({:binary, {a_s, _}}, {:binary, {b_s, _}}) do
    a_s >= b_s
  end

  def sort_type({:tuple, a}, {:tuple, b}) do
    sort_type(a, b)
  end

  def sort_type({:list, a}, {:list, b}) do
    sort_type(a, b)
  end

  ## TODO show potential warnings with maps
  def sort_type({:map, a}, {:map, b}) do
    sort_type(a, b)
  end

  def sort_type({:match, a}, {:match, b}) do
    a =
      try do
        Enum.sort(a, &sort_type/2)
      catch
        :equal ->
          a
      end

    b =
      try do
        Enum.sort(b, &sort_type/2)
      catch
        :equal ->
          b
      end

    sort_type(a, b)
  end

  def sort_type({:match, a}, b) do
    sort_type(a, [b])
  end

  def sort_type(a, {:match, b}) do
    sort_type([a], b)
  end

  def sort_type({:var, :_}, {:var, b}) when b !== :_ do
    false
  end

  def sort_type({:var, a}, {:var, :_}) when a !== :_ do
    true
  end

  def sort_type({a, _}, {a, _}), do: throw(:equal)
  def sort_type({a, _}, {b, _}), do: __MODULE__.Bif.compare_type(a, b)

  defp sort_assertions(a, a), do: throw(:equal)

  defp sort_assertions(%{type: a}, %{type: b}) when a !== b do
    __MODULE__.Bif.compare_type(a, b)
  end
end
