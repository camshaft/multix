defmodule Multix.Dispatch do
  def compile(name, opts, [do: block]) do
    %{for: pattern} = opts = :maps.from_list(opts)

    pattern_s = Macro.to_string(pattern)

    module = Module.concat(name, (opts[:name] || "P" <> encode_name(pattern_s)))

    quote do
      name = unquote(name)

      Multix.assert_multi!(name)
      Multix.Dispatch.__ensure_defdispatch__(name, unquote(pattern_s), __ENV__)

      defmodule unquote(module) do
        @moduledoc false

        Module.register_attribute(__MODULE__, :multix_dispatch, persist: true)
        @multix_dispatch [multix: name, for: __MODULE__, index: unquote(opts[:index] || 0)]

        def __multix_clause__ do
          unquote(format_clause(pattern, module))
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

  defp format_clause(pattern, module) do
    fun = pattern
    |> format_fun(module)
    |> Code.eval_quoted([])
    |> elem(0)

    {_, [{_, _, _, [clause]}]} = :erlang.fun_info(fun, :env)

    clause
    |> Macro.escape()
  end

  defp format_fun({:when, _, [value, guard]}, module) do
    quote do
      fn(unquote(value)) when unquote(guard) ->
        unquote(module)
      end
    end
  end
  defp format_fun(pattern, module) do
    quote do
      fn(unquote(pattern)) ->
        unquote(module)
      end
    end
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
