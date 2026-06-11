defmodule ZogTest do
  use ExUnit.Case
  doctest Zog

  test "creates directed model" do
    assert Zog.directed().kind == :directed
  end
end
