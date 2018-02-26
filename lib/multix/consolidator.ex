defmodule Multix.Consolidator do
  @moduledoc false

  @concurrency 4

  @spec consolidate([term]) ::
          {:ok, binary}
          | {:error, :not_a_dispatcher}
          | {:error, :no_beam_info}
  def consolidate(impls) do
    impls = Enum.to_list(impls)

    beams = load_beams(impls)
    {targets, beams} = modify_impls(impls, beams)

    targets
    |> acc_targets()
    |> modify_targets(beams)
    |> Nile.pmap(
      fn {_mod, code} ->
        save_code(code)
      end,
      concurrency: @concurrency
    )
  end

  defp load_beams(impls) do
    impls
    |> Enum.reduce([], fn {impl, targets}, acc ->
      Enum.reduce(targets, [impl | acc], fn {_fun, {target, _t_fun, _arity, _opts}}, acc ->
        [target | acc]
      end)
    end)
    |> Nile.pmap(&{&1, load_code(&1)})
    |> Enum.into(%{})
  end

  defp load_code(name) do
    chunk_ids = [:abstract_code, 'ExDc', 'ExDp']

    name
    |> beam_file()
    |> :beam_lib.chunks(chunk_ids, [:allow_missing_chunks])
    |> case do
      {:ok, {module, [{:abstract_code, {:raw_abstract_v1, abstract_code}} | extras]}} ->
        extra_chunks =
          for {name, contents} when is_binary(contents) <- extras,
              do: {List.to_string(name), contents}

        {module, abstract_code, extra_chunks}

      _ ->
        raise "Error loading #{name}"
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
  defp save_code({_, code, extra_chunks}) do
    opts = if Code.compiler_options()[:debug_info], do: [:debug_info], else: []
    # :io.fwrite('~s~n', [:erl_prettypr.format(:erl_syntax.form_list(code))])
    {:ok, mod, binary, _warnings} = :compile.forms(code, [:return | opts])
    {:ok, mod, :elixir_erl.add_beam_chunks(binary, extra_chunks)}
  end

  defp modify_impls(impls, beams) do
    Enum.map_reduce(impls, beams, fn {impl, targets}, beams ->
      code = Map.fetch!(beams, impl)
      {targets, code} = modify_impl(targets, code)
      {targets, %{beams | impl => code}}
    end)
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

  defp acc_targets(impl_targets) do
    Enum.reduce(impl_targets, %{}, fn targets, acc ->
      Enum.reduce(targets, acc, fn {m, fa, clause}, acc ->
        mod = Map.get(acc, m, %{})
        clauses = Map.get(mod, fa, [])
        clauses = [clause | clauses]
        mod = Map.put(mod, fa, clauses)
        Map.put(acc, m, mod)
      end)
    end)
  end

  defp modify_targets(targets, beams) do
    Enum.reduce(targets, beams, fn {mod, t}, beams ->
      code = Map.fetch!(beams, mod)
      code = modify_target(t, code)
      %{beams | mod => code}
    end)
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
                |> Multix.Sorter.sort()

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
