defmodule PinocchioTest do
  use ExUnit.Case
  doctest Pinocchio

  test "greets the world" do
    assert Pinocchio.hello() == :world
  end
end
