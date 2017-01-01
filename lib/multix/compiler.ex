defmodule Multix.Compiler do
  def defmulti({_, _, args} = name, caller) do
    name
    |> compile_name(caller)
    |> init(args, caller)
  end

  def defmulti(name, body, opts, caller) do
    compile(name, body, opts, caller)
  end

  defp compile({:when, _meta, [fun, clause]}, body, opts, caller) do
    compile(fun, clause, body, opts, caller)
  end
  defp compile(fun, body, opts, caller) do
    compile(fun, true, body, opts, caller)
  end

  defp compile({_, _, args} = fun, clause, body, opts, caller) do
    mfa = compile_name(fun, caller)
    {:__block__, [], [
      init(mfa, args, caller),
      register(mfa, args, clause, body, opts, caller)
    ]}
  end

  defp init({m, f, a}, args, %{module: m}) do
    fa = {f,a}
    dispatch_args = Enum.map(1..a, &Macro.var(:"@arg#{&1}", nil))

    quote do
      if !Module.defines?(__MODULE__, unquote(fa), :def) do
        Kernel.def unquote(f)(unquote_splicing(init_args(args)))

        use Elixir.Multix.Dispatch, unquote(module: m, function: f, arity: a)

        Kernel.def unquote(f)(unquote_splicing(dispatch_args)) do
          @multix_dispatch.dispatch(unquote(f), unquote({:{}, [], dispatch_args}))
        end

        Kernel.def __multix__(unquote(f), unquote(a)), do: true
      end
    end
  end
  defp init({m, f, a}, _, _) do
    quote do
      require unquote(m)

      # first we check that it's defined
      if !function_exported?(unquote_splicing([m,f,a])) do
        raise UndefinedFunctionError, [
          module: unquote(m),
          function: unquote(f),
          arity: unquote(a),
          reason: "required for multimethod extension"
        ]
      end

      # now we make sure that it's exposed
      try do
        unquote(m).__multix__(unquote(f), unquote(a))
      rescue
        _ ->
          raise ArgumentError, unquote("#{
            Exception.format_mfa(m,f,a)
          } isn't exposed as a multimethod")
      end

      nil
    end
  end

  defp init_args(args) do
    args
    |> Stream.with_index()
    |> Enum.map(fn
      ({{name, _, nil} = arg, _}) when is_atom(name) ->
        arg
      ({{:\\, _, _} = arg, _}) ->
        arg
      ({_other, i}) ->
        Macro.var(:"@arg#{i}", nil)
    end)
  end

  def __put_impl__(m, name, value) do
    prev = case Module.get_attribute(m, name) do
      nil ->
        Module.register_attribute(m, name, persist: true)
        []
      prev ->
        prev
    end

    Module.put_attribute(m, name, [value | prev])
  end

  defp register(mfa, args, clause, body, opts, caller) do
    fun_name = format_impl_fun(mfa, args)
    {ast, args_list} = compile_clause(fun_name, args, clause, caller)
    # TODO is there a cleaner way to do this?
    {priority, _} = Code.eval_quoted(opts[:priority], [], caller)
    analysis = Multix.Analyzer.analyze(ast, caller, priority)
    key = format_dispatch_module(mfa)
    __put_impl__(caller.module, key, {analysis, ast})
    quote do
      Kernel.def unquote(fun_name)(unquote_splicing(args_list)), unquote(body)
      use Multix.Cache, key: unquote(key)
    end
  end

  defp format_dispatch_module({m,f,a}) do
    :"Multix.#{inspect(m)}.#{f}/#{a}"
  end

  defp format_impl_fun(mfa, args) do
    :"__#{format_dispatch_module(mfa)}_#{:erlang.phash2(args)}__"
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
      ({name, _, nil} = var, acc) when is_atom(name) ->
        {var, [var | acc]}
      (other, acc) ->
        {other, acc}
    end)
    |> elem(1)
  end

  defp compile_name(ast, %{functions: funs} = caller) do
    {name, meta, args} = Macro.expand_once(ast, caller)
    mfa = resolve_import(funs, {name, length(args)}, caller)
    {mfa, _} = Code.eval_quoted({:{}, meta, mfa}, [], caller)
    mfa
  end

  defp resolve_import(_, {{:., _, [module, fun]}, arity}, _) do
    [module, fun, arity]
  end
  defp resolve_import([], {f,a}, %{module: m}) do
    [m,f,a]
  end
  defp resolve_import([{module, funs} | rest], {fun, arity} = fa, caller) when is_list(funs) do
    if Enum.any?(funs, &(&1 == {fun, arity})) do
      [module, fun, arity]
    else
      resolve_import(rest, fa, caller)
    end
  end
end
