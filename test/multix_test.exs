use Multix

defmodule Foo do
  defmulti test(t \\ :DEFAULT)
  defmulti test(1) do
    :ONE
  end

  def not_multimethod(value) do
    value
  end
end

defmodule Bar do
  defmulti Foo.test(2 = _) do
    :TWO
  end
end

defmodule Baz do
  alias Foo, as: F
  import Foo
  defmulti test(3 = _three) do
    :THREE
  end

  defmulti F.test(:alias) do
    :ALIAS
  end
end

defmodule Other do
  defmulti Foo.test(%{value: 3 = num}) do
    num / 3
  end
  defmulti Foo.test(%{value: num}) when is_number(num) do
    num * 2
  end
  defmulti Foo.test(%{value: num}) when is_atom(num) do
    num
  end
end

defmodule FallThrough do
  defmulti Foo.test(other) do
    other
  end
end

defmulti Foo.test(:anon) do
  :IT_WORKED!
end

defmulti Foo.test("foo"), do: :foo
defmulti Foo.test("bar"), do: :bar
defmulti Foo.test("b" <> ar), do: ar
defmulti Foo.test("f" <> oo), do: oo
defmulti Foo.test("ba" <> r), do: r
defmulti Foo.test("fo" <> o), do: o

defmodule MyStruct do
  defstruct [:value]

  defmulti Foo.test(%__MODULE__{value: value}) do
    value
  end
end

defmodule UnquoteTest do
  for value <- [:meta_1, :meta_2] do
    defmulti Foo.test(unquote(value)), do: true
  end

  method = :test
  defmulti Foo.unquote(method)(:meta_3), do: false
end

defmodule Test.Multix do
  use ExUnit.Case

  test "consolidation" do
    assert Multix.consolidated?(&Foo.test/1) == false
    assert Multix.consolidated?({Foo, :test, 1}) == false
    assert Multix.consolidated?(Foo, :test, 1) == false
  end

  test "multi dispatch" do
    Multix.inspect_multi(Foo, :test, 1)
    # |> IO.puts
    assert Foo.test() == :DEFAULT
    assert Foo.test(1) == :ONE
    assert Foo.test(2) == :TWO
    assert Foo.test(3) == :THREE
    assert Foo.test(:FOUR) == :FOUR
    assert Foo.test(:anon) == :IT_WORKED!
    assert Foo.test(%{value: 4}) == 8
    assert Foo.test(%{value: :foo}) == :foo

    assert Foo.test("foo") == :foo
    assert Foo.test("bar") == :bar
    assert Foo.test("ba1") == "1"
    assert Foo.test("fo2") == "2"
    assert Foo.test("b3") == "3"
    assert Foo.test("f3") == "3"

    assert Foo.test(:alias) == :ALIAS
    assert Foo.test(%MyStruct{value: :THING}) == :THING
    assert Foo.test(:meta_1) == true
    assert Foo.test(:meta_2) == true
    assert Foo.test(:meta_3) == false
  end

  test "undefined function" do
    assert_raise UndefinedFunctionError, fn ->
      defmulti Bar.test(:thing) do
        :doesnt_work
      end
    end
  end

  test "not exposed" do
    assert_raise ArgumentError, fn ->
      defmulti Foo.not_multimethod(:other_thing) do
        :doesnt_work
      end
    end
  end

  test "cache purging" do
    defmodule T do
      defmulti foo(a)
    end

    defmulti T.foo(2), do: 4
    assert T.foo(2) == 4

    defmulti T.foo(3), do: 6
    assert T.foo(3) == 6
  end
end
