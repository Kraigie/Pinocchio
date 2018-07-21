defmodule Pinocchio.Command do
  alias Pinocchio.Command.Util

  @prefix "I>"
  @bot_id 372_004_796_128_952_321
  @owner_id 89_918_932_789_497_856

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

  def execute(["ping"], msg) do
    Util.ping(msg)
  end

  def execute(["h", term], msg) do
    Util.help(msg, term)
  end

  def execute(["i", to_inspect], msg) do
    if msg.author.id == @owner_id, do: Util.inspect(msg, to_inspect)
  end

  def execute(["e", to_eval], msg) do
    if msg.author.id == @owner_id, do: Util.eval(msg, to_eval)
  end

  def execute(_any, _msg) do
    :noop
  end
end
