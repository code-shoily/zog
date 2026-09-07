defmodule Zog.Layout.RandomTest do
  use ExUnit.Case, async: true

  doctest Zog.Layout.Random

  alias Zog.Layout.Random

  describe "layout/2" do
    test "empty graph" do
      g = Zog.undirected()
      assert Random.layout(g) == %{}
      assert Random.layout(g, raw: true) == []
    end

    test "seeded reproducibility" do
      g = Zog.undirected() |> Zog.add_node("A") |> Zog.add_node("B")
      pos1 = Random.layout(g, seed: 100)
      pos2 = Random.layout(g, seed: 100)
      assert pos1 == pos2
    end
  end
end
