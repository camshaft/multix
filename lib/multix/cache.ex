defmodule Multix.Cache do
  @table __MODULE__

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
          Multix.Cache.clear(unquote(key))
          super()
        end
        defoverridable [__multix_on_load__: 0]
      end
    end
  end

  def clear(key) do
    :ets.delete(@table, key)
  catch
    _, _ ->
      false
  end

  def get_lazy(key, fun) do
    case fetch(key) do
      :error ->
        put(key, fun.())
      {:ok, value} ->
        value
    end
  end

  def fetch(key) do
    {:ok, :ets.lookup_element(@table, key, 2)}
  catch
    _, _ ->
      :error
  end

  def put(key, value) do
    :ets.insert(@table, {key, value})
    value
  catch
    _, _ ->
      start()
      put(key, value)
  end

  def start() do
    # TODO start under the multix supervisor
    :ets.new(@table, [:set, :public, :named_table, {:write_concurrency, true}])
  end
end
