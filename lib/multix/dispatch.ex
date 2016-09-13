defmodule Multix.Dispatch do
  def compile(name, pattern, [do: block]) do
    quote do
      defmodule Module.concat(unquote(name), unquote(Macro.to_string(pattern))) do

        Module.register_attribute(__MODULE__, :multix_dispatch, persist: true)
        @multix_dispatch [multix: unquote(name), for: __MODULE__]

        unquote(compile_pattern(pattern))

        _ = unquote(block)
      end
    end
  end

  defp compile_pattern({:when, _, [value, guard]}) do
    quote do
      def __match__(unquote(value)) when unquote(guard) do
        __MODULE__
      end
    end
  end
  defp compile_pattern(pattern) do
    quote do
      def __match__(unquote(pattern)) do
        __MODULE__
      end
    end
  end
end
