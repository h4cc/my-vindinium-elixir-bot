defmodule Vindinium.Bots.Random do

  def move(_) do
    Enum.take_random(["Stay", "North", "South", "East", "West"], 1) |> List.first
  end

end
