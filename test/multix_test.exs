use Multix

defmodule Foo do
  defmulti test(t)
  defmulti test(1) do
    :ONE
  end

  def not_multimethod(value) do
    value
  end
end

defmodule Bar do
  defmulti Foo.test(2) do
    :TWO
  end
end

defmodule Baz do
  import Foo
  defmulti test(3) do
    :THREE
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

defmodule Test.Multix do
  use ExUnit.Case

  test "consolidation" do
    assert Multix.consolidated?(&Foo.test/1) == false
    assert Multix.consolidated?({Foo, :test, 1}) == false
    assert Multix.consolidated?(Foo, :test, 1) == false
  end

  test "multi dispatch" do
    Multix.inspect_multi(Foo, :test, 1)
    |> :forms.from_abstract
    |> IO.puts
    assert Foo.test(1) == :ONE
    assert Foo.test(2) == :TWO
    assert Foo.test(3) == :THREE
    assert Foo.test(:FOUR) == :FOUR
    assert Foo.test(:anon) == :IT_WORKED!
    assert Foo.test(%{value: 4}) == 8
    assert Foo.test(%{value: :foo}) == :foo
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
end
