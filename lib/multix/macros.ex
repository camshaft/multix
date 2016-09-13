defmodule Multix.Macros do
  defmacro __using__(_) do
    quote do
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
      @fallback_to_any false
    end
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
end
