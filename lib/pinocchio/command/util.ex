defmodule Pinocchio.Command.Util do
  alias Nostrum.Api

  import Nostrum.Struct.Embed

  require Logger

  def ping(msg) do
    Api.create_message(msg.channel_id, "pong")
  end

  def help(msg, term) do
    with {:ok, quoted} <- Code.string_to_quoted(term),
         ast when is_tuple(ast) <- Macro.decompose_call(quoted) do
      mfa = mfa_from_ast(ast)

      {{m, f, a}, function_header, description} = docs_for(mfa)
      link = link({m |> to_string |> String.replace("Elixir.", ""), f, a})

      embed =
        %Nostrum.Struct.Embed{}
        |> put_title("**#{term}**")
        |> put_description(description)
        |> put_field("Link", "[Master Docs](#{link})")
        |> put_color(0x714A94)

      Api.create_message!(
        msg,
        embed:
          if(function_header, do: put_field(embed, "Definition", function_header), else: embed)
      )
    else
      any -> IO.inspect(any)
    end
  end

  defp mfa_from_ast(ast) do
    case ast do
      # Enum
      {:__aliases__, modules} ->
        {Module.concat(modules), nil, nil}

      # Enum.random([1])
      {:__aliases__, _, modules} ->
        {Module.concat(modules), nil, nil}

      # Enum.random
      {{:__aliases__, _, modules}, fun, []} ->
        {Module.concat(modules), fun, nil}

      # Enum.random/1, yikes
      {:/, [{{:., _, [{:__aliases__, _, modules}, fun]}, _, []}, arity]} ->
        {Module.concat(modules), fun, arity}

      _ ->
        ast
    end
  end

  defp docs_for({m, nil, nil} = mfa) do
    {_line, doc} = Code.get_docs(m, :moduledoc)

    {mfa, nil,
     doc
     |> String.split(".")
     |> hd
     |> String.replace("\n", " ")}
  end

  defp docs_for({m, f, nil}) do
    docs = Code.get_docs(m, :docs)

    {{^f, a}, _line, _, args, doc} =
      Enum.find(docs, fn {{fun, _}, _line, _, _args, _doc} -> fun == f end)

    function_header =
      args
      |> Enum.reduce("def #{f}(", fn
        {:\\, [], [{arg, _, _}, default]}, acc ->
          acc <> "#{to_string(arg)} \\\\ #{to_string(default)}, "

        {arg, _, _}, acc ->
          acc <> "#{to_string(arg)}, "
      end)
      |> String.trim()
      |> String.replace("Elixir.", "")
      |> String.replace_trailing(",", "")
      |> Kernel.<>(")")
      |> elixir_code_block

    description =
      doc
      |> String.split(".")
      |> hd
      |> String.replace("\n", " ")

    {{m, f, a}, function_header, description}
  end

  defp docs_for({m, f, a}) do
    docs = Code.get_docs(m, :docs)

    {{^f, ^a}, _line, _, args, doc} =
      Enum.find(docs, fn {{fun, arity}, _line, _, _args, _doc} -> fun == f and arity == a end)

    function_header =
      args
      |> Enum.reduce("def #{f}(", fn
        {:\\, [], [{arg, _, _}, default]}, acc ->
          acc <> "#{to_string(arg)} \\\\ #{to_string(default)}, "

        {arg, _, _}, acc ->
          acc <> "#{to_string(arg)}, "
      end)
      |> String.trim()
      |> String.replace("Elixir.", "")
      |> String.replace_trailing(",", "")
      |> Kernel.<>(")")
      |> elixir_code_block

    description =
      doc
      |> String.split(".")
      |> hd
      |> String.replace("\n", " ")

    {{m, f, a}, function_header, description}
  end

  defp link({<<"Nostrum">> <> _ = m, nil, nil}),
    do: "https://kraigie.github.io/nostrum/#{m}.html#content"

  defp link({<<"Nostrum">> <> _ = m, f, a}),
    do: "https://kraigie.github.io/nostrum/#{m}.html##{f}/#{a}"

  defp link({m, nil, nil}), do: "https://hexdocs.pm/elixir/#{m}.html#content"
  defp link({m, f, a}), do: "https://hexdocs.pm/elixir/#{m}.html##{f}/#{a}"

  def inspect(msg, to_eval) do
    {val, _args} =
      to_eval
      |> String.replace("I>", "|>")
      |> Code.eval_string([msg: msg], __ENV__)

    info =
      [Term: val] ++
        IEx.Info.info(val) ++ ["Implemented protocols": all_implemented_protocols_for_term(val)]

    embed = %{
      fields:
        for {subject, val} <- info do
          case val do
            val when is_binary(val) -> %{name: subject, value: val}
            val -> %{name: subject, value: "#{inspect(val)}"}
          end
        end
    }

    Api.create_message(msg, content: "", embed: embed)
  end

  defp all_implemented_protocols_for_term(term) do
    :code.get_path()
    |> Protocol.extract_protocols()
    |> Enum.uniq()
    |> Enum.reject(fn protocol -> is_nil(protocol.impl_for(term)) end)
    |> Enum.map_join(", ", &inspect/1)
  end

  def eval(msg, to_eval) do
    evald =
      try do
        to_eval
        |> String.replace("I>", "|>")
        |> Code.eval_string([msg: msg], __ENV__)
      rescue
        e -> {:error, e, System.stacktrace() |> hd}
      end

    evald
    |> eval_message
    |> elixir_code_block
    |> pipe_create_message(msg)
  end

  defp eval_message({:error, e, stack}),
    do:
      "** (#{inspect(e.__struct__)}) #{apply(e.__struct__, :message, [e])}\n\n#{inspect(e)}\n#{
        inspect(stack)
      }"

  defp eval_message({evald, _}), do: "#{inspect(evald)}"

  defp pipe_create_message(content, msg) do
    Api.create_message!(msg, content)
  end

  defp elixir_code_block(content) do
    "```elixir\n" <> content <> "\n```"
  end
end
