defmodule Multix.Dispatch do
  defmodule Exception do
    defexception [:module, :function, :arity]

    def message(opts) do
      FunctionClauseError.message(opts)
    end
  end

  defmacro __using__(opts) do
    quote bind_quoted: [opts: opts] do
      if !Module.get_attribute(__MODULE__, :multix_dispatch) do
        @multix_dispatch :"Multix.#{inspect(__MODULE__)}"
        Module.register_attribute(__MODULE__, :multix_methods, accumulate: true)

        def __multix_dispatch__ do
          @multix_dispatch
        end

        @before_compile Multix.Dispatch
      end

      @multix_methods {opts[:function], opts[:arity]}
    end
  end

  defmacro __before_compile__(_) do
    quote unquote: false do
      methods = @multix_methods
      parent_module = __MODULE__

      defmodule @multix_dispatch do
        @compile :debug_info

        Module.register_attribute(__MODULE__, :multix, persist: true)
        @multix true

        def consolidated?, do: false

        def dispatch(fun, args) do
          impl_for?(fun, args)
          |> case do
            {mod, fun, args} ->
              apply(mod, fun, args)
            nil ->
              raise Multix.Dispatch.Exception, [
                module: unquote(parent_module),
                function: fun,
                arity: :erlang.tuple_to_list(args)
              ]
          end
        end

        for {f, a} <- methods do
          fa_key = :"#{__MODULE__}.#{f}/#{a}"

          def impl_for?(unquote(f), args) when tuple_size(args) == unquote(a) do
            Multix.Dispatch.impl_for?(unquote(fa_key), args)
          end

          def inspect(unquote(f), unquote(a)) do
            Multix.Dispatch.inspect(
              unquote(fa_key),
              unquote(f),
              unquote(a)
            )
          end
        end
      end
    end
  end

  def impl_for?(module, args) do
    module
    |> fetch_fun()
    |> execute(args)
  end

  def execute(nil, _) do
    nil
  end
  def execute(module, data) do
    module.impl_for?(data)
  rescue
    FunctionClauseError ->
      nil
  end

  def inspect(fa_key, f, a) do
    module = fetch_fun(fa_key)
    clauses = module.module_info(:attributes)[:clauses]
    {:function, 1, f, a, Enum.map(clauses, fn
      ({:clause, line, [{:tuple, _, args}], guard, body}) ->
        {:clause, line, args, guard, body}
    end)}
    |> :forms.from_abstract()
    |> to_string()
  end

  defp fetch_fun(fa_key) do
    Multix.Cache.get_lazy(fa_key, fn ->
      fa_key
      |> Multix.Extractor.extract_impls([:in_memory | :code.get_path])
      |> Multix.Analyzer.sort(fa_key)
      |> eval(fa_key)
    end)
  end

  defp eval([], _) do
    nil
  end
  defp eval(clauses, module) do
    [
      {:attribute, 1, :module, module},
      {:attribute, 1, :export, [{:impl_for?, 1}]},
      {:attribute, 1, :clauses, clauses},

      {:function, 1, :impl_for?, 1, clauses}
    ]
    |> :compile.forms()
    |> case do
      {:ok, _, beam} ->
        :code.purge(module)
        :code.load_binary(module, '', beam)
        module
    end
  end
end
