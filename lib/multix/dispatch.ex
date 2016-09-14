defmodule Multix.Dispatch do
  def compile(name, opts, [do: block], env) do
    %{for: pattern} = opts = :maps.from_list(opts)

    pattern = Macro.expand(pattern, env)
    pattern_s = Macro.to_string(pattern)

    module = Module.concat(name, (opts[:name] || "P" <> encode_name(pattern_s)))
    index = opts[:index] || case pattern do
                              {:_, _, _} -> -100
                              _ -> 0
                            end

    quote do
      name = unquote(name)

      Multix.assert_multi!(name)
      Multix.Dispatch.__ensure_defdispatch__(name, unquote(pattern_s), __ENV__)

      defmodule unquote(module) do
        @moduledoc false

        Module.register_attribute(__MODULE__, :multix_dispatch, persist: true)
        @multix_dispatch [multix: name,
                          for: __MODULE__,
                          index: unquote(index),
                          location: {__ENV__.file, __ENV__.line}]

        def __multix_info__ do
          %{pattern: unquote(Macro.escape(pattern)),
            pattern_s: unquote(pattern_s),
            erl_clause: unquote(compile_clause(pattern, module, env)),
            file: __ENV__.file,
            line: __ENV__.line,
            index: unquote(index)}
        end

        _ = unquote(block)
      end
    end
  end

  defp encode_name(pattern) do
    :crypto.hash(:md5, pattern)
    |> Base.url_encode64()
    |> String.replace("=", "")
  end

  defp compile_clause(pattern, module, env) do
    fun = quote do
      fn(unquote(pattern)) -> unquote(module) end
    end
    |> Code.eval_quoted([], env)
    |> elem(0)

    {_, [{_, _, _, [clause]}]} = :erlang.fun_info(fun, :env)

    clause
    |> Macro.escape()
  end

  @doc false
  def __ensure_defdispatch__(protocol, for, env) do
    if Multix.consolidated?(protocol) do
      message =
        "the #{inspect protocol} protocol has already been consolidated" <>
        ", an implementation for #{inspect for} has no effect"
      :elixir_errors.warn(env.line, env.file, message)
    end
    :ok
  end
end
