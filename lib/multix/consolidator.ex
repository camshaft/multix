defmodule Multix.Consolidator do
  @moduledoc false

  @doc """
  Receives a dispatcher and a list of implementations and
  consolidates the given dispatcher.

  Consolidation happens by changing the dispatcher `impl_for`
  in the abstract format to have fast lookup rules. Usually
  the list of implementations to use during consolidation
  are retrieved with the help of `extract_dispatchers/2`.

  It returns the updated version of the dispatcher bytecode.
  A given bytecode or dispatcher implementation can be checked
  to be consolidated or not by analyzing the dispatcher
  attribute:

       Multix.consolidated?(MyModule, :my_fun, 1)

  If the first element of the tuple is `true`, it means
  the dispatcher was consolidated.

  This function does not load the dispatcher at any point
  nor loads the new bytecode for the compiled module.
  However each implementation must be available and
  it will be loaded.
  """
  @spec consolidate(module, [module]) ::
    {:ok, binary} |
    {:error, :not_a_dispatcher} |
    {:error, :no_beam_info}
  def consolidate(dispatcher, paths) when is_atom(dispatcher) do
    with {:ok, info} <- beam_dispatcher(dispatcher),
         {:ok, code} <- change_impl_for(info, paths),
         do: compile(code)
  end

  defp beam_dispatcher(dispatcher) do
    case :beam_lib.chunks(beam_file(dispatcher), [:attributes]) do
      {:ok, {^dispatcher, [{:attributes, attributes}]}} ->
        case attributes[:multix] do
          methods when is_list(methods) and length(methods) > 0 ->
            {:ok, {dispatcher, methods}}
          _ ->
            {:error, :not_a_dispatcher}
        end
      _ ->
        {:error, :no_beam_info}
    end
  end

  defp beam_file(module) when is_atom(module) do
    case :code.which(module) do
      atom when is_atom(atom) -> module
      file -> file
    end
  end

  defp change_impl_for({dispatcher, methods}, paths) do
    {impls, dispatches, inspects} =
      Enum.reduce(methods, {[], [], []}, fn({f, a}, {impls, dispatches, inspects}) ->
        key = :"#{dispatcher}.#{f}/#{a}"

        clauses = key
        |> Multix.Extractor.extract_impls(paths)
        |> Multix.Analyzer.sort(key)
        |> Enum.to_list()

        str = Multix.Dispatch.__inspect__(f, a, clauses) |> to_charlist()

        inspect = {:clause, 0, [{:atom, 0, f}, {:integer, 0, a}], [], [
          {:bin, 0, [{:bin_element, 0, {:string, 0, str}, :default, :default}]}
        ]}

        {i, d} = Enum.reduce(clauses, {impls, dispatches}, fn
          ({:clause, line, [tuple], guard, body}, {impls, dispatches}) ->
            f = {:atom, line, f}
            impl = {:clause, line, [f, tuple], guard, body}
            dispatch = {:clause, line, [f, tuple], guard, call_impl(body)}
            {[impl | impls], [dispatch | dispatches]}
        end)

        {i, d, [inspect | inspects]}
      end)

    ast = [
      {:attribute, 1, :module, dispatcher},
      {:attribute, 1, :export, [
        {:consolidated?, 0},
        {:dispatch, 2},
        {:impl_for, 2},
        {:inspect, 2}
      ]},

      {:function, 1, :consolidated?, 0, [{:clause, 0, [], [], [{:atom, 1, true}]}]},
      {:function, 1, :dispatch, 2, :lists.reverse(dispatches)},
      {:function, 1, :impl_for, 2, :lists.reverse(impls)},
      {:function, 1, :inspect, 2, :lists.reverse(inspects)},
    ]

    {:ok, ast}
  end

  defp call_impl([{:tuple, line, [m,f,a]}]) do
    [{:call, line, {:remote, line, m, f}, cons_to_list(a)}]
  end

  defp cons_to_list({:nil, _}) do
    []
  end
  defp cons_to_list({:cons, _, head, tail}) do
    [head | cons_to_list(tail)]
  end

  # Finally compile the module and emit its bytecode.
  defp compile(code) do
    opts = if Code.compiler_options[:debug_info], do: [:debug_info], else: []
    {:ok, _mod, binary, _warnings} = :compile.forms(code, [:return | opts])
    {:ok, binary}
  end
end
