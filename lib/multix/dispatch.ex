defmodule Multix.Dispatch do
  def compile(name, opts, [do: block]) do
    %{for: pattern} = opts = :maps.from_list(opts)

    module = Module.concat(name, (opts[:name] || "P" <> encode_name(pattern)))

    quote do
      defmodule unquote(module) do
        @moduledoc false

        Module.register_attribute(__MODULE__, :multix_dispatch, persist: true)
        @multix_dispatch [multix: unquote(name), for: __MODULE__, index: unquote(opts[:index] || 0)]

        def __multix_clause__ do
          unquote(format_clause(pattern, module))
        end

        _ = unquote(block)
      end
    end
  end

  defp encode_name(pattern) do
    str = pattern
    |> Macro.to_string()

    :crypto.hash(:md5, str)
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
end
