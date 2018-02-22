defmodule Multix.Consolidator do
  @moduledoc false

  @concurrency 4

  @spec consolidate([term]) ::
          {:ok, binary}
          | {:error, :not_a_dispatcher}
          | {:error, :no_beam_info}
  def consolidate(impls) do
    {beams, targets} =
      impls
      |> Nile.pmap(
        fn {impl, targets} ->
          case load_code(impl) do
            {:ok, code} ->
              {targets, code} = modify_impl(targets, code)
              {targets, save_code(code)}

            error ->
              {[], error}
          end
        end,
        concurrency: @concurrency
      )
      |> Enum.map_reduce(%{}, fn {targets, code}, acc ->
        acc =
          Enum.reduce(targets, acc, fn {m, fa, clause}, acc ->
            mod = Map.get(acc, m, %{})
            clauses = Map.get(mod, fa, [])
            clauses = [clause | clauses]
            mod = Map.put(mod, fa, clauses)
            Map.put(acc, m, mod)
          end)

        {code, acc}
      end)

    targets
    |> Nile.pmap(fn {target, impls} ->
      case load_code(target) do
        {:ok, code} ->
          code = modify_target(impls, code)
          save_code(code)

        error ->
          error
      end
    end)
    |> Stream.concat(beams)
  end

  defp load_code(name) do
    name
    |> beam_file()
    |> :beam_lib.chunks([:abstract_code, 'ExDc'], [:allow_missing_chunks])
    |> case do
      {:ok, {module, [{:abstract_code, {:raw_abstract_v1, abstract_code}}, docs]}} ->
        {:ok, {module, abstract_code, docs}}

      _ ->
        # TODO convert the file name to a module name
        {:error, name, :no_beam_info}
    end
  end

  defp beam_file(module) when is_atom(module) do
    case :code.which(module) do
      atom when is_atom(atom) ->
        module

      '' ->
        {_module, binary, _file} = :code.get_object_code(module)
        binary

      file when is_list(file) ->
        file
    end
  end

  # Finally compile the module and emit its bytecode.
  defp save_code({_module, code, docs}) do
    opts = if Code.compiler_options()[:debug_info], do: [:debug_info], else: []
    # :io.fwrite('~s~n', [:erl_prettypr.format(:erl_syntax.form_list(code))])
    {:ok, mod, binary, _warnings} = :compile.forms(code, [:return | opts])
    # TODO add docs if we have them
    {:ok, mod, binary}
  end

  defp modify_impl(targets, {source, code, docs}) do
    targets = :maps.from_list(targets)

    {code, {_, targets}} =
      code
      |> :lists.reverse()
      |> Enum.flat_map_reduce({%{}, []}, fn
        {:function, line, name, arity, [clause]} = node, acc ->
          case Map.fetch(targets, {name, arity}) do
            {:ok, {m, f, a, opts}} ->
              {modified, clauses} = acc

              case prepare_clause(clause, source, name, m, f, a, opts) do
                {new_arity, target_clause, body} ->
                  modified = Map.put(modified, {name, arity}, {name, new_arity})
                  clauses = [{m, {f, a}, target_clause} | clauses]
                  acc = {modified, clauses}
                  {[{:function, line, name, new_arity, [body]}], acc}

                {:inline, target_clause} ->
                  modified = Map.put(modified, {name, arity}, nil)
                  clauses = [{m, {f, a}, target_clause} | clauses]
                  acc = {modified, clauses}
                  {[], acc}
              end

            _ ->
              {[node], acc}
          end

        {:attribute, _line, :multix_impl, _}, acc ->
          {[], acc}

        {:attribute, line, :export, exports}, {modified, _} = acc ->
          exports =
            exports
            |> Stream.map(&Map.get(modified, &1, &1))
            |> Enum.filter(& &1)

          node = {:attribute, line, :export, exports}
          {[node], acc}

        # TODO handle __info__

        node, acc ->
          {[node], acc}
      end)

    {targets, {source, :lists.reverse(code), docs}}
  end

  defp prepare_clause(clause, source, name, m, f, a, opts) do
    case Multix.Analyzer.analyze(clause, opts) do
      %{inline: true} = analysis ->
        {:inline, {clause, analysis}}

      %{inline: false, vars: vars} = analysis ->
        compile_clause(clause, vars, analysis)

      %{pure?: true} = analysis ->
        {:inline, {clause, analysis}}

      %{vars: vars} = analysis ->
        compile_clause(clause, vars, analysis)
    end
  end

  defp compile_clause(clause, vars, analysis) do
    # TODO
    {length(vars), {clause, analysis}, clause}
  end

  defp modify_target(targets, {source, code, docs}) do
    code =
      Enum.flat_map(code, fn
        {:function, line, name, arity, clauses} = node ->
          case Map.fetch(targets, {name, arity}) do
            {:ok, additional} ->
              clauses =
                clauses
                |> Stream.map(&{&1, Multix.Analyzer.analyze(&1)})
                |> Stream.concat(additional)
                |> Multix.Analyzer.sort()

              [{:function, line, name, arity, clauses}]

            _ ->
              [node]
          end

        {:attribute, line, :export, exports} = attr ->
          # TODO add __multix__
          [attr]

        node ->
          [node]
      end)

    {source, code, docs}
  end
end
