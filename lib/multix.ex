defmodule Multix do
  defmacro __using__(_) do
    quote do
      import Multix, only: [defmulti: 1, defmulti: 2, defmulti: 3]
    end
  end

  defmacro defmulti(name) do
    case __CALLER__ do
      %{module: mod, function: fun} = caller when is_nil(mod) or not is_nil(fun) ->
        define_anonymous(name, [], caller, quote do
          defmulti unquote(name)
        end)
      caller ->
        __MODULE__.Compiler.defmulti(name, caller)
    end
  end

  defmacro defmulti(name, opts \\ [], body) do
    case __CALLER__ do
      %{module: mod, function: fun} = caller when is_nil(mod) or not is_nil(fun) ->
        define_anonymous(name, [], caller, quote do
          defmulti unquote(name), unquote(opts), unquote(body)
        end)
      caller ->
        __MODULE__.Compiler.defmulti(name, body, opts, caller)
    end
  end

  defp define_anonymous(name, opts, caller, body) do
    id = :erlang.phash2({name, opts, body})
    mod = Module.concat(["Multix", "Anonymous#{id}"])
    quote do
      defmodule unquote(mod) do
        use Multix
        unquote(body)
      end
      unquote(mod)
    end
    |> maybe_iex(caller)
  end

  defp maybe_iex(ast, %{module: nil, function: nil, file: "iex"} = caller) do
    {mod, _} = Code.eval_quoted(ast, [], caller)
    quote do
      import unquote(mod)
      unquote(mod)
    end
  end
  defp maybe_iex(ast, _) do
    ast
  end

  def consolidated?(mfa) do
    {m,f,a} = normalize_method(mfa)
    consolidated?(m,f,a)
  end
  def consolidated?(m, _f, _a) do
    m.__multix_dispatch__.consolidated?()
  end

  def impl_for?(mfa, args) do
    {m, f, a} = normalize_method(mfa)
    impl_for?(m, f, a, args)
  end
  def impl_for?(m, f, a, args) when is_list(args) do
    impl_for?(m, f, a, :erlang.list_to_tuple(args))
  end
  def impl_for?(m, f, a, args) when is_tuple(args) and a == tuple_size(args) do
    m.__multix_dispatch__.impl_for?(f, a, args)
  end

  def inspect_multi(mfa) do
    {m,f,a} = normalize_method(mfa)
    inspect_multi(m, f, a)
  end
  def inspect_multi(m, f, a) do
    m.__multix_dispatch__.inspect(f, a)
  end

  defp normalize_method({m, f, a}) do
    {m, f, a}
  end
  defp normalize_method(fun) when is_function(fun) do
    case :erlang.fun_info(fun) do
      [module: m, name: f, arity: a, env: _, type: :external] ->
        {m,f,a}
      _ ->
        raise ArgumentError, "#{inspect(fun)} not a multimethod"
    end
  end
end
