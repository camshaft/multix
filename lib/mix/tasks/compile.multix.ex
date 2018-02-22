defmodule Mix.Tasks.Compile.Multix do
  use Mix.Task
  import Mix.Compilers.Elixir, only: [module: 1]

  @manifest "compile.multix"
  @manifest_vsn 1

  @moduledoc ~S"""
  Consolidates all multix modules in all paths.
  """
  @spec run(OptionParser.argv()) :: :ok
  def run(args) do
    config = Mix.Project.config()
    {opts, _, _} = OptionParser.parse(args, switches: [force: :boolean, verbose: :boolean])

    manifest = manifest()
    output = Mix.Project.consolidation_path(config)

    dispatchers_and_impls = dispatchers_and_impls(config)

    # TODO remove this once i get the manifest diffing working
    opts = Keyword.put(opts, :force, true)

    cond do
      opts[:force] || Mix.Utils.stale?(Mix.Project.config_files(), [manifest]) ->
        clean()
        paths = consolidation_paths()

        paths
        |> Multix.Extractor.extract_impls()
        |> consolidate(output, manifest, dispatchers_and_impls, opts)

      dispatchers_and_impls ->
        manifest
        |> diff_manifest(dispatchers_and_impls, output)
        |> consolidate(output, manifest, dispatchers_and_impls, opts)

      true ->
        :noop
    end
  end

  @doc """
  Cleans up manifest.
  """
  def clean do
    File.rm(manifest())
  end

  @doc """
  Returns manifests.
  """
  def manifests, do: [manifest()]
  defp manifest, do: Path.join(Mix.Project.manifest_path(), @manifest)

  defp dispatchers_and_impls(config) do
    deps = for %{scm: scm, opts: opts} <- Mix.Dep.cached(), not scm.fetchable?, do: opts[:build]

    app =
      if Mix.Project.umbrella?(config) do
        []
      else
        [Mix.Project.app_path(config)]
      end

    protocols_and_impls =
      for path <- app ++ deps do
        manifest_path = Path.join(path, ".mix/compile.elixir")
        compile_path = Path.join(path, "ebin")
        dispatchers_and_impls(manifest_path, compile_path)
      end

    Enum.concat(protocols_and_impls)
  end

  def dispatchers_and_impls(manifest, compile_path) do
    for module(beam: beam, module: module) <-
          Mix.Compilers.Elixir.read_manifest(manifest, compile_path),
        kind = detect_kind(module),
        do: {module, kind, beam}
  end

  defp detect_kind(module) do
    attributes = module.module_info(:attributes)

    cond do
      funs = attributes[:multix] ->
        {:dispatch, funs}

      impls = attributes[:multix_impl] ->
        {:impl, impls}

      true ->
        false
    end
  end

  defp consolidation_paths do
    filter_otp(:code.get_path(), :code.lib_dir())
  end

  defp filter_otp(paths, otp) do
    Enum.filter(paths, &(not :lists.prefix(&1, otp)))
  end

  defp consolidate([], output, manifest, metadata, _opts) do
    File.mkdir_p!(output)
    write_manifest(manifest, metadata)
    :noop
  end

  defp consolidate(dispatchers, output, manifest, metadata, opts) do
    File.mkdir_p!(output)

    consolidate(dispatchers, output, opts)

    write_manifest(manifest, metadata)
    :ok
  end

  defp consolidate(dispatchers, output, opts) do
    dispatchers
    |> Multix.Consolidator.consolidate()
    |> Enum.map(fn
      {:ok, module, binary} ->
        File.write!(Path.join(output, "#{module}.beam"), binary)

        if opts[:verbose] do
          Mix.shell().info("Consolidated #{inspect(module)}")
        end

      # If we remove a dependency and we have implemented one of its
      # protocols locally, we will mark the protocol as needing to be
      # reconsolidated when the implementation is removed even though
      # the protocol no longer exists. Although most times removing a
      # dependency will trigger a full recompilation, such won't happen
      # in umbrella apps with shared build.
      {:error, module, :no_beam_info} ->
        remove_consolidated(module, output)

        Mix.shell().error("Unavailable #{inspect(module)}")
    end)
  end

  defp read_manifest(manifest, output) do
    try do
      [@manifest_vsn | metadata] = manifest |> File.read!() |> :erlang.binary_to_term()
      metadata
    rescue
      _ ->
        # If there is no manifest or it is out of date, remove old files
        File.rm_rf(output)
        []
    end
  end

  defp write_manifest(manifest, metadata) do
    File.mkdir_p!(Path.dirname(manifest))
    manifest_data = :erlang.term_to_binary([@manifest_vsn | metadata], [:compressed])
    File.write!(manifest, manifest_data)
  end

  defp diff_manifest(manifest, new_metadata, output) do
    modified = Mix.Utils.last_modified(manifest)
    old_metadata = read_manifest(manifest, output)

    modules =
      for {module, :multix, beam} <- new_metadata,
          Mix.Utils.last_modified(beam) > modified,
          remove_consolidated(module, output),
          do: {module, true},
          into: %{}

    modules =
      Enum.reduce(new_metadata -- old_metadata, modules, fn {module, :multix, _beam}, modules ->
        Map.put(modules, module, true)
      end)

    removed_metadata = old_metadata -- new_metadata

    removed_modules =
      for {module, :multix, _beam} <- removed_metadata,
          remove_consolidated(module, output),
          do: {module, true},
          into: %{}

    modules =
      for {_, {:impl, module}, _beam} <- removed_metadata,
          not Map.has_key?(removed_modules, module),
          do: {module, true},
          into: modules

    modules
  end

  defp remove_consolidated(module, output) do
    File.rm(Path.join(output, "#{module}.beam"))
  end
end
