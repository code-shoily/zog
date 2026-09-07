defmodule Zog.Layout.MultipartiteTest do
  use ExUnit.Case, async: true

  doctest Zog.Layout.Multipartite

  alias Zog.Layout.Multipartite

  describe "layout/3" do
    test "empty layers" do
      g = Zog.undirected()
      assert Multipartite.layout(g, []) == %{}
      assert Multipartite.layout(g, [], raw: true) == []
    end

    test "single layer" do
      g = Zog.undirected() |> Zog.add_node("A")
      assert Multipartite.layout(g, [["A"]]) == %{"A" => {0.0, 0.0}}
    end
  end
end
