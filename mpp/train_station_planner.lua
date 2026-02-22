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

---@param x1 number
---@param y1 number
---@param x2 number
---@param y2 number
---@return defines.direction
---根据相邻两点计算传送带方向，用于保证每一段都指向“下一格实体”。
local function step_direction(x1, y1, x2, y2)
	if x2 > x1 then return EAST end
	if x2 < x1 then return WEST end
	if y2 > y1 then return SOUTH end
	return NORTH
end

---@param surface LuaSurface
---@param player LuaPlayer
---@param force LuaForce
---@param belt_name string
---@param points table[]
---@param final_direction defines.direction
---按折线关键点逐格铺设传送带：
---1) 段内每格统一朝向下一格；
---2) 最后一格按 final_direction 指向终点实体（通常是靠带侧机械臂）。
local function place_belt_path(surface, player, force, belt_name, points, final_direction)
	if #points == 0 then return end
	for i = 1, #points - 1 do
		local point = points[i]
		local next_point = points[i+1]
		local direction = step_direction(point.x, point.y, next_point.x, next_point.y)
		local dx = next_point.x == point.x and 0 or (next_point.x > point.x and 1 or -1)
		local dy = next_point.y == point.y and 0 or (next_point.y > point.y and 1 or -1)
		local x, y = point.x, point.y
		place_ghost(surface, player, force, {
			name = belt_name,
			position = {x, y},
			direction = direction,
		})
		while x ~= next_point.x or y ~= next_point.y do
			x = x + dx
			y = y + dy
			place_ghost(surface, player, force, {
				name = belt_name,
				position = {x, y},
				direction = direction,
			})
		end
	end
	local last = points[#points]
	place_ghost(surface, player, force, {
		name = belt_name,
		position = {last.x, last.y},
		direction = final_direction,
	})
end

---@param state MinimumPreservedState
---@param belts BeltSpecification[]
---@return table[]
---将布局内部坐标系中的输出带起点，转换为世界坐标并按 y 排序，稳定映射到站台车道。

local function step_direction(x1, y1, x2, y2)
	if x2 > x1 then return EAST end
	if x2 < x1 then return WEST end
	if y2 > y1 then return SOUTH end
	return NORTH
end

---@param surface LuaSurface
---@param player LuaPlayer
---@param force LuaForce
---@param belt_name string
---@param points table[]
---@param final_direction defines.direction
local function place_belt_path(surface, player, force, belt_name, points, final_direction)
	if #points == 0 then return end
	for i = 1, #points - 1 do
		local point = points[i]
		local next_point = points[i+1]
		local direction = step_direction(point.x, point.y, next_point.x, next_point.y)
		local dx = next_point.x == point.x and 0 or (next_point.x > point.x and 1 or -1)
		local dy = next_point.y == point.y and 0 or (next_point.y > point.y and 1 or -1)
		local x, y = point.x, point.y
		place_ghost(surface, player, force, {
			name = belt_name,
			position = {x, y},
			direction = direction,
		})
		while x ~= next_point.x or y ~= next_point.y do
			x = x + dx
			y = y + dy
			place_ghost(surface, player, force, {
				name = belt_name,
				position = {x, y},
				direction = direction,
			})
		end
	end
	local last = points[#points]
	place_ghost(surface, player, force, {
		name = belt_name,
		position = {last.x, last.y},
		direction = final_direction,
	})
end

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
	-- 阶段 0：收集矿区输出口。
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
	local anchor_x, anchor_y, station_direction
	local rail_vertical = true
	local side = 1

	-- 阶段 1：依据玩家方向选择车站锚点与铁轨朝向。
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
	local lanes = {}
	for i, _ in ipairs(outputs) do
		local lane = i - math.ceil(#outputs / 2)
		
		-- 从铁轨边缘向外布局：插入器-箱子-插入器-传送带。
		local inserter_rail_x = rail_vertical and (anchor_x + side * 2) or (anchor_x + lane)
		local inserter_rail_y = rail_vertical and (anchor_y + lane) or (anchor_y + side * 2)

		local chest_x = rail_vertical and (anchor_x + side * 3) or (anchor_x + lane)
		local chest_y = rail_vertical and (anchor_y + lane) or (anchor_y + side * 3)

		local inserter_belt_x = rail_vertical and (anchor_x + side * 4) or (anchor_x + lane)
		local inserter_belt_y = rail_vertical and (anchor_y + lane) or (anchor_y + side * 4)
		local belt_end_x = rail_vertical and (anchor_x + side * 5) or (anchor_x + lane)
		local belt_end_y = rail_vertical and (anchor_y + lane) or (anchor_y + side * 5)
		local inserter_direction = NORTH
		if rail_vertical then
			inserter_direction = side > 0 and EAST or WEST
		else
			inserter_direction = side > 0 and SOUTH or NORTH
		end
		-- local reverse_inserter_direction = (inserter_direction + 4) % 8
		local near_rail_direction = inserter_direction
		local near_belt_direction = inserter_direction
		
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
		
		place_ghost(surface, player, force, {
			name = inserter_name,
			position = {inserter_belt_x, inserter_belt_y},
			direction = near_belt_direction,
		})

		-- 每条矿区输出带对应一个独立站台车道，不在中途做 merge。
		lanes[i] = {
			belt_end_x = belt_end_x,
			belt_end_y = belt_end_y,
			sink_x = inserter_belt_x,
			sink_y = inserter_belt_y,
		}
	end

	print_step(state, "4/5", "route belts from patch outputs to station")
	local lane_center = math.ceil(#outputs / 2)
	for i, src in ipairs(outputs) do
		local lane = lanes[i]
		local lane_offset = (i - lane_center) * 2
		local points = {{x = src.x, y = src.y}}

		-- 路由策略：先向中间靠拢（mid 点），再进入各自目标车道，防止错误汇流。
		if rail_vertical then
			local mid_x = align_odd(math.floor((src.x + lane.belt_end_x) / 2)) + lane_offset
			if mid_x ~= src.x then points[#points+1] = {x = mid_x, y = src.y} end
			if lane.belt_end_y ~= src.y then points[#points+1] = {x = mid_x, y = lane.belt_end_y} end
			if lane.belt_end_x ~= mid_x then points[#points+1] = {x = lane.belt_end_x, y = lane.belt_end_y} end
		else
			local mid_y = align_odd(math.floor((src.y + lane.belt_end_y) / 2)) + lane_offset
			if mid_y ~= src.y then points[#points+1] = {x = src.x, y = mid_y} end
			if lane.belt_end_x ~= src.x then points[#points+1] = {x = lane.belt_end_x, y = mid_y} end
			if lane.belt_end_y ~= mid_y then points[#points+1] = {x = lane.belt_end_x, y = lane.belt_end_y} end
		end

		-- 最后一格必须朝向靠带侧机械臂，保证传送方向上有实体。
		local final_direction = step_direction(lane.belt_end_x, lane.belt_end_y, lane.sink_x, lane.sink_y)
		place_belt_path(surface, player, force, belt_name, points, final_direction)
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
