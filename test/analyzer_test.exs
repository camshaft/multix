defmodule Test.Multix.Analyzer do
  use ExUnit.Case

  defmacrop sort([{:do, clauses} | rest]) do
    env =
      __CALLER__
      |> Map.take([
        :file,
        :aliases,
        :requires,
        :functions,
        :macros
      ])
      |> Enum.to_list()

    quote do
      unquote(compile(clauses, env))
      |> Stream.map(&{&1, Multix.Analyzer.analyze(&1)})
      |> Multix.Sorter.sort(__ENV__.function)
    end
    |> compile_assertions(rest, env)
  end

  defp compile(clauses, env) do
    clauses =
      Macro.prewalk(clauses, fn
        {type, meta, args} ->
          {type, Keyword.delete(meta, :line), args}

        node ->
          node
      end)

    fun =
      {:fn, [], clauses}
      |> Code.eval_quoted([], env)
      |> elem(0)

    {_, [{_, _, _, clauses}]} = :erlang.fun_info(fun, :env)

    clauses
    |> Macro.escape()
  end

  defp compile_assertions(ast, [after: clauses], env) do
    quote do
      actual = unquote(ast)
      expected = unquote(compile(clauses, env))
      assert actual == expected
      actual
    end
  end

  defp compile_assertions(ast, [rescue: true], _env) do
    quote do
      assert %Multix.ConflictError{} = catch_error(unquote(ast))
    end
  end

  defp compile_assertions(ast, [], _) do
    ast
  end

  test "literals" do
    sort do
      1 -> 1
      "foo" -> 2
      1.2 -> 3
      :foo -> 4
      "testing" -> 5
    after
      "testing" -> 5
      "foo" -> 2
      :foo -> 4
      1.2 -> 3
      1 -> 1
    end
  end

  test "tuples" do
    sort do
      {:foo, 1} -> 1
      {:bar} -> 2
      {:foo, 2} -> 3
    after
      {:foo, 2} -> 3
      {:foo, 1} -> 1
      {:bar} -> 2
    end
  end

  test "tuple vars" do
    sort do
      {:a, :b, :c} -> 1
      {_, _, _} -> 2
      {:a, _, _} -> 3
      {:a, :b, _} -> 4
      {_, :b, _} -> 5
      {_, _, :c} -> 6
    after
      {:a, :b, :c} -> 1
      {:a, :b, _} -> 4
      {:a, _, _} -> 3
      {_, :b, _} -> 5
      {_, _, :c} -> 6
      {_, _, _} -> 2
    end
  end

  test "list" do
    sort do
      [] -> 1
      [a, b] -> 2
      [foo | rest] -> 3
    after
      [a, b] -> 2
      [foo | rest] -> 3
      [] -> 1
    end
  end

  defmodule Foo do
    defstruct [:name, :age]
  end

  defmodule Bar do
    defstruct [:name]
  end

  test "structs" do
    sort do
      %Foo{} -> 1
      %Foo{name: _} -> 2
      %Bar{name: _} -> 3
      %Foo{age: _} -> 4
    after
      %Foo{name: _} -> 2
      %Bar{name: _} -> 3
      %Foo{age: _} -> 4
      %Foo{} -> 1
    end
  end

  test "guards" do
    sort do
      a when is_integer(a) -> 1
      b when is_list(b) -> 2
      c when is_tuple(c) -> 3
      d when is_boolean(d) -> 4
    after
      b when is_list(b) -> 2
      c when is_tuple(c) -> 3
      d when is_boolean(d) -> 4
      a when is_integer(a) -> 1
    end
  end

  test "conflicts" do
    sort do
      "foo" -> 1
      "foo" -> 2
    rescue
      true
    end
    |> Exception.message()
    |> IO.puts()
  end
end
