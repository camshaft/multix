defmodule Multix.Cache do
  @moduledoc false

  defmacro __using__(opts) do
    quote bind_quoted: [opts: opts] do
      [key: key] = opts
      if Module.get_attribute(__MODULE__, :on_load) == [] do
        @on_load :__multix_on_load__
        def __multix_on_load__(), do: :ok
        defoverridable [__multix_on_load__: 0]
      end

      # we only clear on the first one defined
      if match?([_], Module.get_attribute(__MODULE__, key)) do
        def __multix_on_load__() do
          :code.delete(unquote(key))
          super()
        end
        defoverridable [__multix_on_load__: 0]
      end
    end
  end
end
