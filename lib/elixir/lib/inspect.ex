import Kernel, except: [inspect: 1]
import Inspect.Algebra

defrecord Inspect.Opts, raw: false, limit: :infinity, depth: 0,
                        pretty: false, width: 80, as_doc: false

defprotocol Inspect do
  @moduledoc """
  The `Inspect` protocol is responsible for
  converting any structure to a binary for textual
  representation. All basic data structures
  (tuple, list, function, pid, etc) implement the
  inspect protocol. Other structures are advised to
  implement the protocol in order to provide pretty
  printing.
  """

  def inspect(thing, opts)
end

defmodule Inspect.Utils do
  @moduledoc """
  This module defines useful functions to be used on the
  implementation of custom pretty-printers. The provided
  functions use the document algebra implemented on the
  `Inspect.Algebra` module.
  """

  ## groups aware of depth
  @doc """
  Increases the depth count to be used with group_maybe.
  """
  def inc_depth(Inspect.Opts[] = opts), do: opts.update_depth(&1 + 1)

  @doc """
  Wraps a document `d` on a group if the current nest level on the pretty-printer is
  smaller than `t`. `group_maybe/2` uses a default nesting level of 3.

    # group_maybe enables the output for
    iex(1)> inspect([foo: [1,2,3,:bar], bazzz: :bat], [pretty: true, width: 30])

    # to be a much more concise
    [
      foo: [1,2,3,:bar], bazzz: :bat
    ]

    # instead of
    [
      foo: [
        1,
        2,
        3,
        :bar
      ],
      bazzz: :bat
    ]


  """
  def group_maybe(d, opts),    do: group_maybe_do(d, 3, fn(d) -> group(d) end, opts)
  def group_maybe(d, t, opts), do: group_maybe_do(d, t, fn(d) -> group(d) end, opts)

  defp group_maybe_do(d, t, f, opts) do
    if opts.depth > t, do: d, else: f.(d)
  end

  @doc """
  Renders a document with regard to the the provided options:
  * `:as_doc`: returns doc if true, useful for recursive Kernel.inspect calls.
  * `:pretty`: applies pretty-printing on the document if true.
  * `:width`: the number of columns available for rendering the document.
  """
  def return(doc, Inspect.Opts[] = opts) do
    cond do
      opts.as_doc -> doc
      opts.pretty -> pretty(doc, opts.width)
      true -> pretty(doc, :infinity)
    end
  end

  @doc """
  Creates a document from a sequence (tuples and lists), using first and
  last to enclose the document.
  """
  def container_join(tuple, first, last, opts) when is_tuple(tuple) do
    container_join(tuple_to_list(tuple), first, last, opts)
  end

  def container_join(list, first, last, opts) do
    opts = inc_depth(opts)
    group_maybe(
      surround(
        first,
        do_container_join(list, opts, opts.limit),
        last,
        ""
      ),
    5, opts)
  end

  defp do_container_join(_, _opts, 0) do
    text "..."
  end

  defp do_container_join([h], opts, _counter) do
    Kernel.inspect(h, opts.as_doc(true))
  end

  defp do_container_join([h|t], opts, counter) when is_list(t) do
    glue(
      concat(
        Kernel.inspect(h, opts.as_doc(true)),
        text(",")
      ),
      "",
      do_container_join(t, opts, decrement(counter))
    )
  end

  defp do_container_join([h|t], opts, _counter) do
    glue(
      concat(
        Kernel.inspect(h, opts.as_doc(true)),
        text("|")
      ),
      "",
      Kernel.inspect(t, opts.as_doc(true))
    )
  end

  defp do_container_join([], _opts, _counter) do
    text ""
  end

  defp decrement(:infinity), do: :infinity
  defp decrement(counter),   do: counter - 1

  ## escape

  def escape(other, char) do
    b = do_escape(other, char, <<>>)
    << char, b :: binary, char >>
  end

  @compile {:inline, do_escape: 3}
  defp do_escape(<<>>, _char, binary), do: binary
  defp do_escape(<< char, t :: binary >>, char, binary) do
    do_escape(t, char, << binary :: binary, ?\\, char >>)
  end
  defp do_escape(<<?#, ?{, t :: binary>>, char, binary) do
    do_escape(t, char, << binary :: binary, ?\\, ?#, ?{ >>)
  end
  defp do_escape(<<?\a, t :: binary>>, char, binary) do
    do_escape(t, char, << binary :: binary, ?\\, ?a >>)
  end
  defp do_escape(<<?\b, t :: binary>>, char, binary) do
    do_escape(t, char, << binary :: binary, ?\\, ?b >>)
  end
  defp do_escape(<<?\d, t :: binary>>, char, binary) do
    do_escape(t, char, << binary :: binary, ?\\, ?d >>)
  end
  defp do_escape(<<?\e, t :: binary>>, char, binary) do
    do_escape(t, char, << binary :: binary, ?\\, ?e >>)
  end
  defp do_escape(<<?\f, t :: binary>>, char, binary) do
    do_escape(t, char, << binary :: binary, ?\\, ?f >>)
  end
  defp do_escape(<<?\n, t :: binary>>, char, binary) do
    do_escape(t, char, << binary :: binary, ?\\, ?n >>)
  end
  defp do_escape(<<?\r, t :: binary>>, char, binary) do
    do_escape(t, char, << binary :: binary, ?\\, ?r >>)
  end
  defp do_escape(<<?\\, t :: binary>>, char, binary) do
    do_escape(t, char, << binary :: binary, ?\\, ?\\ >>)
  end
  defp do_escape(<<?\t, t :: binary>>, char, binary) do
    do_escape(t, char, << binary :: binary, ?\\, ?t >>)
  end
  defp do_escape(<<?\v, t :: binary>>, char, binary) do
    do_escape(t, char, << binary :: binary, ?\\, ?v >>)
  end
  defp do_escape(<<h, t :: binary>>, char, binary) do
    do_escape(t, char, << binary :: binary, h >>)
  end
end

defimpl Inspect, for: Atom do
  require Macro
  import Inspect.Utils

  @doc """
  Represents the atom as an Elixir term. The atoms false, true
  and nil are simply quoted. Modules are properly represented
  as modules using the dot notation.

  Notice that in Elixir, all operators can be represented using
  literal atoms (`:+`, `:-`, etc).

  ## Examples

      iex> inspect(:foo)
      ":foo"
      iex> inspect(nil)
      "nil"
      iex> inspect(Foo.Bar)
      "Foo.Bar"

  """
  def inspect(atom, opts) do
    return text(inspect_text(atom)), opts
  end

  # Used internally by Elixir
  @doc false
  def inspect_text(false),  do: "false"
  def inspect_text(true),   do: "true"
  def inspect_text(nil),    do: "nil"
  def inspect_text(:""),    do: ":\"\""
  def inspect_text(Elixir), do: "Elixir"

  def inspect_text(atom) do
    binary = atom_to_binary(atom)

    cond do
      valid_atom_identifier?(binary) ->
        ":" <> binary
      valid_ref_identifier?(binary) ->
        Module.to_string(atom)
      atom in Macro.binary_ops or atom in Macro.unary_ops ->
        ":" <> binary
      true ->
        ":" <> escape(binary, ?")
    end
  end

  # Detect if atom is an atom alias (Elixir.Foo.Bar.Baz)

  defp valid_ref_identifier?("Elixir" <> rest) do
    valid_ref_piece?(rest)
  end

  defp valid_ref_identifier?(_), do: false

  defp valid_ref_piece?(<<?., h, t :: binary>>) when h in ?A..?Z do
    valid_ref_piece? valid_identifier?(t)
  end

  defp valid_ref_piece?(<<>>), do: true
  defp valid_ref_piece?(_),    do: false

  # Detect if atom

  defp valid_atom_identifier?(<<h, t :: binary>>) when h in ?a..?z or h in ?A..?Z or h == ?_ do
    case valid_identifier?(t) do
      <<>>   -> true
      <<??>> -> true
      <<?!>> -> true
      _      -> false
    end
  end

  defp valid_atom_identifier?(_), do: false

  defp valid_identifier?(<<h, t :: binary>>)
      when h in ?a..?z
      when h in ?A..?Z
      when h in ?0..?9
      when h == ?_ do
    valid_identifier? t
  end

  defp valid_identifier?(other), do: other
end

defimpl Inspect, for: BitString do
  import Inspect.Utils

  @doc %B"""
  Represents the string as itself escaping
  all necessary characters.

  ## Examples

      iex> inspect("bar")
      "\"bar\""
      iex> inspect("f\"oo")
      "\"f\\\"oo\""

  """

  def inspect(thing, opts) when is_binary(thing) do
    if String.printable?(thing) do
      return text(escape(thing, ?")), opts
    else
      return text(as_bitstring(thing, opts)), opts
    end
  end

  def inspect(thing, opts) do
    return text(as_bitstring(thing, opts)), opts
  end

  ## Bitstrings

  defp as_bitstring(bitstring, Inspect.Opts[] = opts) do
    "<<" <> each_bit(bitstring, opts.limit) <> ">>"
  end

  defp each_bit(_, 0) do
    "..."
  end

  defp each_bit(<<h, t :: bitstring>>, counter) when t != <<>> do
    integer_to_binary(h) <> "," <> each_bit(t, decrement(counter))
  end

  defp each_bit(<<h :: size(8)>>, _counter) do
    integer_to_binary(h)
  end

  defp each_bit(<<>>, _counter) do
    <<>>
  end

  defp each_bit(bitstring, _counter) do
    size = bit_size(bitstring)
    <<h :: size(size)>> = bitstring
    integer_to_binary(h) <> "::size(" <> integer_to_binary(size) <> ")"
  end

  defp decrement(:infinity), do: :infinity
  defp decrement(counter),   do: counter - 1
end

defimpl Inspect, for: List do
  import Inspect.Utils

  @doc %B"""
  Represents a list checking if it can be printed or not.
  If so, a single-quoted representation is returned,
  otherwise the brackets syntax is used.

  Inspecting a list is conservative as it does not try
  to guess how the list is encoded. That said, `'josé'`
  will likely be inspected as `[106,111,115,195,169]`
  because we can't know if it is encoded in utf-8
  or iso-5569-1, which is common in Erlang libraries.

  ## Examples

      iex> inspect('bar')
      "'bar'"
      iex> inspect([0|'bar'])
      "[0,98,97,114]"
      iex> inspect([:foo,:bar])
      "[:foo,:bar]"

  """

  def inspect([], opts), do: return(text("[]"), opts)

  def inspect(thing, Inspect.Opts[] = opts) do
    cond do
      :io_lib.printable_list(thing) ->
        return text(escape(:unicode.characters_to_binary(thing), ?')), opts
      keyword?(thing) ->
        opts = inc_depth(opts)
        return(
          group_maybe(
            surround("[",join_keywords(thing, opts.as_doc(true)),"]"),
            opts
          ), opts
        )
      true ->
        return container_join(thing, "[", "]", opts), opts
    end
  end

  defp join_keywords([x], opts),   do: keyword_to_docentity(x, opts)
  defp join_keywords([x|xs], opts) do
    glue(
      concat(
        keyword_to_docentity(x, opts),
        text(",")
      ),
      join_keywords(xs, opts)
    )
  end

  defp keyword_to_docentity({key, value}, opts) do
    keybin = key_to_binary(key, opts) <> ": "

    concat(
      text(keybin),
      Kernel.inspect(value, opts.as_doc(true))
    )
  end

  defp key_to_binary(key, opts) do
    case Inspect.Atom.inspect(key, opts.as_doc(false)) do
      ":" <> right -> right
      other -> other
    end
  end

  defp keyword?([{ key, _value } | rest]) when is_atom(key) do
    case atom_to_list(key) do
      'Elixir.' ++ _ -> false
      _ -> keyword?(rest)
    end
  end

  defp keyword?([]),     do: true
  defp keyword?(_other), do: false
end

defimpl Inspect, for: Tuple do
  import Inspect.Utils

  @doc """
  Inspect tuples. If the tuple represents a record,
  it shows it nicely formatted using the access syntax.

  ## Examples

      iex> inspect({1, 2, 3})
      "{1,2,3}"
      iex> inspect(ArgumentError.new)
      "ArgumentError[message: \\\"argument error\\\"]"

  """

  def inspect({}, opts), do: return(text("{}"), opts)

  def inspect(tuple, opts) do
    unless opts.raw do
      return record_inspect(tuple, opts.as_doc(true)), opts
    end || return container_join(tuple, "{", "}", opts), opts
  end

  ## Helpers

  defp record_inspect(record, opts) do
    [name|tail] = tuple_to_list(record)

    if is_atom(name) && (fields = record_fields(name)) && (length(fields) == size(record) - 1) do
      if Enum.first(tail) == :__exception__ do
        record_join(name, tl(fields), tl(tail), opts)
      else
        record_join(name, fields, tail, opts)
      end
    end || container_join(record, "{", "}", opts)
  end

  defp record_fields(name) do
    try do
      name.__record__(:fields)
    rescue
      _ -> nil
    end
  end

  defp record_join(name, fields, tail, opts) do
    opts = inc_depth(opts)
    fields = lc { field, _ } inlist fields, do: field
    namedoc = Inspect.Atom.inspect(name, opts)
    group_maybe(
      concat(
        namedoc,
        surround("[", record_join(fields, tail, opts), "]")
      ),
      opts
    )
  end

  defp record_join([f], [v], opts) do
    fbin = atom_to_binary(f, :utf8) <> ": "
    concat(
      text(fbin),
      Kernel.inspect(v, opts)
    )
  end

  defp record_join([fh|ft], [vh|vt], opts) do
    fhbin = atom_to_binary(fh, :utf8) <> ": "
    glue(
      concat(
        text(fhbin),
        concat(
          Kernel.inspect(vh, opts),
          text(",")
        )
      ),
      record_join(ft, vt, opts)
    )
  end

  defp record_join([], [], _opts) do
    text ""
  end
end

defimpl Inspect, for: Number do
  import Inspect.Utils

  @doc """
  Represents the number as a binary.

  ## Examples

      iex> inspect(1)
      "1"

  """
  def inspect(thing, opts) when is_integer(thing) do
    return text(integer_to_binary(thing)), opts
  end

  def inspect(thing, opts) do
    return text(list_to_binary(:io_lib_format.fwrite_g(thing))), opts
  end
end

defimpl Inspect, for: Regex do
  import Inspect.Utils

  @moduledoc %B"""
  Represents the Regex using the `%r""` syntax.

  ## Examples

      iex> inspect(%r/foo/m)
      "%r\"foo\"m"

  """
  def inspect(regex, opts) when size(regex) == 5 do
    return text("%r" <> Kernel.inspect(Regex.source(regex), []) <> Regex.opts(regex)), opts
  end

  def inspect(other, opts) do
    return Kernel.inspect(other, opts.raw(true).as_doc(true)), opts
  end
end

defimpl Inspect, for: Function do
  import Inspect.Utils

  @moduledoc """
  Inspect functions, when possible, in a literal form.
  """
  def inspect(function, opts) do
    fun_info = :erlang.fun_info(function)
    if fun_info[:type] == :external and fun_info[:env] == [] do
      return(
        text(
          "function(#{Kernel.inspect(fun_info[:module])}.#{fun_info[:name]}/#{fun_info[:arity]})"
        ),
      opts)
    else
      '#Fun' ++ rest = :erlang.fun_to_list(function)
      return text("#Function" <> list_to_binary(rest)), opts
    end
  end
end

defimpl Inspect, for: PID do
  import Inspect.Utils

  def inspect(pid, opts) do
    return(text("#PID" <> list_to_binary pid_to_list(pid)), opts)
  end
end

defimpl Inspect, for: Port do
  import Inspect.Utils

  def inspect(port, opts) do
    return(text(list_to_binary :erlang.port_to_list(port)), opts)
  end
end

defimpl Inspect, for: Reference do
  import Inspect.Utils

  def inspect(ref, opts) do
    '#Ref' ++ rest = :erlang.ref_to_list(ref)
    return text("#Reference" <> list_to_binary(rest)), opts
  end
end

defimpl Inspect, for: HashDict do
  def inspect(dict, opts) do
    "#HashDict<" <> Kernel.inspect(HashDict.to_list(dict), opts) <> ">"
  end
end

defimpl Inspect, for: HashSet do
  def inspect(set, opts) do
    "#HashSet<" <> Kernel.inspect(HashSet.to_list(set), opts) <> ">"
  end
end
