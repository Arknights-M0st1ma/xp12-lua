# Nearby METAR & Time（X-Plane 12 / FlyWithLua）

一个键唤出一个真正的小窗口：最近三个「能用的」机场的 METAR 报文，加上你当前
所在位置的时区、格林威治时间（Zulu / GMT）和本地时间。所有数据都来自游戏本身
——不查气象网站、不联网、也不依赖外部数据文件。

- **脚本：** `nearby_weather.lua`
- **平台：** X-Plane 12 + FlyWithLua NG+（**2.8.x**，即带 ImGui 浮动窗口的版本）；
  更旧的 FlyWithLua 会在日志里说明为什么不显示
- **快捷键：** `FlyWithLua/nearby_weather/toggle`，由你自己绑定
- **窗口：** 真正的 X-Plane 浮动窗口——窗框和标题栏由游戏绘制，可以用鼠标拖动、
  拖边缘缩放、点右上角关闭（或者再按一次你的键）
- **读取：** `XPLMGetMETARForAirport`、`apt.dat`、`sim/time/*`
- **写入：** 什么都不写

## 窗口长什么样

```
Nearby METAR & Time                                     _  X     ← 游戏自带的标题栏
────────────────────────────────────────────────────────────────
NEARBY METAR & TIME
KSEA  Seattle-Tacoma Intl                        0.0 NM  000
VFR   241953Z 18005KT 10SM FEW020 SCT250 18/12 A3012 RMK AO2 SLP132
      5 min ago    RWY 11,892 ft asphalt    elev 433 ft
KBFI  Boeing Field King Co Intl                  4.8 NM  005
MVFR  241953Z 20008KT 4SM BR BKN012 OVC025 12/10 A3005
      5 min ago    RWY 9,995 ft asphalt    elev 21 ft
KS50  Auburn Muni                                7.0 NM  211
LIFR  241953Z 00000KT 1/2SM FG VV002 08/08 A3000
      5 min ago    RWY 3,903 ft concrete    elev 20 ft
Zulu (UTC)  19:58:03Z
Local       11:58:03
Zone        UTC-08:00  US Pacific
```

- **飞行天气等级**（VFR 绿 / MVFR 蓝 / IFR 红 / LIFR 紫）由能见度和云底高按
  常用阈值解算，扫一眼就知道这个场子值不值得计划。报文是特选（`SPECI`）时会
  标出来。
- **时长**是该报文距离模拟器当前时刻有多久。显示 `ahead of clock` 说明你在
  实时天气下把模拟时间调到了过去；显示 `stale` 说明这个站很久没更新了。
- **距离和方位**是从你当前位置算的大圆距离与真方位。
- 报文里的长 RMK 会自动折到第二行，不会跑出窗口。

## 字号与可读性（这一版重点修的地方）

X-Plane 的插件窗口以 **boxel**（与设备无关的像素）为单位，所以同一个字号在笔记本
屏幕上正合适、在 4K 屏上就小得看不清。脚本因此按你的屏幕高度**整体缩放**面板
——文字、内边距和窗口尺寸一起放大：

| 屏幕高度 | 缩放 | 窗口尺寸 | 基础字号 |
|---|---|---|---|
| 1080p | 1.25 | 750 × 425 | 约 16 px |
| 1440p | 1.44 | 864 × 490 | 约 19 px |
| 4K | 2.16 | 1296 × 734 | 约 28 px |

仍然想更大或更小？把脚本顶部设置块里的 `text_scale` 改成固定值（例如
`text_scale = 1.8`），或者直接用鼠标拖窗口边缘——文字会按新的宽度重新折行。

## 数据从哪来

| 内容 | 来源 | 说明 |
|---|---|---|
| METAR 报文 | `XPLMGetMETARForAirport(ICAO)` | X-Plane 自己最近一次下载的报文，也就是实时天气模式的原始数据 |
| 附近机场 | `Resources/default scenery/default apt dat/Earth nav data/apt.dat` | X-Plane 自带的机场数据库（apt.dat 12.00），后台流式读取 |
| 跑道铺装 / 长度 | 同上，跑道行 | 用于下面的筛选 |
| 格林威治 / 本地时间 | `sim/time/zulu_time_sec`、`sim/time/local_time_sec` | 时区由这两者的差值推导 |

`XPLMGetMETARForAirport` 是 C 接口，FlyWithLua NG 不带 Lua 绑定，所以脚本通过
FlyWithLua 自带的 LuaJIT FFI 直接调用它（按平台加载 `XPLM_64` /
`XPLM_64.so` / `XPLM.framework`）。脚本**只读取** X-Plane 已经下好的数据，
自己不发起任何网络请求。万一你的 FlyWithLua 构建没有 FFI，窗口会显示
`METAR source unavailable`，其余内容照常显示。

**必须是「实时天气（Real Weather）」用过的会话。** 在静态天气模式下 X-Plane
根本没有报文可给，返回空字符串；这时窗口会明确写 `no METAR data (Real Weather
off?)`，而不是编一个数字给你。另外官方文档说得很清楚：METAR 不等于模拟出来的
天气——游戏会把单点报文和区域预报混合，所以你在飞机上感受到的与这里读到的报文
会有差异，这正是要如实说明的。

## 哪些机场会被列出来

候选来自全球机场库，然后按下面的规则过滤：

| 规则 | 原因 |
|---|---|
| 只保留陆地机场（apt.dat 行代码 1） | 直升机场（17）和水上飞机基地（16）直接排除 |
| 至少有一条**铺装**跑道 | 沥青 / 混凝土，含 apt.dat 12.00 新增的 20-38、50-57 色号系列；草地、土路、碎石、干湖床、水面、冰雪跑道全部排除 |
| 该跑道长度 ≥ 2000 ft | 只留下你现实里真的会用的场子 |
| 具备 4 字符 ICAO 式代码 | 优先用 1302 行的 `icao_id`，只有当它缺失时才退回机场头行的 ID；带本地编号的私人简易跑道会被排除 |
| 这个站确实发报文 | 先查最近的 10 个候选，优先取「有报文」的；不足三个时，用最近的机场补齐并标注 `no METAR reported by X-Plane for this station` |

上面每个数字都是可改的配置（见「调参」）。窗口还会写明用的是哪条跑道，例如
`RWY 11,892 ft asphalt`。

## 安装

1. 把 `nearby_weather.lua` 复制到：

   ```
   <X-Plane 12>/Resources/plugins/FlyWithLua/Scripts/
   ```

2. Plugins → FlyWithLua → **Reload all Lua scripts**（或重启 X-Plane）。

## 绑定你的快捷键

设置 → **键盘**（或 **摇杆**），搜索 **`nearby weather`**：

| 命令 | 用途 |
|---|---|
| `FlyWithLua/nearby_weather/toggle` | 平时就绑这一个——显示 / 隐藏窗口 |

菜单里也有对应入口：Plugins → FlyWithLua → *Nearby METAR & time: show/hide*，
同名宏也能直接点。X-Plane **没有给插件提供「替你绑定按键」的接口**，所以这一次
绑定需要手动完成；绑好后会和其他按键设置一起保存，重载脚本、切换机型都不会丢。

## 调参

所有可调项集中在脚本顶部的 `CFG` 块里。

```lua
local CFG = {
    window_width   = 600,     -- 逻辑尺寸，会乘以 text_scale
    window_height  = 340,
    margin_left    = 30,      -- 首次出现的位置：距屏幕左边
    margin_top     = 30,      -- 距屏幕上边
    text_scale     = 0,       -- 0 = 按屏幕自动，或写固定值如 1.8
    start_visible  = false,   -- 是否一载入就显示
    resizable      = true,    -- 允许拖边缘缩放

    airport_count        = 3,     -- 列出几个机场
    min_paved_runway_ft  = 2000,  -- 铺装跑道短于这个值就排除
    require_icao_code    = true,  -- 只认 4 字符代码
    search_radius_nm     = 150,   -- 搜索半径
    candidate_limit      = 10,    -- 查报文时最多检查几个候选
    prefer_reporting     = true,  -- 优先显示有报文的机场

    scan_on_load         = true,  -- 一载入就开始建机场库
    scan_max_lines       = 4000,  -- 每帧解析多少行 apt.dat
    scan_budget_sec      = 0.004, -- 每帧最多花多少 CPU 时间
    repick_seconds       = 45,    -- 多久重新排一次「最近的机场」
    repick_distance_nm   = 20,    -- 飞出这么远也重排一次
    metar_refresh_sec    = 300,   -- 多久重新读一次 X-Plane 的报文
    zone_table           = true,  -- 是否显示粗略的地区名
    debug                = false, -- 往 Log.txt 多写几行
}
```

常见改法：

- **想让它一直显示？** `start_visible = true`。
- **字还是偏小？** 把 `text_scale` 设成 2.0 或更大（窗口会一起变大）；也可以
  直接用鼠标拖窗口边缘。
- **只想看大机场？** 把 `min_paved_runway_ft` 调大（例如 `6000`）。
- **嫌小场子碍眼？** 保持 `require_icao_code = true` 并提高跑道长度下限；
  「必须有报文」这条本身已经滤掉了绝大多数小场子。
- **想看更远的机场？** 调大 `search_radius_nm` 和 `candidate_limit`。
- **窗口里的文字是英文**：X-Plane 的插件字体没有中日韩字形，写中文会变成空白，
  所以面板刻意只用英文（航空用语本来也是英文）。

## 后台开销

apt.dat 大约上百万行。脚本每个会话只读一次，而且是拆成小片放在飞行循环里读
（默认每帧最多 4000 行、且最多 4 ms 的 CPU 时间），因此是几秒钟的分散开销，
不会卡帧。如果在扫描完成前就打开窗口，表头会显示 `scanning airports 42%`，
读完后列表立即补齐。

解析结果缓存在一个全局表里，所以切换机型或机场（FlyWithLua 会因此重跑所有脚本）
不会再去读一遍 apt.dat，**已经打开的窗口也会被复用而不是重复创建**。如果你更
希望「不用就不花这个开销」，把 `scan_on_load` 设为 `false`，扫描会在你第一次
打开窗口时才开始。

## 需要知道的细节

- **需要 FlyWithLua NG+ 2.8.x。** 窗口是基于 ImGui 浮动窗口实现的；不带这个
  支持的旧版 FlyWithLua 会在日志里写一行说明，然后什么也不显示——因为在
  X-Plane 12 里没有可靠的替代画法（见下面的设计取舍）。
- **没有实时天气就没有报文。** 显示的是 X-Plane 最近一次为这个站下载的报文，
  有可能已经过去一小时——所以每条后面都标了时长。
- **只看默认机场库。** 脚本读的是 FlyWithLua 自带的 default apt.dat。如果你装了
  第三方地景把某个机场改了（换了跑道），窗口描述的可能是默认版本。
- **地区名是粗略的。** `US Pacific`、`China`、`India` 这类标签来自脚本内置的
  一张粗粒度范围表；只有当模拟器给出的 UTC 偏移与范围表一致时才会显示标签，
  因此它永远不会和上面的时钟矛盾。UTC 偏移本身完全来自 X-Plane，是精确值。
  把 `zone_table` 设为 `false` 就只显示偏移。
- **窗口位置只在本次运行内记忆。** 隐藏再显示会回到你拖到的位置；重启 X-Plane
  后回到左上角默认位置。
- **离线验证，未在真机跑过**（作者写这版时手边没有 X-Plane 安装）：见下节。

## 设计取舍

- **为什么用 X-Plane 浮动窗口 + ImGui，而不是自己在屏幕上画一个面板？**
  第一版用的是「自己画」：用 `draw_string` 写字、用 `glBegin_QUADS` 之类的
  即时模式 OpenGL 画背景和边框。真机测试反馈了三件事——字太小、背景透明、
  没有边框而且拖不动。原因是这类自绘面板既拿不到游戏的 UI 缩放，又依赖插件
  绘图上下文里的 GL 状态；而 FlyWithLua NG+ 的 ImGui 浮动窗口由 X-Plane 自己
  提供带标题栏的实心窗框、拖动与缩放，ImGui 的文字还能按倍数缩放。改用之后
  三个问题一次性解决（代价是要求 FlyWithLua 是带 ImGui 的版本）。
- **为什么缩放要按屏幕高度算？** 插件窗口的单位是 boxel，和 Windows 的显示
  缩放、显示器的物理尺寸都无关；同样 13 px 的字在 1080p 上合适，在 4K 上只有
  一半的相对大小。用「屏幕高度 / 1000」并夹在 1.25–2.6 之间，能让三种常见
  分辨率都落在可读区间，同时允许用 `text_scale` 覆盖。
- **为什么用 FFI 读 METAR，而不是找现成的 Lua 接口？** FlyWithLua 本身没有
  暴露任何 METAR 读取函数（`XSB_METAR` 那个变量只在连 VATSIM 的 XSquawkBox
  在线时才有值）。`XPLMGetMETARForAirport` 是官方 SDK 里 XPLM400（也就是
  X-Plane 12）提供的接口，而 FlyWithLua 用的 LuaJIT 自带 FFI，直接调用是最短
  路径。
- **为什么解析 apt.dat 而不去问导航数据库？** 导航数据库接口能给出机场位置和
  代码，但给不出**跑道铺装和长度**，而这两项正是你要的筛选条件。apt.dat 是唯一
  同时包含位置、名称、机场类型和跑道属性的数据源。
- **为什么先查 10 个候选再挑 3 个？** 最近的三个机场里经常有一个不发报文。
  与其把「无报文」占掉一格，不如在最近的十个里优先挑有报文的；只有当确实不足
  三个时，才用最近的机场补齐并如实标注。
- **为什么时区偏移要用两个 dataref 相减？** `sim/time/local_time_sec` 与
  `sim/time/zulu_time_sec` 都是「当天零点起的秒数」，差值（做 24 小时归一化后）
  就是模拟器正在使用的本地偏移，夏令时也一并包含了，比自己去查时区数据库更准。

## 验证情况

作者机器上没有 X-Plane，因此脚本是在一个模拟 FlyWithLua 的环境里跑的：假的
`float_wnd_*` 浮动窗口函数、一个会记录每个文字项位置的小型 ImGui 版式引擎、
假的 FFI，以及一份合成的 apt.dat（里面同时放了铺装、草地、碎石、水面、直升机场、
水上基地和私人简易跑道）。约八十项断言覆盖了：

- 筛选与按距离排序，包括 XP12 新增的 24、53 两个铺装色号；
- METAR 解算：VFR/MVFR/IFR/LIFR、`10SM`/`P6SM`/`1/2SM`/`1 1/2SM`/`M1/4SM`、
  米制能见度（`8000`、`9999`）、`BKN`/`OVC`/`VV` 云底、`CAVOK`、`SPECI`、
  无报文，以及报文时间领先于模拟时钟的情况；
- 时区换算，包括 UTC+8 跨零点、半小时偏移（UTC+05:30）；
- 版面：把每一段文字按量测宽度对照窗口矩形检查，确保任何内容都不会溢出；
  以及很长的 RMK 报文必须正确折行（并缩进到报文列）；
- 窗口本身：第一次按键创建、第二次按键销毁、再次显示时回到你拖到的位置、
  点叉关闭、以及 FlyWithLua 因切换机型重载脚本时**复用**已有窗口而不是重复创建；
- 显示缩放：1080p / 1440p / 4K 三种屏幕下的窗口尺寸与文字大小；
- 后台加载：两万行的文件分多帧切片读取期间进度可见，读完后窗口完整；
- 失败路径：没有 FFI、缺少 apt.dat、FlyWithLua 不带浮动窗口支持、可用机场不足
  三个。

它无法证明的是你机器上的真实情况——你那版 X-Plane 的 apt.dat 具体排布、你的天气
模式实际下载回来的报文内容，以及 ImGui 在你的显卡上的渲染效果。如果发现哪里
不对，把 `debug` 设为 `true`，然后看 `Resources/plugins/FlyWithLua/Log.txt`，
脚本会把读到的东西写进去。

## 文件

```
XP_Nearby_Weather/
  nearby_weather.lua                 脚本本体
  nearby_weather.README.md           英文说明
  nearby_weather.README.zh-CN.md     本文件
```
