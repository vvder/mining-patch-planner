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

	local avg_y = 0
	local min_x = outputs[1].x
	for _, o in ipairs(outputs) do
		avg_y = avg_y + o.y
		if o.x < min_x then min_x = o.x end
	end
	avg_y = math.floor(avg_y / #outputs)

	local anchor_x = min_x - 18
	local anchor_y = avg_y
	local station_direction = NORTH
	local side = 1

	print_step(state, "1/5", "create rail line")
	for i = -8, 8 do
		place_ghost(surface, player, force, {
			name = rail_name,
			position = {anchor_x, anchor_y + i},
			direction = station_direction,
		})
	end

	print_step(state, "2/5", "create train stop")
	place_ghost(surface, player, force, {
		name = "train-stop",
		position = {anchor_x, anchor_y},
		direction = station_direction,
		tags = {station_name = "MPP Mining Loading"},
	})

	print_step(state, "3/5", "create loading chests and inserters")
	for i, _ in ipairs(outputs) do
		local y = anchor_y + i - math.ceil(#outputs / 2)
		place_ghost(surface, player, force, {
			name = chest_name,
			position = {anchor_x + side * 2, y},
			direction = NORTH,
		})
		place_ghost(surface, player, force, {
			name = inserter_name,
			position = {anchor_x + side, y},
			direction = side > 0 and EAST or WEST,
		})
	end

	print_step(state, "4/5", "route belts from patch outputs to station")
	for i, src in ipairs(outputs) do
		local dst_x = anchor_x + side * 3
		local dst_y = anchor_y + i - math.ceil(#outputs / 2)

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

	print_step(state, "5/5", "add power poles")
	for i = -6, 6, 3 do
		place_ghost(surface, player, force, {
			name = pole_name,
			position = {anchor_x + side * 5, anchor_y + i},
			direction = NORTH,
		})
	end

	print_step(state, "done", "belt-to-train-station ghosts generated")
end

return train_station_planner
