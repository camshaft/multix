defmodule Multix.ConflictError do
  defexception [:a, :b, :fa]

  def message(%{fa: {f, _}, a: a, b: b}) do
    str =
      [
        erl_to_ex(a),
        erl_to_ex(b)
      ]
      |> Stream.map(fn {:->, meta, [args, body]} ->
        {:def, [import: Kernel],
         [
           [{f, meta, args}],
           [do: body]
         ]}
      end)
      |> Stream.map(&Macro.to_string/1)
      |> Enum.join("\n")

    """
    Multix methods conflict

    #{str}
    """
  end

  def message(%{a: a, b: b}) do
    str =
      {:fn, [],
       [
         erl_to_ex(a),
         erl_to_ex(b)
       ]}
      |> Macro.to_string()

    """
    Multix methods conflict

    #{str}
    """
  end

  def erl_to_ex(items) when is_list(items) do
    Enum.map(items, &erl_to_ex/1)
  end

  def erl_to_ex({:clause, line, args, conditions, body}) do
    args = erl_to_ex(args)

    args =
      case conditions do
        [] ->
          args

        _ ->
          # TODO
          args
      end

    {:->, [line: line], [args, {:__block__, [], erl_to_ex(body)}]}
  end

  def erl_to_ex({type, _, v}) when type in [:integer, :atom, :float, :string] do
    v
  end

  def erl_to_ex({:char, _, val}) when is_integer(val) do
    {:"?", [], [val]}
  end

  def erl_to_ex({:bin, _, [{:bin_element, _, {:string, _, s}, _, _}]}) do
    to_string(s)
  end

  def erl_to_ex({:bin, _, elems}) do
    {:<<>>, [], erl_to_ex(elems)}
  end

  def erl_to_ex({:bin_element, _, val, :default, :default}) do
    bin_element_expr(val)
  end

  def erl_to_ex({:bin_element, _, val, size, :default}) do
    ex_val = bin_element_expr(val)
    ex_size = bin_element_size(size, false)
    {:::, [], [ex_val, ex_size]}
  end

  def erl_to_ex({:bin_element, _, val, size, modifiers}) do
    ex_val = bin_element_expr(val)
    ex_size = bin_element_size(size, true)
    ex_modifiers = bin_element_modifier_list(modifiers, ex_size)
    {:::, [], [ex_val, ex_modifiers]}
  end

  def erl_to_ex({nil, _}) do
    []
  end

  def erl_to_ex({:tuple, _, vals}) when is_list(vals) do
    {:{}, [], erl_to_ex(vals)}
  end

  def erl_to_ex({:cons, _, head, tail = {:cons, _, _, _}}) do
    ex_head = erl_to_ex(head)
    ex_tail = erl_to_ex(tail)
    [ex_head | ex_tail]
  end

  def erl_to_ex({:cons, _, head, {nil, _}}) do
    [erl_to_ex(head)]
  end

  def erl_to_ex({:cons, _, head, tail}) do
    ex_head = erl_to_ex(head)
    ex_tail = erl_to_ex(tail)
    [{:|, [], [ex_head, ex_tail]}]
  end

  def erl_to_ex({:var, _, name}) when is_atom(name) do
    name =
      name
      |> to_string()
      |> case do
        "V" <> var -> var
        var -> var
      end
      |> String.replace(~r/\@\d+$/, "")
      |> String.to_atom()

    {name, [], nil}
  end

  def erl_to_ex({:match, _, lhs, rhs}) do
    ex_lhs = erl_to_ex(lhs)
    ex_rhs = erl_to_ex(rhs)
    {:=, [], [ex_lhs, ex_rhs]}
  end

  def erl_to_ex({node_type, _, lhs, rhs}) when node_type in [:map_field_assoc, :map_field_exact] do
    ex_lhs = erl_to_ex(lhs)
    ex_rhs = erl_to_ex(rhs)
    {ex_lhs, ex_rhs}
  end

  def erl_to_ex({:map, _, associations}) do
    {:%{}, [], erl_to_ex(associations)}
  end

  def erl_to_ex({:map, _, base_map, []}) do
    erl_to_ex(base_map)
  end

  def erl_to_ex({:map, _, base_map, assocs}) do
    ex_base_map = erl_to_ex(base_map)
    update_map(ex_base_map, assocs)
  end

  defp update_map(base_map, assocs = [{:map_field_exact, _, _, _} | _]) do
    {exact_assocs, remaining_assocs} =
      assocs
      |> Enum.split_while(fn
        {:map_field_exact, _, _, _} -> true
        _ -> false
      end)

    ex_exact_assocs = erl_to_ex(exact_assocs)
    new_base = {:%{}, [], [{:|, [], [base_map, ex_exact_assocs]}]}
    update_map(new_base, remaining_assocs)
  end

  defp update_map(base_map, []) do
    base_map
  end

  defp bin_element_expr({:string, _, str}) do
    to_string(str)
  end

  defp bin_element_expr(val) do
    erl_to_ex(val)
  end

  defp bin_element_size(:default, _verbose) do
    nil
  end

  defp bin_element_size(size, verbose) do
    ex_size = erl_to_ex(size)

    if verbose or not is_integer(ex_size) do
      {:size, [], [ex_size]}
    else
      ex_size
    end
  end

  defp bin_element_modifier_list([], ex_modifiers) do
    ex_modifiers
  end

  defp bin_element_modifier_list([modifier | tail], nil) do
    ex_modifier = bin_element_modifier(modifier)
    bin_element_modifier_list(tail, ex_modifier)
  end

  defp bin_element_modifier_list([modifier | tail], ex_modifiers) do
    ex_modifier = bin_element_modifier(modifier)
    bin_element_modifier_list(tail, {:-, [], [ex_modifiers, ex_modifier]})
  end

  defp bin_element_modifier({:unit, val}) do
    {:unit, [], [val]}
  end

  defp bin_element_modifier(modifier) do
    {modifier, [], Elixir}
  end
end
