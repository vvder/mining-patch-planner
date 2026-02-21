local mpp_util = require("mpp.mpp_util")
local EAST, NORTH, SOUTH, WEST = mpp_util.directions()

local train_station_planner = {}

local function align_odd(n)
	return n % 2 == 0 and (n + 1) or n
end

local function clamp_positive_int(value, fallback)
	local num = math.floor(tonumber(value) or fallback)
	if num < 1 then return fallback end
	return num
end

local function print_step(state, step, message)
	if state.player and state.player.valid then
		state.player.print({"", "[MPP][TrainStation] ", step, ": ", message})
	end
end

---@param surface LuaSurface
---@param player LuaPlayer
---@param force LuaForce
---@param ghost GhostSpecification
local function place_ghost(surface, player, force, ghost)
	if not prototypes.entity[ghost.name] then return end
	ghost.raise_built = true
	ghost.player = player
	ghost.force = force
	ghost.inner_name = ghost.name
	ghost.name = "entity-ghost"
	surface.create_entity(ghost)
end

---@param belts BeltSpecification[]
local function to_world_belt_outputs(state, belts)
	local outputs = {}
	local converter = mpp_util.reverter_delegate(state.coords, state.direction_choice)
	for _, belt in pairs(belts or {}) do
		if belt.is_output == true then
			local gx, gy = converter(belt.x_start - 1, belt.y)
			outputs[#outputs+1] = {x = math.floor(gx), y = math.floor(gy)}
		end
	end
	table.sort(outputs, function(a, b) return a.y < b.y end)
	return outputs
end

---@param state MinimumPreservedState
function train_station_planner.generate_from_layout_state(state)
	local outputs = to_world_belt_outputs(state, state.belts)
	if #outputs == 0 then
		print_step(state, "skip", "no output belts")
		return
	end

	local surface = state.surface
	local player = state.player
	local force = player.force
	local belt_name = state.belt_choice
	local chest_name = "steel-chest"
	local inserter_name = "fast-inserter"
	local rail_name = "straight-rail"
	local pole_name = state.pole_choice ~= "none" and state.pole_choice or "medium-electric-pole"

	local avg_x = 0
	local avg_y = 0
	local min_x = outputs[1].x
	local max_x = outputs[1].x
	local min_y = outputs[1].y
	local max_y = outputs[1].y
	for _, o in ipairs(outputs) do
		avg_x = avg_x + o.x
		avg_y = avg_y + o.y
		if o.x < min_x then min_x = o.x end
		if o.x > max_x then max_x = o.x end
		if o.y < min_y then min_y = o.y end
		if o.y > max_y then max_y = o.y end
	end
	avg_x = math.floor(avg_x / #outputs)
	avg_y = math.floor(avg_y / #outputs)

	local direction = state.direction_choice or "west"
	local station_offset = clamp_positive_int(state.train_station_offset_choice, 12)
	local train_length = clamp_positive_int(state.train_station_train_length_choice, 1)
	local wagon_length = clamp_positive_int(state.train_station_wagon_length_choice, 2)
	local station_type = state.train_station_type_choice or "loading"
	local anchor_x, anchor_y, station_direction
	local rail_vertical = true
	local side = 1

	if direction == "east" then
		anchor_x = align_odd(max_x + station_offset)
		anchor_y = align_odd(avg_y)
		station_direction = SOUTH
		rail_vertical = true
		side = -1
	elseif direction == "north" then
		anchor_x = align_odd(avg_x)
		anchor_y = align_odd(min_y - station_offset)
		station_direction = EAST
		rail_vertical = false
		side = 1
	elseif direction == "south" then
		anchor_x = align_odd(avg_x)
		anchor_y = align_odd(max_y + station_offset)
		station_direction = WEST
		rail_vertical = false
		side = -1
	else
		anchor_x = align_odd(min_x - station_offset)
		anchor_y = align_odd(avg_y)
		station_direction = NORTH
		rail_vertical = true
		side = 1
	end

	local rolling_stock_count = math.max(1, train_length + wagon_length)
	local rail_half_span = math.max(16, rolling_stock_count * 3 + 4)
	local stop_longitudinal_offset = side * (wagon_length * 3 + 2)

	print_step(state, "1/5", "create rail line")
	for i = -rail_half_span, rail_half_span, 2 do
		local rail_x = rail_vertical and anchor_x or (anchor_x + i)
		local rail_y = rail_vertical and (anchor_y + i) or anchor_y
		place_ghost(surface, player, force, {
			name = rail_name,
			position = {rail_x, rail_y},
			direction = station_direction,
		})
	end

	print_step(state, "2/5", "create train stop")
	local trainstop_x = rail_vertical and (anchor_x + side * 2) or (anchor_x + stop_longitudinal_offset)
	local trainstop_y = rail_vertical and (anchor_y - stop_longitudinal_offset)  or (anchor_y + side * 2)
	place_ghost(surface, player, force, {
		name = "train-stop",
		position = {trainstop_x, trainstop_y},
		direction = station_direction,
		tags = {station_name = "MPP Mining Loading"},
	})
	print_step(state, "3/5", "create loading chests and inserters")
	for i, _ in ipairs(outputs) do
		local lane = i - math.ceil(#outputs / 2)
		
		-- 从铁轨边缘向外布局：插入器-箱子-插入器-传送带
		local inserter_rail_x = rail_vertical and (anchor_x + side * 2) or (anchor_x + lane)
		local inserter_rail_y = rail_vertical and (anchor_y + lane) or (anchor_y + side * 2)

		local chest_x = rail_vertical and (anchor_x + side * 3) or (anchor_x + lane)
		local chest_y = rail_vertical and (anchor_y + lane) or (anchor_y + side * 3)

		local inserter_belt_x = rail_vertical and (anchor_x + side * 4) or (anchor_x + lane)
		local inserter_belt_y = rail_vertical and (anchor_y + lane) or (anchor_y + side * 4)
		local inserter_direction = NORTH
		if rail_vertical then
			inserter_direction = side > 0 and EAST or WEST
		else
			inserter_direction = side > 0 and SOUTH or NORTH
		end
		local reverse_inserter_direction = (inserter_direction + 4) % 8
		local near_rail_direction = station_type == "unloading" and reverse_inserter_direction or inserter_direction
		local near_belt_direction = station_type == "unloading" and inserter_direction or reverse_inserter_direction
		
		-- 靠铁轨的插入器
		place_ghost(surface, player, force, {
			name = inserter_name,
			position = {inserter_rail_x, inserter_rail_y},
			direction = near_rail_direction,
		})
		
		place_ghost(surface, player, force, {
			name = chest_name,
			position = {chest_x, chest_y},
			direction = NORTH,
		})
		
		-- 靠传送带的插入器
		place_ghost(surface, player, force, {
			name = inserter_name,
			position = {inserter_belt_x, inserter_belt_y},
			direction = near_belt_direction,
		})
	end

	print_step(state, "4/5", "route belts from patch outputs to station")
	for i, src in ipairs(outputs) do
		local lane = i - math.ceil(#outputs / 2)
		local dst_x = rail_vertical and (anchor_x + side * 5) or (anchor_x + lane)
		local dst_y = rail_vertical and (anchor_y + lane) or (anchor_y + side * 5)

		local x1, x2 = math.min(src.x, dst_x), math.max(src.x, dst_x)
		for x = x1, x2 do
			place_ghost(surface, player, force, {
				name = belt_name,
				position = {x, src.y},
				direction = src.x <= dst_x and EAST or WEST,
			})
		end

		local y1, y2 = math.min(src.y, dst_y), math.max(src.y, dst_y)
		for y = y1, y2 do
			place_ghost(surface, player, force, {
				name = belt_name,
				position = {dst_x, y},
				direction = src.y <= dst_y and SOUTH or NORTH,
			})
		end
	end

	-- print_step(state, "5/5", "add power poles")
	-- for i = -6, 6, 3 do
	-- 	local pole_x = rail_vertical and (anchor_x + side * 5) or (anchor_x + i)
	-- 	local pole_y = rail_vertical and (anchor_y + i) or (anchor_y + side * 5)
	-- 	place_ghost(surface, player, force, {
	-- 		name = pole_name,
	-- 		position = {pole_x, pole_y},
	-- 		direction = NORTH,
	-- 	})
	-- end

	print_step(state, "done", "belt-to-train-station ghosts generated")
end

return train_station_planner
