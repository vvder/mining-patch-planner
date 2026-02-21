local mpp_util = require("mpp.mpp_util")
local EAST, NORTH, SOUTH, WEST = mpp_util.directions()

local train_station_planner = {}

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
	local anchor_x, anchor_y, station_direction
	local rail_vertical = true
	local side = 1

	if direction == "east" then
		anchor_x = max_x + 12
		anchor_y = avg_y
		station_direction = SOUTH
		rail_vertical = true
		side = -1
	elseif direction == "north" then
		anchor_x = avg_x
		anchor_y = min_y - 12
		station_direction = EAST
		rail_vertical = false
		side = 1
	elseif direction == "south" then
		anchor_x = avg_x
		anchor_y = max_y + 12
		station_direction = WEST
		rail_vertical = false
		side = -1
	else
		anchor_x = min_x - 12
		anchor_y = avg_y
		station_direction = NORTH
		rail_vertical = true
		side = 1
	end

	print_step(state, "1/5", "create rail line")
	for i = -16, 16 do
		local rail_x = rail_vertical and anchor_x or (anchor_x + i)
		local rail_y = rail_vertical and (anchor_y + i) or anchor_y
		place_ghost(surface, player, force, {
			name = rail_name,
			position = {rail_x, rail_y},
			direction = station_direction,
		})
	end

	print_step(state, "2/5", "create train stop")
	local trainstop_x = rail_vertical and (anchor_x+side*2) or (anchor_x+side*8)
	local trainstop_y = rail_vertical and (anchor_y+side*8)  or (anchor_y+side*2)
	place_ghost(surface, player, force, {
		name = "train-stop",
		position = {trainstop_x, trainstop_y},
		direction = station_direction,
		tags = {station_name = "MPP Mining Loading"},
	})

-- 改进后的代码 (L124-155)
	print_step(state, "3/5", "create loading chests and inserters")
	for i, _ in ipairs(outputs) do
		local lane = i - math.ceil(#outputs / 2)
		
		-- 第一个插入器：从传送带取货到箱子
		local inserter1_x = rail_vertical and (anchor_x + side * 3) or (anchor_x + lane)
		local inserter1_y = rail_vertical and (anchor_y + lane) or (anchor_y + side * 3)
		
		-- 箱子
		local chest_x = rail_vertical and (anchor_x + side * 2) or (anchor_x + lane)
		local chest_y = rail_vertical and (anchor_y + lane) or (anchor_y + side * 2)
		
		-- 第二个插入器：从箱子取货到火车
		local inserter2_x = rail_vertical and (anchor_x + side) or (anchor_x + lane)
		local inserter2_y = rail_vertical and (anchor_y + lane) or (anchor_y + side)
		local inserter_direction = NORTH
		if rail_vertical then
			inserter_direction = side > 0 and EAST or WEST
		else
			inserter_direction = side > 0 and SOUTH or NORTH
		end
		
		-- 放置第一个插入器（传送带→箱子）
		place_ghost(surface, player, force, {
			name = inserter_name,
			position = {inserter1_x, inserter1_y},
			direction = inserter_direction,
		})
		
		-- 放置箱子
		place_ghost(surface, player, force, {
			name = chest_name,
			position = {chest_x, chest_y},
			direction = NORTH,
		})
		
		-- 放置第二个插入器（箱子→铁轨）
		place_ghost(surface, player, force, {
			name = inserter_name,
			position = {inserter2_x, inserter2_y},
			direction = inserter_direction,
		})
	end

	print_step(state, "4/5", "route belts from patch outputs to station")
	for i, src in ipairs(outputs) do
		local lane = i - math.ceil(#outputs / 2)
		local dst_x = rail_vertical and (anchor_x + side * 3) or (anchor_x + lane)
		local dst_y = rail_vertical and (anchor_y + lane) or (anchor_y + side * 3)

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
