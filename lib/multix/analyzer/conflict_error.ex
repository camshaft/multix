defmodule Multix.Analyzer.ConflictError do
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

  def erl_to_ex({type, _, v}) when type in [:integer, :atom, :float] do
    v
  end

  def erl_to_ex({:bin, _, [{:bin_element, _, {:string, _, s}, _, _}]}) do
    to_string(s)
  end
end
