defmodule Pinocchio.Command do
  alias Pinocchio.Command.Util

  @prefix "I>"
  @bot_id 372_004_796_128_952_321

  defp actionable_command?(msg) do
    String.starts_with?(msg.content, @prefix) and msg.author.id != @bot_id
  end

  def handle(msg) do
    if actionable_command?(msg) do
      msg.content
      |> String.trim()
      |> String.split(" ", parts: 3)
      |> tl
      |> execute(msg)
    end
  end

  def execute(["h", method], msg) do
    Util.help(msg, method)
  end

  def execute(["ping"], msg) do
    Util.ping(msg)
  end

  def execute(["i", to_eval], msg) do
    Util.inspect(msg, to_eval)
  end
end
