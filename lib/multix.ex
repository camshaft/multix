defmodule Multix do
  defmacro __using__(_) do
    quote do
      import Multix, only: [defmulti: 2, defdispatch: 3]
    end
  end

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

  @doc """
  Checks if the given module is loaded and is protocol.
  Returns `:ok` if so, otherwise raises `ArgumentError`.
  """
  @spec assert_multi!(module) :: :ok | no_return
  def assert_multi!(module) do
    assert_multi!(module, "")
  end

  defp assert_multi!(module, extra) do
    case Code.ensure_compiled(module) do
      {:module, ^module} -> :ok
      _ -> raise ArgumentError, "#{inspect module} is not available" <> extra
    end

    try do
      module.__multix__(:module)
    rescue
      UndefinedFunctionError ->
        raise ArgumentError, "#{inspect module} is not a protocol" <> extra
    end

    :ok
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
