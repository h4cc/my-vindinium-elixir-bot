defmodule Vindinium.Bots.Utils do
  def create_sectors({x,y}), do: [{x,y}, {-x,y}, {x,-y}, {-x,-y}]
end