# Smart Headphone（X-Plane 12 / FlyWithLua）

给座舱配一副「降噪耳机」：按下一个自定义快捷键，发动机的低频轰鸣淡出，
而 ATC、语音和告警依然清晰——这正是戴上主动降噪（ANR）耳机的真实感受。

- **脚本：** `smart_headphone.lua`
- **平台：** X-Plane 12 + FlyWithLua（X-Friese 版，2023 及以后）
- **快捷键：** `FlyWithLua/smart_headphone/toggle`，由你自己绑定
- **写入：** `%APPDATA%\xplane_smart_headphone.state`（开关状态 + 你的音量配比）
- **只动：** X-Plane 自己的声音声道音量，其他一概不碰

## 它到底做了什么（请先读这一段）

FlyWithLua **无法访问 X-Plane 的音频混音器或音频流**，所以从 Lua 里没法把
一个真正的低通/高通滤波器插进游戏的音频输出。能用的只有 X-Plane 自己的声道
音量——也就是「设置 → 声音」里的那几条滑块——而发动机轰鸣正好集中在
interior / exterior 这两个机身声道里。

于是脚本复刻的是降噪耳机的**体感**：承载噪声的声道淡下去，承载信息的声道
保持满音量。

| 声音声道 | DataRef | 开启降噪后 |
|---|---|---|
| 机内（座舱里听到的轰鸣） | `sim/operation/sound/interior_volume_ratio` | × 0.20（−14 dB） |
| 机外（从外部听到的发动机） | `sim/operation/sound/exterior_volume_ratio` | × 0.15（−16 dB） |
| 环境（风噪 / 雨声 / 机场场噪） | `sim/operation/sound/environment_volume_ratio` | × 0.50（−6 dB） |
| 独立的发动机 / 螺旋桨声道（如果你的版本有） | `.../engine_volume_ratio`、`.../prop_volume_ratio` | × 0.15 |
| 无线电（ATC 与语音）、副驾、UI、总音量 | — | 完全不动 |

这些系数都是可配置的，不是写死的魔法数字，见下面的「调参」。

## 安装

1. 把 `smart_headphone.lua` 复制到：

   ```
   <X-Plane 12>/Resources/plugins/FlyWithLua/Scripts/
   ```

2. Plugins → FlyWithLua → **Reload all Lua scripts**（或重启 X-Plane）。

## 绑定你的快捷键

设置 → **键盘**（或 **摇杆**），搜索 **`smartheadphone`**：

| 命令 | 用途 |
|---|---|
| `FlyWithLua/smart_headphone/toggle` | 平时就绑这一个——开/关降噪 |
| `FlyWithLua/smart_headphone/on` | 单独的「开启降噪」键 |
| `FlyWithLua/smart_headphone/off` | 单独的「关闭降噪」键 |
| `FlyWithLua/smart_headphone/reset` | 兜底：恢复满音量并忘掉记忆的配比 |

X-Plane **没有给插件提供「替你绑定按键」的接口**，所以这一次绑定需要手动完成。
绑好后会和其他按键设置一起保存，重载脚本、切换机型都不会丢。

## 调参

所有你可能想改的东西都在脚本顶部的 `CONFIG` 块里。

```lua
local FADE_SECS = 0.8      -- 设为 0 就是瞬间切换，没有过渡
local SHOW_TOAST = true    -- 是否显示「ANR on / off」的短暂屏幕提示

local CHANNELS = {
    { path = "sim/operation/sound/interior_volume_ratio",    factor = 0.20 },
    { path = "sim/operation/sound/exterior_volume_ratio",    factor = 0.15 },
    { path = "sim/operation/sound/environment_volume_ratio", factor = 0.50 },
    ...
}
```

`factor` 表示开启降噪时该声道还保留多少：

| factor | 0.5 | 0.25 | 0.15 | 0.10 | 0.05 |
|---|---|---|---|---|---|
| 衰减量 | −6 dB | −12 dB | −16 dB | −20 dB | −26 dB |

- **想更安静：** 把 factor 调低（0.10 已接近真实耳机的水准）。
- **想放过某个声道：** 把它的 factor 写成 `1.0`。
- **只想去掉座舱里的轰鸣：** 删掉 exterior 和 environment 两行。
- **除 ATC 外全部降低：** 加入 `master_volume_ratio`，系数约 0.2。
  （不推荐：告警音也会一起变小。）

## 需要知道的细节

- **开启降噪期间，这几个滑块的归属权在脚本手里。** 不要在「设置 → 声音」里
  跟它对着改：先关掉降噪，改好你想要的配比，再打开——新的配比会成为基准。
  脚本不会每帧强行回写，所以你在游戏里手动拖动的值永远生效。
- **记住你的配比，而不是粗暴复位。** 如果你的机内音量本来是 0.9，降噪时是
  0.18，关掉后还你 0.9——它绝不会假设一切都是 1.0。
- **状态能跨机型切换。** FlyWithLua 会在每次载入飞机时重载所有脚本；脚本把
  「是否开启」和你的音量配比写进 `%APPDATA%\xplane_smart_headphone.state`，
  因此重载既不会忘记降噪状态，也不会把滑块遗留在衰减后的数值上
  （更不会二次衰减）。
- **没地方写文件也能用。** 如果 `%APPDATA%` 不可写，脚本退化为仅本次会话记忆，
  并在日志里说明。
- **声音卡住了？** 执行一次 `reset` 命令，或者直接删掉那个 state 文件：
  受管声道会恢复到 1.0，记忆的配比也会被清掉。
- **缺失的声道**会在日志里带上原因（`not present` / `read-only`）并列出来，
  然后被跳过——dataref 名字写错绝不会让脚本崩掉。想知道你的版本到底有哪些：

  ```
  findstr /i volume_ratio "<X-Plane 12>\Resources\plugins\DataRefs.txt"
  ```

  把找到的名字加进 `CHANNELS` 即可。日志文件位置：
  `Resources/plugins/FlyWithLua/FlyWithLua_debug.txt`。
- **告警音**由飞机自身的系统发出（不少机模也走 `interior` 声道），所以把
  interior 削得特别狠时，GPWS 之类的提示音也会跟着小。想要「轰鸣没了但告警
  依旧响亮」，请配合下面的 EQ 方案一起用。

## 想要真正的低频滤波

如果你要的是真的把低频**能量**滤掉，而不是改声道配比，那只能在 Windows 的
音频输出上做，也就是在 X-Plane 之外：

- **[Equalizer APO](https://sourceforge.net/projects/equalizerapo/)**（配合
  Peace 图形界面）挂在输出设备上：在 80–150 Hz 附近放一个高通或低架滤波，
  轰鸣会真的消失——对**所有**游戏音频生效。
- **Voicemeeter** 配一个 VST / 图形均衡器，效果相同，而且可以在飞行中用它
  自己的快捷键开关。

代价是：均衡器分不清发动机轰鸣和无线电语音，切得深了 ATC 会发闷。
`smart_headphone` 正好是它的互补：把**信息类**声道保持在满音量，只把轰鸣压下去。
两者叠加是最实际的组合。

## 为什么这样设计（决策记录）

- **为什么不做真滤波？** Lua 够不到混音器和音频流；X-Plane 暴露的声音
  dataref 只有音量比例。更进一步需要编译插件，而且同样拿不到 FMOD 的输出，
  所以才有了上面那条系统 EQ 的路子。
- **为什么动 interior/exterior 而不是 master？** master 会把 ATC 和告警音
  一起带走。降噪的隐喻是「噪声消失，信息保留」。
- **为什么是渐变而不是瞬变？** 真耳机是有过渡的。0.8 秒的 ease-out 听起来像
  「耳机稳定下来了」，而不是一次卡顿。不同意就把 `FADE_SECS` 设成 0。
- **为什么要记住用户的配比？** 直接恢复成 1.0 会悄悄毁掉你原本的设置。脚本
  记录它读到的数值并原样还给你；而且它会识别「这个数值已经是我们自己的衰减
  结果」，所以重载不会把衰减值误当成新基准。
- **为什么需要一个 state 文件？** 没有它，FlyWithLua 的「载入飞机即重载脚本」
  会让滑块停留在衰减态、而脚本却以为自己没开启——这是用户能看见的 bug，
  所以必须落盘。
- **为什么运行时探测 dataref？** 名字写错应该退化成一行日志，而不是让脚本
  加载失败。脚本会先试 XPLM 底层接口（`XPLMFindDataRef` /
  `XPLMCanWriteDataRef`），再退回 FlyWithLua 自己的 `dataref()` 绑定；只读
  声道会被跳过，而不是每帧写一次报一次错。
- **为什么切换命令用的是「重新武装」而不是简单去抖？** `create_command` 的
  三个回调槽位在「按下」和「按住（每帧触发）」之间的语义，在不同 FlyWithLua
  版本里并不一致；单纯去抖的话，只要按键按得超过去抖窗口就会再切一次。所以
  脚本改用锁存：触发一次后保持「解除武装」，直到命令安静 0.4 秒才重新武装——
  按下、长按、键盘自动重复三种情况都恰好只切换一次。
- **没做「长按透听」（talk-through）**：那依赖各版本不一致的按住回调语义，
  与其发布一个不稳定的功能，不如先不做。

## 验证情况

脚本逻辑已在离线环境下用桩件模拟 FlyWithLua / X-Plane API 跑过（`texlua`，
不需要游戏本体）：37 项检查覆盖了渐变曲线、配比记忆的数学、开启状态下重载
脚本的路径、长按快捷键、只读与缺失的 dataref、`reset` 兜底，以及完全无处写
文件的机器——并且**两种 dataref 绑定模式**各跑一遍。

它无法证明的是：你机器上 X-Plane 自己的 dataref 命名（本项目没有在真实
X-Plane 安装上测过）。正因如此，脚本会在载入时探测声道并把结果写进日志：
如果你的版本命名不同，日志会告诉你，改一下 `CHANNELS` 就行。

## 文件

```
Scripts/
  smart_headphone.lua                   脚本本体
  smart_headphone.README.md             英文说明
  smart_headphone.README.zh-CN.md       本文件

%APPDATA%\
  xplane_smart_headphone.state          开关状态 + 音量配比（脚本唯一写入的文件）
```
