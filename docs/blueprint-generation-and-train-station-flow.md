# Mining Patch Planner 蓝图生成过程与“传送带到火车站”实现说明

## 1. 现有矿区蓝图主流程（保持不变）
1. 玩家使用 `mining-patch-planner` 框选资源。
2. `control.lua -> algorithm.on_player_selected_area` 创建布局 `state`。
3. `storage.tasks` 在 `on_tick` 中由 `task_runner.mining_patch_task` 驱动布局状态机。
4. 各布局（如 `simple` / `blueprints`）生成矿机、皮带、电线杆等 ghost。

## 2. 新需求后的火车站逻辑（已改造）

> 目标：`train_station_choice` 仅控制“是否在布局完成后，直接生成传送带到火车站相关 ghost”。

### 关键变化
- **不再发放 train-station 规划蓝图**。
- **不再依赖 `on_built_entity` 锚点点击流程**。
- **与 belt planner 无关系**（belt planner 仍可独立使用，互不依赖）。

### 运行时流程
1. `layout:finish`（`simple` / `blueprints`）阶段检查 `state.train_station_choice`。
2. 若开启：调用 `common.generate_train_station_ghosts(state)`。
3. `common` 直接转发到 `mpp/train_station_planner.lua::generate_from_layout_state(state)`。
4. `train_station_planner`：
   - 从 `state.belts` 提取输出带（`is_output=true`）并转换到世界坐标；
   - 自动计算站点锚点（当前实现：位于输出带左侧固定偏移）；
   - 直接生成 rail / train-stop / chest / inserter / belt / pole 的 ghost；
   - 每个阶段通过 `player.print` 输出步骤日志（`[MPP][TrainStation] 1/5...done`）。

## 3. 流程图（Mermaid）

```mermaid
flowchart TD
  A[布局完成 layout:finish] --> B{train_station_choice?}
  B -->|No| Z[结束]
  B -->|Yes| C[common.generate_train_station_ghosts(state)]
  C --> D[train_station_planner.generate_from_layout_state(state)]
  D --> E[提取输出带并转换世界坐标]
  E --> F[自动计算火车站锚点]
  F --> G[生成轨道和 train-stop ghost]
  G --> H[生成装卸箱/机械臂 ghost]
  H --> I[生成输出带到车站的连接皮带 ghost]
  I --> J[生成供电杆 ghost]
  J --> K[输出日志 done]
```

## 4. 代码边界说明
- `train_station_choice` 只控制“额外 train-station ghosts 生成”开关。
- 皮带规划器（belt planner）仍是独立功能，逻辑与数据流都不参与 train-station 生成。
