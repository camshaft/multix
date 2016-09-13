defmodule Multix do
  defmacro defmulti(name, body) do
    {name, _} = Code.eval_quoted(name, [], __CALLER__)
    __MODULE__.Multi.compile(name, body)
  end

  defmacro defdispatch(name, pattern, body) do
    {name, _} = Code.eval_quoted(name, [], __CALLER__)
    __MODULE__.Dispatch.compile(name, pattern, body)
  end

  def consolidated?(type) do
    type.__multix__(:consolidated?)
  end
end

# this is just for tests so we can make sure it pulls things from the path
if Mix.env == :test do
  defmodule FooContainer do
    import Multix

    defmulti Elixir.Foo do
      def test(value)
    end

    defdispatch Elixir.Foo, for: :test do
      def test(_) do
        :ITS_A_TEST
      end
    end
  end
end
