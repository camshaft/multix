defmodule Multix.Compiler do
  def defmulti({_, _, []}) do
    raise ArgumentError, "Cannot define 0 arity multimethods"
  end
  def defmulti(mfa) do
    quote bind_quoted: [
      mfa: {:quote, [], [[do: mfa]]}
    ], context: __MODULE__.DEF do
      {name, _, args} = mfa

      def unquote(name)(unquote_splicing(args))

      require Multix.Compiler
      Multix.Compiler.__define__(name, args)
    end
  end

  def defmulti(name, body, opts) do
    compile(name, body, opts)
  end

  defmacro __define__(name, args) do
    quote bind_quoted: [
      name: name,
      args: args
    ], context: __MODULE__.DEFINE do

      {args, arity} =
        args
        |> Stream.with_index()
        |> Enum.map_reduce(0, fn
          ({{name, _, nil} = var, idx}, _) when is_atom(name) ->
            {var, idx}
          ({_, idx}, _) ->
            {Macro.var(:"arg#{idx}", nil), idx}
        end)
      arity = arity + 1

      use Elixir.Multix.Dispatch, function: name, arity: arity

      def unquote(name)(unquote_splicing(args)) do
        @multix_dispatch.dispatch(unquote(name), unquote({:{}, [], args}))
      end

      def __multix__({unquote(name), unquote(arity)}), do: true
    end
  end

  defp compile({:when, _meta, [fun, clause]}, body, opts) do
    compile(fun, clause, body, opts)
  end
  defp compile(fun, body, opts) do
    compile(fun, true, body, opts)
  end

  defp compile(mfa, clause, body, opts) do
    quote bind_quoted: [
      mfa: {:quote, [], [[do: mfa]]},
      local?: mfa |> elem(0) |> is_atom(),
      clause: {:quote, [], [[do: clause]]},
      body: {:quote, [], [[do: body]]},
      opts: {:quote, [], [[do: opts]]}
    ], context: __MODULE__.DEFMULTI do
      env = __ENV__
      {m,f,args,a} = Multix.Compiler.resolve_name(mfa, env)
      m = Multix.Compiler.normalize_name(m, f, a, local?, env)

      cond do
        __MODULE__ != m ->
          Multix.Compiler.ensure_multix(m,f,a)
        !Module.defines?(__MODULE__, {f,a}, :def) ->
          require Multix.Compiler
          Multix.Compiler.__define__(f, args)
        true ->
          # same module; already defined
          :ok
      end

      key = :"Multix.#{inspect(m)}.#{f}/#{a}"
      name = :"__#{key}_#{:erlang.phash2({args, clause})}__"

      args_list = Multix.Compiler.put_impl(key, name, args, clause, opts, env)
      body = Multix.Compiler.assign_blank_variables(args_list, body)

      use Multix.Cache, key: key
      def unquote(name)(unquote_splicing(args_list)), unquote(body)
    end
  end

  def resolve_name({{:., _, [module, fun]}, _, args}, env) do
    {Macro.expand(module, env), fun, args, length(args)}
  end
  def resolve_name({name, _, args}, %{module: module}) when is_atom(name) do
    {module, name, args, length(args)}
  end

  def normalize_name(module, _function, _arity, false, _caller) do
    module
  end
  def normalize_name(_module, function, arity, true, caller) do
    caller.functions
    |> resolve_import({function, arity}, caller.module)
  end

  defp resolve_import([], _fa, m) do
    m
  end
  defp resolve_import([{module, funs} | rest], fa, m) do
    if Enum.any?(funs, &(&1 == fa)) do
      module
    else
      resolve_import(rest, fa, m)
    end
  end

  def ensure_multix(m, f, a) do
    Code.ensure_compiled(m)

    if !function_exported?(m,f,a) do
      raise UndefinedFunctionError, [
        module: m,
        function: f,
        arity: a,
        reason: "required for multimethod extension"
      ]
    end

    try do
      m.__multix__({f, a})
    rescue
      _ ->
        raise ArgumentError, "#{
          Exception.format_mfa(m,f,a)
        } isn't exposed as a multimethod"
    end
  end

  def put_impl(key, name, args, clause, opts, caller) do
    {clause, args_list} = compile_clause(name, args, clause, caller)
    analysis = Multix.Analyzer.analyze(clause, caller, opts[:priority])
    acc_attribute(caller, key, {analysis, clause})
    args_list
  end

  defp compile_clause(fun_name, args, clause, %{module: m} = caller) do
    args_list = extract_args(args)
    fun = quote do
      fn(unquote({:{}, [], args})) when unquote(clause) ->
        {unquote(m), unquote(fun_name), unquote(args_list)}
      end
    end
    |> Code.eval_quoted([], caller)
    |> elem(0)

    {_, [{_, _, _, [clause]}]} = :erlang.fun_info(fun, :env)

    clause = case clause do
      {:clause, line, args, [[{:atom, _, true}]], body} ->
        {:clause, line, args, [], body}
      c ->
        c
    end

    {clause, args_list}
  end

  defp extract_args(args) do
    Macro.prewalk(args, [], fn
      ({name, _, _} = other, acc) when name in [:__MODULE__, :__ENV__] ->
        {other, acc}
      ({name, _, context} = var, acc) when is_atom(name) and is_atom(context) ->
        {var, [var | acc]}
      (other, acc) ->
        {other, acc}
    end)
    |> elem(1)
  end

  defp acc_attribute(%{module: m}, name, value) do
    prev = case Module.get_attribute(m, name) do
      nil ->
        Module.register_attribute(m, name, persist: true)
        []
      prev ->
        prev
    end

    Module.put_attribute(m, name, [value | prev])
  end

  def assign_blank_variables(args_list, [{:do, {:__block__, meta, b}} | body]) do
    b = Enum.reduce(args_list, b, fn(arg, acc) ->
      [quote(do: _ = unquote(arg)) | acc]
    end)
    [{:do, {:__block__, meta, b}} | body]
  end
  def assign_blank_variables(args_list, [{:do, b} | rest]) do
    assign_blank_variables(args_list, [{:do, {:__block__, [], [b]}} | rest])
  end
end
