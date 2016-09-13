defmodule Multix do
  defmacro defmulti(name, body) do
    __MODULE__.Multi.compile(name, body)
  end

  defmacro defdispatch(name, pattern, body) do
    __MODULE__.Dispatch.compile(name, pattern, body)
  end
end

# this is just for tests so we can make sure it pulls things from the path
if Mix.env == :test do
  defmodule FooContainer do
    import Multix

    defdispatch Foo, for: :test do
      def test(_) do
        :ITS_A_TEST
      end
    end
  end
end
