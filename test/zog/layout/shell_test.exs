defmodule Zog.Layout.ShellTest do
  use ExUnit.Case, async: true

  doctest Zog.Layout.Shell

  alias Zog.Layout.Shell

  describe "layout/3" do
    test "empty shells" do
      g = Zog.undirected()
      assert Shell.layout(g, []) == %{}
      assert Shell.layout(g, [], raw: true) == []
    end

    test "single node shell" do
      g = Zog.undirected() |> Zog.add_node("A")
      assert Shell.layout(g, [["A"]]) == %{"A" => {0.0, 0.0}}
    end
  end
end
