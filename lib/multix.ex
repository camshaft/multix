defmodule Multix do
  @moduledoc """

  ## Examples

  Start by defining a multimethod inside a module.

      defmodule Math do
        def add(_, _) do
          throw :not_implemented
        end
      end

  Implementations can now be added to `Math.add/2` with `defmulti/3`.

      defmodule Math.Integer do
        use Multix

        defmulti Math.add(a, b) when is_integer(a) and is_integer(b) do
          a + b
        end
      end

  `Math.add/2` can now compute integer addition.

      iex> Math.add(1, 2)
      3

  More complex types can also be added.

      defmodule MyStruct do
        use Multix

        defstruct [:count]

        defmulti Math.add(%__MODULE__{count: a}, b) do
          %__MODULE__{count: Math.add(a, b)}
        end
        defmulti Math.add(a, %__MODULE__{count: b}) do
          Math.add(a, b)
        end
      end

  `Math.add/2` now is aware of %MyStruct{} addition.

      iex> Math.add(%MyStruct{count: 1}, %MyStruct{count: 2})
      %MyStruct{count: 3}

      iex> Math.add(%MyStruct{count: 2}, 3)
      %MyStruct{count: 5}
  """

  defmacro __using__(_) do
    quote do
      import Multix, only: [defmulti: 2, defmulti: 3]
      @compile :debug_info
    end
  end

  @doc """
  Defines a multidispatch function implementation.
  """

  defmacro defmulti(name, opts \\ [], body) do
    __MODULE__.Compiler.defmulti(name, body, opts)
  end

  @doc """
  Returns true if the multimethod module was consolidated.
  """

  def consolidated?(module) when is_atom(module) do
    function_exported?(module, :__multix__, 1)
  end

  def consolidated?(mfa) do
    {m, _f, _a} = normalize_method(mfa)
    consolidated?(m)
  end

  @doc """
  Returns true if the multimethod was consolidated.
  """

  def consolidated?(module, function, arity) do
    _ = function
    _ = arity
    consolidated?(module)
  end

  @doc """
  Returns `{module, function, arguments}` for a multimethod.
  """

  def impl_for(module, function, arity, args) when is_list(args) do
    impl_for(module, function, arity, :erlang.list_to_tuple(args))
  end

  def impl_for(module, function, arity, args) when is_tuple(args) and arity == tuple_size(args) do
    module.__multix_dispatch__.impl_for(function, args)
  end

  @doc """
  Inspects the generated erlang code for the multimethod dispatcher.
  """

  def inspect_multi(mfa) do
    {m, f, a} = normalize_method(mfa)
    inspect_multi(m, f, a)
  end

  @doc """
  Inspects the generated erlang code for the multimethod dispatcher.
  """

  def inspect_multi(module, function, arity) do
    module.__multix_dispatch__.inspect(function, arity)
  end

  defp normalize_method({m, f, a}) do
    {m, f, a}
  end

  defp normalize_method(fun) when is_function(fun) do
    case :erlang.fun_info(fun) do
      [module: m, name: f, arity: a, env: _, type: :external] ->
        {m, f, a}

      _ ->
        raise ArgumentError, "#{inspect(fun)} not a multimethod"
    end
  end
end
