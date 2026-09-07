defmodule Zog.Layout.CircularTest do
  use ExUnit.Case, async: true

  doctest Zog.Layout.Circular

  alias Zog.Layout.Circular

  describe "layout/2" do
    test "empty graph" do
      g = Zog.undirected()
      assert Circular.layout(g) == %{}
      assert Circular.layout(g, raw: true) == []
    end

    test "single node" do
      g = Zog.undirected() |> Zog.add_node("A")
      assert Circular.layout(g, center: {5.0, 10.0}) == %{"A" => {5.0, 10.0}}
    end

    test "multi node positioning" do
      g = Zog.undirected() |> Zog.add_node("A") |> Zog.add_node("B")
      pos = Circular.layout(g, radius: 10.0)
      assert map_size(pos) == 2
    end
  end
end
