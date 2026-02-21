local mpp_util = require("mpp.mpp_util")
local EAST, NORTH, SOUTH, WEST = mpp_util.directions()

local train_station_planner = {}

local function print_step(state, step, message)
	if state.player and state.player.valid then
		state.player.print({"", "[MPP][TrainStation] ", step, ": ", message})
	end
end

---@param player_data PlayerData
function train_station_planner.clear_stack(player_data)
	player_data.train_station_planner_stack = {}
end

---@param player LuaPlayer|integer
---@param spec TrainStationPlannerSpecification
function train_station_planner.push_step(player, spec)
	player = type(player) == "number" and player or player.index
	---@type PlayerData
	local player_data = storage.players[player]
	player_data.train_station_planner_stack = player_data.train_station_planner_stack or {}
	table.insert(player_data.train_station_planner_stack, spec)
end

---@param state MinimumPreservedState
---@param spec TrainStationPlannerSpecification
function train_station_planner.give_blueprint(state, _spec)
	local ply = state.player
	local stack = ply.cursor_stack --[[@as LuaItemStack]]
	stack.set_stack("mpp-blueprint-belt-planner")

	stack.set_blueprint_entities({
		{
			name = state.belt_choice,
			position = {1, 1},
			direction = defines.direction.north,
			entity_number = 1,
			tags = {mpp_train_station_planner = "main"},
		},
	})
	ply.cursor_stack_temporary = true
	return stack
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

---@param state TrainStationPlannerState
function train_station_planner.layout(state)
	local surface = state.surface
	local player = state.player
	local force = player.force
	local spec = state.spec
	if spec == nil or spec.count == nil or spec.count < 1 then
		print_step(state, "skip", "no belt outputs available")
		return
	end

	local anchor_x, anchor_y = math.floor(state.anchor_x), math.floor(state.anchor_y)
	local station_direction = state.anchor_direction
	local belt_name = spec.belt_choice
	local chest_name = state.options and state.options.chest_name or "steel-chest"
	local inserter_name = state.options and state.options.inserter_name or "fast-inserter"
	local rail_name = "straight-rail"
	local station_name = state.options and state.options.station_name or "MPP Mining Loading"

	print_step(state, "1/5", "create rail line")
	if station_direction == NORTH or station_direction == SOUTH then
		for i = -8, 8 do
			place_ghost(surface, player, force, {name = rail_name, grid_x = 0, grid_y = 0, position = {anchor_x, anchor_y + i}, direction = station_direction})
		end
	else
		for i = -8, 8 do
			place_ghost(surface, player, force, {name = rail_name, grid_x = 0, grid_y = 0, position = {anchor_x + i, anchor_y}, direction = station_direction})
		end
	end

	print_step(state, "2/5", "create train stop")
	place_ghost(surface, player, force, {
		name = "train-stop",
		grid_x = 0,
		grid_y = 0,
		position = {anchor_x, anchor_y},
		direction = station_direction,
		tags = {station_name = station_name},
	})

	print_step(state, "3/5", "create loading chests and inserters")
	local side = (station_direction == NORTH or station_direction == EAST) and 1 or -1
	for i = 1, spec.count do
		local y = anchor_y + i - math.ceil(spec.count / 2)
		place_ghost(surface, player, force, {name = chest_name, grid_x = 0, grid_y = 0, position = {anchor_x + side * 2, y}, direction = NORTH})
		place_ghost(surface, player, force, {name = inserter_name, grid_x = 0, grid_y = 0, position = {anchor_x + side, y}, direction = side > 0 and EAST or WEST})
	end

	print_step(state, "4/5", "route belts from patch outputs to station")
	for i = 1, spec.count do
		local belt = spec[i]
		local src_x, src_y = math.floor(belt.world_x), math.floor(belt.world_y)
		local dst_x = anchor_x + side * 3
		local dst_y = anchor_y + i - math.ceil(spec.count / 2)

		local x1, x2 = math.min(src_x, dst_x), math.max(src_x, dst_x)
		for x = x1, x2 do
			place_ghost(surface, player, force, {name = belt_name, grid_x = 0, grid_y = 0, position = {x, src_y}, direction = src_x <= dst_x and EAST or WEST})
		end

		local y1, y2 = math.min(src_y, dst_y), math.max(src_y, dst_y)
		for y = y1, y2 do
			place_ghost(surface, player, force, {name = belt_name, grid_x = 0, grid_y = 0, position = {dst_x, y}, direction = src_y <= dst_y and SOUTH or NORTH})
		end
	end

	print_step(state, "5/5", "add power poles")
	for i = -6, 6, 3 do
		place_ghost(surface, player, force, {name = "medium-electric-pole", grid_x = 0, grid_y = 0, position = {anchor_x + side * 5, anchor_y + i}, direction = NORTH})
	end

	print_step(state, "done", "train station blueprint generated")
end

return train_station_planner
