defmodule Multix.Compiler do
  @moduledoc false

  def defmulti({:when, _meta, [fun, clause]}, body, opts) do
    compile(fun, clause, body, opts)
  end

  def defmulti(fun, body, opts) do
    compile(fun, true, body, opts)
  end

  defp compile(mfa, clause, body, opts) do
    quote bind_quoted: [
            mfa: {:quote, [], [[do: mfa]]},
            clause: {:quote, [], [[do: clause]]},
            body: {:quote, [], [[do: body]]},
            opts: {:quote, [], [[do: opts]]}
          ],
          context: __MODULE__.DEFMULTI do
      env = __ENV__
      {m, f, args, a} = Multix.Compiler.resolve_name(mfa, env)

      cond do
        __MODULE__ != m ->
          Multix.Compiler.ensure_multi(m, f, a, env)

        true ->
          # same module; already defined
          :ok
      end

      fun_name = :"_#{m}.#{f}/#{a} (#{:erlang.phash2(args)})"

      opts =
        opts
        |> Enum.into(%{
          priority: 0
        })
        |> Map.merge(%{
          file: env.file,
          line: env.line
        })

      Multix.Compiler.__attr__(env, :multix_impl, {{fun_name, a}, {m, f, a, opts}})

      def unquote(fun_name)(unquote_splicing(args)), unquote(body)
    end
  end

  def resolve_name({{:., _, [module, fun]}, _, args}, env) do
    {Macro.expand(module, env), fun, args, length(args)}
  end

  def resolve_name({name, _, args}, %{module: module}) when is_atom(name) do
    {module, name, args, length(args)}
  end

  def ensure_multi(m, f, a, env) do
    Code.ensure_compiled(m)

    if !function_exported?(m, f, a) do
      raise UndefinedFunctionError,
        module: m,
        function: f,
        arity: a,
        reason: "required for multimethod extension"
    end

    if Multix.consolidated?(m) do
      require Logger
      name = Exception.format_mfa(m, f, a)
      fl = Exception.format_file_line(env.file, env.line)
      Logger.warn("#{fl} #{name} has already been consolidated")
    end
  end

  def __attr__(%{module: m}, name, value) do
    prev =
      case Module.get_attribute(m, name) do
        nil ->
          Module.register_attribute(m, name, persist: true)
          []

        prev ->
          prev
      end

    Module.put_attribute(m, name, :ordsets.add_element(value, prev))
  end
end
