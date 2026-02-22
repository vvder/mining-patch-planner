# Train Station Planner 传送带路由逻辑说明

本文档总结 `mpp/train_station_planner.lua` 的核心流程，重点解释“矿区输出带独立汇入车站装载链路”的实现方式。

## 目标

- 每条矿区输出带保持独立，不在路径中错误 merge 到其他回流线。
- 路由先向中间靠拢，再分别进入各自车道。
- 每一格传送带都必须朝向下一个实体（传送带或机械臂），避免“指向空地”。

## 总体流程

`generate_from_layout_state(state)` 分为 4 个主要阶段：

1. **收集输出口**
   - `to_world_belt_outputs` 将布局坐标转换为世界坐标。
   - 仅提取 `belt.is_output == true` 的输出带。
   - 按 `y` 排序，确保输出口与车道映射稳定。

2. **确定车站锚点与轨道方向**
   - 根据 `state.direction_choice`（east/north/south/west）计算：
     - 车站锚点 `anchor_x/anchor_y`
     - 铁轨方向（vertical/horizontal）
     - 站台相对矿区的侧向符号 `side`

3. **放置装载链实体**
   - 每条车道固定放置：
     - 靠轨机械臂
     - 钢箱
     - 靠带机械臂
   - 并记录车道路由参数：
     - `belt_end_x/belt_end_y`：该车道传送带的目标终点
     - `sink_x/sink_y`：最终接收实体（靠带机械臂）位置

4. **生成每条输出带路径**
   - 对每条矿区输出带构造折线关键点 `points`：
     - 起点：`src`
     - 中继点：`mid_x` 或 `mid_y`（向中间靠拢）
     - 车道终点：`belt_end`
   - 使用 `place_belt_path` 沿关键点“逐格”铺带。

## 方向保证机制

### `step_direction`

根据相邻两点 `(x1,y1)->(x2,y2)` 返回单步方向（E/W/S/N）。

### `place_belt_path`

- 段内逐格前进，当前段所有格子都指向“下一格”。
- 最后一格使用 `final_direction`，显式指向 `sink`（通常是靠带机械臂）。

这样可确保：

- 不出现传送带方向与路径断裂的情况。
- 路径终点不会指向空白格。

## 为什么能避免错误汇流

- 每条输出带单独计算 `points`，并绑定独立 `lane` 参数。
- `lane_offset` 用于分开中间过渡路径，降低不同输出带共享同一段的概率。
- 路由终点直接绑定到对应车道的装载实体链，不会错误接到其他分支回流线。

## 关键函数

- `to_world_belt_outputs`：输出带采样与排序
- `step_direction`：相邻点方向推导
- `place_belt_path`：逐格铺带与终点方向修正
- `generate_from_layout_state`：整体流程调度
