defmodule Mix.Tasks.Compile.Multix do
  use Mix.Task
  import Mix.Compilers.Elixir, only: [module: 1]

  @manifest ".compile.multix"
  @manifest_vsn :v1

  @moduledoc ~S"""
  Consolidates all multix modules in all paths.
  """
  @spec run(OptionParser.argv) :: :ok
  def run(args) do
    config = Mix.Project.config
    Mix.Task.run "compile", args
    {opts, _, _} = OptionParser.parse(args, switches: [force: :boolean, verbose: :boolean])

    output   = Mix.Project.consolidation_path(config)
    manifest = Path.join(output, @manifest)

    protocols_and_impls = protocols_and_impls(config)

    cond do
      opts[:force] || Mix.Utils.stale?(Mix.Project.config_files(), [manifest]) ->
        clean()
        paths = consolidation_paths()
        paths
        |> Multix.Extractor.extract_protocols
        |> consolidate(paths, output, manifest, protocols_and_impls, opts)

      protocols_and_impls ->
        manifest
        |> diff_manifest(protocols_and_impls, output)
        |> consolidate(consolidation_paths(), output, manifest, protocols_and_impls, opts)

      true ->
        :noop
    end
  end

  @doc """
  Cleans up consolidated protocols.
  """
  def clean do
    File.rm_rf(Mix.Project.consolidation_path)
  end

  defp protocols_and_impls(config) do
    deps = for(%{scm: scm, opts: opts} <- Mix.Dep.cached(),
               not scm.fetchable?,
               do: opts[:build])

    app =
      if Mix.Project.umbrella?(config) do
        []
      else
        [Mix.Project.app_path(config)]
      end

    protocols_and_impls =
      for path <- app ++ deps do
        manifest_path = Path.join(path, ".compile.elixir")
        compile_path = Path.join(path, "ebin")
        protocols_and_impls(manifest_path, compile_path)
      end

    Enum.concat(protocols_and_impls)
  end

  def protocols_and_impls(manifest, compile_path) do
    for module(beam: beam, module: module) <- Mix.Compilers.Elixir.read_manifest(manifest, compile_path),
      kind = detect_kind(module),
      do: {module, kind, beam}
  end

  defp detect_kind(module) do
    attributes = module.module_info(:attributes)
    cond do
      attributes[:multix] ->
        :multix
      attributes[:multix_dispatch] ->
        :dispatch
      true ->
        false
    end
  end

  defp consolidation_paths do
    filter_otp(:code.get_path, :code.lib_dir)
  end

  defp filter_otp(paths, otp) do
    Enum.filter(paths, &(not :lists.prefix(&1, otp)))
  end

  defp consolidate([], _paths, output, manifest, metadata, _opts) do
    File.mkdir_p!(output)
    write_manifest(manifest, metadata)
    :noop
  end

  defp consolidate(protocols, paths, output, manifest, metadata, opts) do
    File.mkdir_p!(output)

    protocols
    |> Enum.uniq()
    |> Enum.map(&Task.async(fn -> consolidate(&1, paths, output, opts) end))
    |> Enum.map(&Task.await(&1, 30_000))

    write_manifest(manifest, metadata)
    :ok
  end

  defp consolidate(protocol, paths, output, opts) do
    impls = Multix.Extractor.extract_impls(protocol, paths)
    reload(protocol)
    case Multix.Consolidator.consolidate(protocol, impls) do
      {:ok, binary} ->
        File.write!(Path.join(output, "#{protocol}.beam"), binary)
        if opts[:verbose] do
          Mix.shell.info "Consolidated #{inspect protocol}"
        end

      # If we remove a dependency and we have implemented one of its
      # protocols locally, we will mark the protocol as needing to be
      # reconsolidated when the implementation is removed even though
      # the protocol no longer exists. Although most times removing a
      # dependency will trigger a full recompilation, such won't happen
      # in umbrella apps with shared build.
      {:error, :no_beam_info} ->
        remove_consolidated(protocol, output)
        if opts[:verbose] do
          Mix.shell.info "Unavailable #{inspect protocol}"
        end
    end
  end

  defp reload(module) do
    :code.purge(module)
    :code.delete(module)
  end

  defp read_manifest(manifest, output) do
    try do
      [@manifest_vsn | metadata] =
        manifest |> File.read! |> :erlang.binary_to_term()
      metadata
    rescue
      _ ->
        # If there is no manifest or it is out of date, remove old files
        File.rm_rf(output)
        []
    end
  end

  defp write_manifest(manifest, metadata) do
    manifest_data =
      [@manifest_vsn | metadata]
      |> :erlang.term_to_binary(compressed: 9)

    File.write!(manifest, manifest_data)
  end

  defp diff_manifest(manifest, new_metadata, output) do
    modified = Mix.Utils.last_modified(manifest)
    old_metadata = read_manifest(manifest, output)

    protocols =
      for {protocol, :multix, beam} <- new_metadata,
          Mix.Utils.last_modified(beam) > modified,
          remove_consolidated(protocol, output),
          do: {protocol, true},
          into: %{}

    protocols =
      Enum.reduce(new_metadata -- old_metadata, protocols, fn
        {_, {:multix_dispatch, protocol}, _beam}, protocols ->
          Map.put(protocols, protocol, true)
        {protocol, :multix, _beam}, protocols ->
          Map.put(protocols, protocol, true)
      end)

    protocols =
      Enum.reduce(old_metadata -- new_metadata, protocols, fn
        {_, {:multix_dispatch, protocol}, _beam}, protocols ->
          Map.put(protocols, protocol, true)
        {protocol, :multix, _beam}, protocols ->
          remove_consolidated(protocol, output)
          protocols
      end)

    Map.keys(protocols)
  end

  defp remove_consolidated(protocol, output) do
    File.rm Path.join(output, "#{protocol}.beam")
  end
end