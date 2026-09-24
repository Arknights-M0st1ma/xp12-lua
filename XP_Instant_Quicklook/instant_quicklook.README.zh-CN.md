# 瞬时快速视角（Instant Quick-Looks，X-Plane 12 / FlyWithLua）

让“跳转到已保存的 3D 座舱视角”**瞬间切换**，而不是缓慢滑过去。

- **脚本：** `instant_quicklook.lua`（只负责“调用/还原”，保存仍然由 X-Plane 自己完成）
- **存储：** 使用 X-Plane 自己的 `<机型>_prefs.txt`（位于机型文件夹内）。脚本不保留任何自己的文件，
  它只是**读取**已保存的视角。
- **平台：** X-Plane 12，FlyWithLua（X-Friese 版本，2023 及以后）

## 工作原理

- **保存**：照常用 X-Plane 的方式保存（Ctrl+小键盘 / 原生的 `quick_look_N_mem` 绑定）。脚本**不**负责保存。
- **调用**（`FlyWithLua/quicklook/recall_N`）：瞬间跳到第 N 个已保存视角。
  它从 `<机型>_prefs.txt` 读取姿态，然后直接写入 `pilots_head_x/y/z` 和 `pilots_head_psi/the`
  ——直接写入不会产生缓动过渡。

一次性还原**头部位置 + 视线角度**，并且是瞬时的。命令编号 N 对应 X-Plane 的“location #N”，
也就是原生槽位 (N-1)。

## 使用方法

1. 重新加载脚本：Plugins（插件）→ FlyWithLua → **Reload all Lua scripts**（重新加载全部 Lua 脚本），
   或者直接重启 X-Plane。
2. 进入 Settings（设置）→ Keyboard / Joystick（键盘 / 摇杆），搜索 **`quicklook`**，
   你会看到 20 条命令 `FlyWithLua/quicklook/recall_1..20`。
3. 把你的视角按键绑定到 `recall_N`，**而不是**绑定到 `sim/view/quick_look_(N-1)`。
   保存视角仍然用 X-Plane 原来的方式。

## 缩放（Zoom）

座舱缩放是 X-Plane 内部的 `zoom_rat`。实测确认它**既不可读也不可写**为 dataref，
而全局 FOV 的 dataref（`field_of_view_deg` / `vertical_field_of_view_deg`）是**全局图形设置**
（写它们会把你的全局/垂直 FOV 重置掉）——所以缩放无法从 Lua 直接设置。

默认行为：完全不碰缩放（位置 + 角度已完全瞬时）。

对于**少数确实需要特定缩放的视角**，把它们列在脚本顶部的 `ZOOM_SLOTS` 中，
例如 `local ZOOM_SLOTS = { [2] = true }`。对于这些槽位，调用时会：

1. 先触发**原生**的 `sim/view/quick_look_(N-1)`，由它**原生地**恢复该视角的缩放
   （以及位置/角度）——这个过程约 0.5 秒的滑行；然后
2. 在 `OVERRIDE_SECS`（约 0.7 秒）内**每帧**覆盖 `pilots_head_*`，
   于是位置 + 角度**瞬时切换**，而只有缩放在滑行到目标值。

这样保留了所有原生相机物理/特效（没有接管相机）。这些槽位的缩放不是瞬时的——
它会像原生快速视角一样在约 0.5 秒内缓动到位。真正瞬时的缩放需要走 C / `XPLMControlCamera`
的路线（但那会丢失原生物理效果）。

如果某个 `ZOOM_SLOTS` 视角的位置/角度仍然在滑行，说明逐帧覆盖
（`instant_quicklook_hold`）在时序上输掉了竞争；可以试着把它移到
`do_every_draw`，或者增大 `OVERRIDE_SECS`。

### 小技巧：让所有视角共用同一个缩放（数据侧做法）

如果你只是想让所有视角都用同一个缩放值，可以在关闭 X-Plane 的情况下编辑
`<机型>_prefs.txt`，把每个 `_iql_zoom_rat_N` 都设成同一个值（比如复制你最喜欢那个视角的值）。
这样就不再需要任何 `ZOOM_SLOTS` 滑行——每个视角本身就已经是那个缩放了。
（之后在游戏里重新保存某个视角会再次覆盖它的缩放值。）

## 问题所在 / 技巧所在

`sim/view/quick_look_0..19`（“Go to saved 3-D cockpit location #1..20”）会让相机在约 0.5 秒内
**缓动**过去，而且**没有任何原生设置或 dataref** 可以关掉它（已通过检索
`Resources/plugins/DataRefs.txt` + `Commands.txt` 以及网上搜索确认）。但 3D 座舱姿态**是**可写的：

| Dataref | 含义 |
|---|---|
| `sim/graphics/view/pilots_head_x` / `_y` / `_z` | 头部位置（相对重心，单位 m） |
| `sim/graphics/view/pilots_head_psi` / `_the` | 朝向 / 俯仰（单位 度） |

写这些 dataref 会让相机瞬间移动。调用时会先触发 `sim/view/3d_cockpit_cmnd_look`
以确保处于 3D 座舱，然后再把姿态瞬时写入。（不使用滚转——快速视角本来也不存储它。）

## 为什么这样设计（决策记录）

- **为什么不干脆禁用动画？** 不存在这样的原生开关（见上）。
- **为什么自己实现 `recall_N`，而不是拦截原生命令？** 这个 FlyWithLua 版本**无法**挂接已有命令
  ——已通过扫描 `win_x64/FlyWithLua.xpl` 验证：里面没有 `replace_command` / `wrap_command`。
  所以按键必须指向我们自己的命令，也就意味着需要重新绑定调用键。
- **为什么脚本也不负责保存？** 早期版本包装了原生保存命令，用来加一个屏幕上的确认提示；
  后来因为没人用而移除。保存完全交给 X-Plane，它是唯一的事实来源。
- **为什么用 FlyWithLua 而不是编译版插件？** 抗更新（修复只是改文本 + 重新加载，永远不用重新编译），
  且稳态开销为零。代价是：你需要重新绑定调用键。

## 已知注意事项

- **写盘时机：** X-Plane 可能只在切换机型 / 退出时才写 `_prefs.txt`，而不是每次保存都写。
  所以你在**本次会话中**新保存的视角，可能要等文件被写盘（重新加载机型 / 重启）之后才能被调用读到。
  上次会话保存的视角则完全正常。
- **缩放：** 除了 `ZOOM_SLOTS` 之外不会恢复（见“缩放”一节）。我们从不会去写全局 FOV 的 dataref，
  所以你自定义的/垂直 FOV 永远不会被打扰。
- **外部视角槽位：** 只有 3D 座舱视角（`v_3dc`）会按预期被还原；环绕/外部视角槽位不做处理。

## 如果将来走 C 路线（未来）

使用 `XPLMControlCamera` 的编译版插件可以做到瞬时的位置 + 角度 + **缩放**，
就像 X-Camera / A Better Camera 那样。代价是：需要 X-Plane SDK + C 工具链
（你已有 VS2019；SDK 需要另行下载），而且每次修复都要重新编译。
完全接管的另一个代价是：除非自己重新实现，否则会丢失原生物理/头部晃动/自由环视——
这也是我们留在 Lua 里的原因。

## 文件

```
Scripts/
  instant_quicklook.lua                 脚本本体
  instant_quicklook.README.md           本说明（英文原版）
  instant_quicklook.README.zh-CN.md     本说明（中文版）

<机型文件夹>/                           例如 Aircraft/.../FlightFactor 777.../
  <机型>_prefs.txt                      X-Plane 自己的偏好文件（我们只读它）
```

## X-Plane 原生快速视角的存储格式（参考）

在 `<机型>_prefs.txt` 中，每个槽位 N（0..19）：

```
_iql_view_type_N   v_3dc        视角类型（3D 座舱）
_iql_pe_x_N/_y_N/_z_N           飞行员眼位坐标    -> 我们的 pilots_head_x/y/z
_iql_look_os_psi_N/_the_N       视线朝向/俯仰     -> 我们的 pilots_head_psi/the
_iql_zoom_rat_N                 缩放**倍率**（是倍数，不是角度；不可写）
_iql_circ_psi/the/dis_N         环绕参数（仅外部视角使用）
_iql_pscroll_x/y_pix_N          2D 面板滚动位置
```

## 相关 dataref / 命令（XP12）

- `sim/view/quick_look_0..19` —— 原生“跳转到已保存位置”（带缓动动画）
- `sim/view/quick_look_0..19_mem` —— 原生“记忆/保存”（用它来保存视角）
- `sim/view/3d_cockpit_cmnd_look` —— 进入 3D 座舱
- `sim/graphics/view/pilots_head_*` —— 我们用来瞬时跳转的可写姿态 dataref
