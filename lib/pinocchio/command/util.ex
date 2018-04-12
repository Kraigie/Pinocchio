defmodule Pinocchio.Command.Util do
  alias Nostrum.Api
  alias Nostrum.Struct.Embed
  alias Pinocchio.Command.Doc

  require Logger

  def ping(msg) do
    Api.create_message(msg.channel_id, "pong")
  end

  def help(msg, term) do
    embed =
      term
      |> Code.string_to_quoted!()
      |> Macro.decompose_call()
      |> mfa_from_ast
      |> Doc.h()
      |> help_embed
      |> IO.inspect()

    Api.create_message!(msg.channel_id, content: "", embed: embed)
  end

  def inspect(msg, to_eval) do
    {val, _args} = Code.eval_string(to_eval)

    info =
      [Term: val] ++
        IEx.Info.info(val) ++ ["Implemented protocols": all_implemented_protocols_for_term(val)]

    IO.inspect(info)

    embed = %{
      fields:
        for {subject, val} <- info do
          case val do
            val when is_binary(val) -> %{name: subject, value: val}
            val -> %{name: subject, value: "#{inspect(val)}"}
          end
        end
    }

    Api.create_message(msg.channel_id, content: "", embed: embed)
  end

  defp map_to_fields(struct, fields) do
    split = String.split(fields, ~r/\#{2,}.+?\n/, include_captures: true)

    ["## Info" | split]
    |> Enum.chunk_every(2)
    |> Enum.reduce(struct, fn [name, value], acc ->
      name = String.replace(name, "#", "") |> String.trim()
      Embed.put_field(acc, name, value, true)
    end)
  end

  defp help_embed({heading, _types, doc}) do
    %Embed{}
    |> Embed.put_title(heading)
    |> map_to_fields(doc)
  end

  defp mfa_from_ast(ast) do
    case ast do
      # Enum
      {:__aliases__, modules} ->
        Module.concat(modules)

      # Enum.random
      {{:__aliases__, _, modules}, fun, []} ->
        {Module.concat(modules), fun}

      # Enum.random/1, yikes
      {:/, [{{:., _, [{:__aliases__, _, modules}, fun]}, _, []}, arity]} ->
        {Module.concat(modules), fun, arity}

      _ ->
        ast
    end
  end

  defp all_implemented_protocols_for_term(term) do
    :code.get_path()
    |> Protocol.extract_protocols()
    |> Enum.uniq()
    |> Enum.reject(fn protocol -> is_nil(protocol.impl_for(term)) end)
    |> Enum.map_join(", ", &inspect/1)
  end
end
