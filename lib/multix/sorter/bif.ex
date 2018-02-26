defmodule Multix.Sorter.Bif do
  bifs = %{
    {:*, 2} => [
      [type: :number],
      [type: :number]
    ],
    {:+, 1} => [
      [type: :number]
    ],
    {:+, 2} => [
      [type: :number],
      [type: :number]
    ],
    {:-, 1} => [
      [type: :number]
    ],
    {:-, 2} => [
      [type: :number],
      [type: :number]
    ],
    {:/, 2} => [
      [type: :number],
      [type: :number]
    ],
    {:"/=", 2} => [[], []],
    {:<, 2} => [[], []],
    {:"=/=", 2} => [[], []],
    {:"=:=", 2} => [[], []],
    {:"=<", 2} => [[], []],
    {:==, 2} => [[], []],
    {:>, 2} => [[], []],
    {:>=, 2} => [[], []],
    {:abs, 1} => [
      [type: :number]
    ],
    {:and, 2} => [
      [type: :boolean],
      [type: :boolean]
    ],
    {:band, 2} => [
      [type: :number],
      [type: :number]
    ],
    {:binary_part, 2} => [
      [type: :binary],
      [type: :tuple]
    ],
    {:binary_part, 3} => [
      [type: :binary],
      [type: :integer],
      [type: :integer]
    ],
    {:bit_size, 1} => [
      [type: :binary]
    ],
    {:bnot, 1} => [
      [type: :number]
    ],
    {:bor, 2} => [
      [type: :number],
      [type: :number]
    ],
    {:bsl, 2} => [
      [type: :number],
      [type: :number]
    ],
    {:bsr, 2} => [
      [type: :number],
      [type: :number]
    ],
    {:bxor, 2} => [
      [type: :number],
      [type: :number]
    ],
    {:byte_size, 1} => [
      [type: :binary]
    ],
    {:ceil, 1} => [
      [type: :number]
    ],
    {:div, 2} => [
      [type: :number],
      [type: :number]
    ],
    {:element, 2} => [
      [type: :number],
      [type: :tuple]
    ],
    {:float, 1} => [
      [type: :float]
    ],
    {:floor, 1} => [
      [type: :number]
    ],
    {:hd, 1} => [
      [type: :list]
    ],
    {:is_atom, 1} => [
      [type: :atom]
    ],
    {:is_binary, 1} => [
      [type: :binary]
    ],
    {:is_bitstring, 1} => [
      [type: :bitstring]
    ],
    {:is_boolean, 1} => [
      [type: :boolean]
    ],
    {:is_float, 1} => [
      [type: :float]
    ],
    {:is_function, 1} => [
      [type: :function]
    ],
    {:is_function, 2} => [
      [type: :function],
      [type: :integer]
    ],
    {:is_integer, 1} => [
      [type: :integer]
    ],
    {:is_list, 1} => [
      [type: :list]
    ],
    {:is_map, 1} => [
      [type: :map]
    ],
    {:is_number, 1} => [
      [type: :number]
    ],
    {:is_pid, 1} => [
      [type: :pid]
    ],
    {:is_port, 1} => [
      [type: :port]
    ],
    {:is_record, 2} => [
      [type: :record],
      [type: :atom]
    ],
    {:is_record, 3} => [
      [type: :record],
      [type: :atom],
      [type: :integer]
    ],
    {:is_reference, 1} => [
      [type: :reference]
    ],
    {:is_tuple, 1} => [
      [type: :tuple]
    ],
    {:length, 1} => [
      [type: :list]
    ],
    {:map_size, 1} => [
      [type: :map]
    ],
    {:node, 1} => [
      [type: {:or, [:pid, :port, :reference]}]
    ],
    {:not, 1} => [
      [type: :boolean]
    ],
    {:or, 2} => [
      [type: :boolean],
      [type: :boolean]
    ],
    {:rem, 2} => [
      [type: :number],
      [type: :number]
    ],
    {:round, 1} => [
      [type: :number]
    ],
    {:size, 1} => [
      [type: :tuple]
    ],
    {:tl, 1} => [
      [type: :list]
    ],
    {:trunc, 1} => [
      [type: :integer]
    ],
    {:tuple_size, 1} => [
      [type: :tuple]
    ],
    {:xor, 2} => [
      [type: :number],
      [type: :number]
    ]
  }

  if Mix.env() !== :prod do
    :erlang.module_info(:exports)
    |> Stream.concat(:math.module_info(:exports))
    |> Stream.uniq()
    |> Stream.filter(fn {f, a} ->
      a > 0 and
        (:erl_internal.arith_op(f, a) or :erl_internal.bool_op(f, a) or
           :erl_internal.comp_op(f, a) or :erl_internal.guard_bif(f, a))
    end)
    |> Stream.filter(&(!Map.has_key?(bifs, &1)))
    |> Enum.sort()
    |> case do
      [] ->
        :ok

      missing ->
        raise "Missing %{\n  #{
                for {f, a} <- missing do
                  "#{inspect({f, a})} => []"
                end
                |> Enum.join(",\n  ")
              }\n}"
    end
  end

  def get, do: unquote(Macro.escape(bifs))

  types =
    [
      :literal,
      :bitstring,
      :binary,
      :list,
      nil,
      :map,
      :record,
      :tuple,
      :pid,
      :port,
      :fun,
      :reference,
      :boolean,
      :atom,
      :float,
      :number,
      :integer,
      :guarded_var,
      :var
    ]
    |> Enum.with_index()

  for {a, a_i} <- types,
      {b, b_i} <- types do
    def compare_type(unquote(a), unquote(b)) do
      unquote(b_i >= a_i)
    end
  end
end
