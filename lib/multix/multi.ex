defmodule Multix.Multi do
  def compile(name, [do: block]) do
    quote do
      defmodule unquote(name) do
        # We don't allow function definition inside protocols
        import Kernel, except: [
          defmacrop: 1, defmacrop: 2, defmacro: 1, defmacro: 2,
          defp: 1, defp: 2, def: 1, def: 2
        ]

        # Import the new dsl that holds the new def
        import unquote(__MODULE__), only: [def: 1]

        # Compile with debug info for consolidation
        @compile :debug_info

        # Set up a clear slate to store defined functions
        @functions []

        # Invoke the user given block
        _ = unquote(block)

        # Finalize expansion
        unquote(after_defmulti())
      end
    end
  end

  defp after_defmulti do
    quote unquote: false do
      @doc false
      @spec impl_for(term) :: atom | nil
      Kernel.def impl_for(data)

      Kernel.def impl_for(data) do
        path = [:in_memory | :code.get_path()]
        __MODULE__
        |> Multix.Extractor.extract_impls(path)
        |> Multix.Multi.__find_match__(data)
      end

      @doc false
      @spec impl_for!(term) :: atom | no_return
      Kernel.def impl_for!(data) do
        impl_for(data) || raise(Protocol.UndefinedError, protocol: __MODULE__, value: data)
      end

      unless Kernel.Typespec.defines_type?(__MODULE__, :t, 0) do
        @type t :: term
      end

      # Store information as an attribute so it
      # can be read without loading the module.
      Module.register_attribute(__MODULE__, :multix, persist: true)
      @multix []

      @doc false
      @spec __multix__(:module) :: __MODULE__
      @spec __multix__(:functions) :: unquote(Protocol.__functions_spec__(@functions))
      @spec __multix__(:consolidated?) :: boolean
      Kernel.def __multix__(:module), do: __MODULE__
      Kernel.def __multix__(:functions), do: unquote(:lists.sort(@functions))
      Kernel.def __multix__(:consolidated?), do: false
    end
  end

    @doc """
  Defines a new multi-method function.
  Multi-method modules do not allow functions to be defined directly, instead, the
  regular `Kernel.def/*` macros are replaced by this macro which
  defines the multi-method functions with the appropriate callbacks.
  """
  defmacro def(signature)

  defmacro def({_, _, args}) when args == [] or is_atom(args) do
    raise ArgumentError, "multi-method functions expect at least one argument"
  end

  defmacro def({name, _, args}) when is_atom(name) and is_list(args) do
    arity = length(args)

    type_args = :lists.map(fn _ -> quote(do: term) end,
                           :lists.seq(2, arity))
    type_args = [quote(do: t) | type_args]

    call_args = :lists.map(fn i -> {String.to_atom(<<?x, i + 64>>), [], __MODULE__} end,
                           :lists.seq(2, arity))
    call_args = [quote(do: t) | call_args]

    quote do
      name  = unquote(name)
      arity = unquote(arity)

      @functions [{name, arity} | @functions]

      # Generate a fake definition with the user
      # signature that will be used by docs
      Kernel.def unquote(name)(unquote_splicing(args))

      # Generate the actual implementation
      Kernel.def unquote(name)(unquote_splicing(call_args)) do
        impl_for!(t).unquote(name)(unquote_splicing(call_args))
      end

      # Convert the spec to callback if possible,
      # otherwise generate a dummy callback
      Protocol.__spec__?(__MODULE__, name, arity) ||
        @callback unquote(name)(unquote_splicing(type_args)) :: term
    end
  end

  def __find_match__([], _) do
    nil
  end
  def __find_match__(types, data) do
    clauses = Enum.map(types, fn(type) ->
      type.__multix_clause__()
    end)
    fun = {:fun, 1, {:clauses, clauses}}
    |> :erl_eval.expr([])
    |> elem(1)

    fun.(data)
  rescue
    FunctionClauseError ->
      nil
  end
end
