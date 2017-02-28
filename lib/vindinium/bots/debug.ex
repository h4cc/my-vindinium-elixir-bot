defmodule Vindinium.Bots.Debug do

  require Logger
  alias Vindinium.Bots.Utils

  # Magic numbers
  @hero_life_max 100
  @mine_lose_life 20
  @tavern_gold 2
  @tavern_life 50

  # --- DIRECTIONS ---
  @directions [
    stay: "Stay",
    north: "North",
    south: "South",
    east: "East",
    west: "West",
  ]
  @direction_keys Keyword.keys(@directions)
  Enum.each(@directions, fn({atom, string}) ->
    defp direction(unquote(atom)), do: unquote(string)
  end)

  # --- TILES ---
  # ## Impassable wood
  # @1 Hero number 1
  # [] Tavern
  # $- Gold mine (neutral)
  # $1 Gold mine (belonging to hero 1)
  @tiles [
    {'  ', :empty},
    {'##', :wood},
    {'[]', :tavern},
    {'$-', :mine},
    {'$1', {:mine, 1}},
    {'$2', {:mine, 2}},
    {'$3', {:mine, 3}},
    {'$4', {:mine, 4}},
    {'@1', {:hero, 1}},
    {'@2', {:hero, 2}},
    {'@3', {:hero, 3}},
    {'@4', {:hero, 4}},
  ]
  Enum.each(@tiles, fn({string, type}) ->
    defp tile_type(unquote(string)), do: unquote(type)
  end)
  Enum.each(@tiles, fn({string, type}) ->
    defp tile_string(unquote(type)), do: unquote(string)
  end)

  def move(state) do
    # Enrich state map with some needed infos.
    state = state |> add_map |> add_heroes_map

    print_map(state)
    Logger.info(hero_stats_line(state["hero"]))

    # _Strategy:_
    # * Move randomly over empty tiles. DONE
    # * Visit tavern, if abled to drink. DONE
    # * Claim gold, if abled to conquer. DONE
    # * Move away from other heros to avoid beeing hit. DONE
    # * Do NOT move onto any other hero spawning position.

    # Looking for the first strategy that will return {:ok, direction}
    {:ok, dir} =
    with :ignore <- hero_fight(state),
         :ignore <- next_mine(state),
         :ignore <- next_tavern(state),
         :ignore <- next_empty(state) do
         {:ok, :stay}
    end

    Logger.info("Hero going direction #{inspect dir}")

    direction(dir)
  end

  defp hero_fight(state) do

    # If our hero has <= 20 life points: flee
    # If there is no hero around, ignore
    # If there is one hero around:
    #   with <= 20 life points: flee
    #   with less life then us: fight
    #   with more life than us: flee
    # If there are multiple heroes around: flee

    # Get list of heroes around
    state
    |> other_heroes_around
    |> case do

      [] ->
        Logger.info("No other hero next to us.")
        :ignore

      [{dir, {:hero, id}}] ->
        if hero_life(state) > 20 && hero_life(state) >= hero_life(state, id) do
          Logger.info("Fighting hero #{id}")
          {:ok, dir}
        else
          Logger.info("Other hero has more live points: FLEE.")
          next_empty(state)
        end

      [_, _ | _] ->
        Logger.info("Multiple heroes around: FLEE.")
        next_empty(state)
    end
  end

  defp next_mine(%{map: map} = state) do
    if hero_can_win_mine?(state) do
      # Check if there is a mine directly next to us we can capture.
      state
      |> tiles_around
      |> Enum.filter(fn {_, tile} ->
        case tile do
          {:mine, id} -> (id != hero_id(state))
          :mine -> true
          _ -> false
        end
      end)
      |> Enum.shuffle
      |> case do

        [] ->
          map
          |> find_next_mine(hero_id(state))
          |> case do
            {:ok, coords} ->
              Logger.info("Mine seen at #{inspect coords}.")
              {:ok, coords_to_direction(coords)}
            :error ->
              Logger.info("No mine next to hero.")
              :ignore
          end

        [{dir, _} | _] ->
          Logger.info("Mine at #{inspect dir} to hero.")
          {:ok, dir}
      end
    else
      Logger.info("Hero can not win mine.")
      :ignore
    end
  end

  defp next_tavern(%{map: map} = state) do
    if hero_can_buy_beer?(state) do
      # Check if there is a tavern directly next to us.
      @direction_keys
      |> Enum.filter(fn direction ->
        is_tile?(map, direction, :tavern)
      end)
      |> Enum.shuffle
      |> case do

        [] ->
          map
          |> find_next_tavern
          |> case do
            {:ok, coords} ->
              Logger.info("Tavern seen at #{inspect coords}.")
              {:ok, coords_to_direction(coords)}
            :error ->
              Logger.info("No tavern next to hero.")
              :ignore
          end

        [dir | _] ->
          Logger.info("Tavern at #{inspect dir} to hero.")
          {:ok, dir}
      end
    else
      Logger.info("Hero can not enter tavern.")
      :ignore
    end
  end

  defp coords_to_direction({0, 0}), do: :stay

  defp coords_to_direction({y, 0}) when y > 0, do: :east
  defp coords_to_direction({y, 0}) when y < 0, do: :west

  defp coords_to_direction({0, x}) when x > 0, do: :south
  defp coords_to_direction({0, x}) when x < 0, do: :north

  defp coords_to_direction({y, x}) when y > 0 and x > 0 and abs(y) > abs(x), do: :east
  defp coords_to_direction({y, x}) when y > 0 and x > 0 and abs(y) <= abs(x), do: :south

  defp coords_to_direction({y, x}) when y < 0 and x > 0 and abs(y) > abs(x), do: :west
  defp coords_to_direction({y, x}) when y < 0 and x > 0 and abs(y) <= abs(x), do: :south

  defp coords_to_direction({y, x}) when y > 0 and x < 0 and abs(y) > abs(x), do: :east
  defp coords_to_direction({y, x}) when y > 0 and x < 0 and abs(y) <= abs(x), do: :north

  defp coords_to_direction({y, x}) when y < 0 and x < 0 and abs(y) > abs(x), do: :west
  defp coords_to_direction({y, x}) when y < 0 and x < 0 and abs(y) <= abs(x), do: :north

  defp next_empty(%{map: map}) do
    # Check if there are empty tiles next to us.
    @direction_keys
    |> Enum.filter(fn direction ->
      is_tile?(map, direction, :empty)
    end)
    |> Enum.shuffle
    |> case do
      [] ->
        Logger.info("No empty tile next to hero.")
        :ignore
      [dir | _] ->
        Logger.info("Empty tile at #{inspect dir} to hero.")
        {:ok, dir}
    end
  end

  defp is_tile?(map, direction, type) do
    case tile(map, direction) do
      ^type -> true
      _ -> false
    end
  end

  defp tile(%{{ 0, -1} => type},  :west), do: type
  defp tile(%{{ 0,  1} => type},  :east), do: type
  defp tile(%{{ 1,  0} => type}, :south), do: type
  defp tile(%{{-1,  0} => type}, :north), do: type
  defp tile(                  _,      _), do: nil

  defp hero_can_win_mine?(state), do: hero_life(state) > @mine_lose_life

  defp hero_can_buy_beer?(state) do
    # Has enough gold
    hero_gold(state) >= @tavern_gold
    &&
    # Would get at least 50% of gained life points.
    hero_life(state) < (@hero_life_max - (@tavern_life / 2))
  end


  @search_coords_order [
    {1,1},

    {2,0},

    {2,1},
    {1,2},
    
    {3,0},
    
    {3,1},
    {1,3},
  ]

  Enum.each(@search_coords_order, fn(coord) ->
    coord
    |> Utils.create_sectors
    |> Enum.each(fn({x,y}) ->
        defp find_next_mine(%{{unquote(x), unquote(y)} => :mine}, _) do
          {:ok, {unquote(x), unquote(y)}}
        end
        defp find_next_mine(%{{unquote(x), unquote(y)} => {:mine, other_hid}}, my_hid) when my_hid != other_hid do
          {:ok, {unquote(x), unquote(y)}}
        end
    end)
  end)
  defp find_next_mine(_, _), do: :error

  Enum.each(@search_coords_order, fn(coord) ->
    coord
    |> Utils.create_sectors
    |> Enum.each(fn({x,y}) ->
        defp find_next_tavern(%{{unquote(x), unquote(y)} => :tavern}) do
          {:ok, {unquote(x), unquote(y)}}
        end
    end)
  end)
  defp find_next_tavern(_), do: :error


  defp build_map(%{"game" => %{"board" => %{"size" => size, "tiles" => tiles}}} = state) do
    {hero_x, hero_y} = hero_position(state)
    tiles
    |> String.to_charlist
    |> Enum.chunk(size*2)
    |> Enum.with_index
    |> Enum.flat_map(fn({line, x}) ->
      line
      |> Enum.chunk(2)
      |> Enum.with_index
      |> Enum.map(fn({string, y}) ->
        {
          {x-hero_x, y-hero_y},
          tile_type(string)
        }
      end)
    end)
    |> Enum.into(%{})
  end

  def print_map(%{"game" => %{"board" => %{"size" => size, "tiles" => tiles}}}) do
    IO.puts(" ")
    IO.puts("+" <> String.duplicate("-", size*2) <> "+")
    tiles
    |> String.to_charlist
    |> Enum.chunk(size*2)
    |> Enum.each(fn(line) -> IO.puts("|#{line}|") end)
    IO.puts("+" <> String.duplicate("-", size*2) <> "+")
  end

  def hero_stats_line(%{"crashed" => crashed, "elo" => elo, "gold" => gold, "id" => id,
                          "life" => life, "mineCount" => mines, "name" => name,
                          "pos" => _, "spawnPos" => _, "userId" => _}) do
    "#{name} (@#{id}): #{life}/#{@hero_life_max} mines:#{mines} gold:#{gold} elo:#{elo} crashed:#{inspect crashed}"
  end

  defp other_heroes_around(state) do
    state
    |> tiles_around
    |> Enum.filter(fn {_, tile} ->
      case tile do
        {:hero, id} -> (id != hero_id(state))
        _ -> false
      end
    end)
  end

  defp tiles_around(%{map: map}) do
    @direction_keys -- [:stay]
    |> Enum.map(fn direction ->
      {direction, tile(map, direction)}
    end)
  end

  defp hero_position(%{"hero" => %{"pos" => %{"x" => x, "y" => y}}}), do: {x, y}
  defp hero_gold(%{"hero" => %{"gold" => gold}}), do: gold
  defp hero_id(%{"hero" => %{"id" => id}}), do: id
  defp hero_life(%{"hero" => %{"life" => life}}), do: life
  defp hero_life(%{heroes_map: %{1 => %{"life" => life}}}, 1), do: life
  defp hero_life(%{heroes_map: %{2 => %{"life" => life}}}, 2), do: life
  defp hero_life(%{heroes_map: %{3 => %{"life" => life}}}, 3), do: life
  defp hero_life(%{heroes_map: %{4 => %{"life" => life}}}, 4), do: life

  defp add_map(state) do
    Map.put(state, :map, build_map(state))
  end

  defp add_heroes_map(state) do
    Map.put(state, :heroes_map, build_heroes_map(state))
  end

  defp build_heroes_map(%{"game" => %{"heroes" => heroes}}) do
    Enum.into(heroes, %{}, fn(%{"id" => id} = hero) -> {id, hero} end)
  end

end
