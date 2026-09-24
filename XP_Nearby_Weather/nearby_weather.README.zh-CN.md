# Nearby METAR & Time（X-Plane 12 / FlyWithLua）

一个键，一个小窗口，出现在屏幕左上角：最近三个「能用的」机场的 METAR 报文，
外加你当前所在位置的时区、格林威治时间（Zulu / GMT）和本地时间。
所有数据都来自游戏本身——不查气象网站、不联网、也不依赖外部数据文件。

- **脚本：** `nearby_weather.lua`
- **平台：** X-Plane 12 + FlyWithLua NG（X-Friese 版，2023 及以后）
- **快捷键：** `FlyWithLua/nearby_weather/toggle`，由你自己绑定
- **读取：** `XPLMGetMETARForAirport`、`apt.dat`、`sim/time/*` dataref
- **写入：** 什么都不写

## 窗口长什么样

```
NEARBY METAR & TIME
────────────────────────────────────────────────────────────────
KSEA  Seattle-Tacoma Intl                        0.0 NM  000
VFR   241953Z 18005KT 10SM FEW020 SCT250 18/12 A3012     5 min
      RMK AO2 SLP132
      RWY 11,892 ft asphalt    elev 433 ft
────────────────────────────────────────────────────────────────
KBFI  Boeing Field King Co Intl                  4.8 NM  005
MVFR  241953Z 20008KT 4SM BR BKN012 OVC025 12/10 A3005    5 min
      RWY 9,995 ft asphalt    elev 21 ft
────────────────────────────────────────────────────────────────
KS50  Auburn Muni                                7.0 NM  211
LIFR  241953Z 00000KT 1/2SM FG VV002 08/08 A3000         5 min
      RWY 3,903 ft concrete    elev 20 ft
────────────────────────────────────────────────────────────────
Zulu (UTC)  19:58:03Z              Local   11:58:03
Zone        UTC-08:00  US Pacific
```

- **飞行天气等级**（VFR 绿 / MVFR 蓝 / IFR 红 / LIFR 紫）由能见度和云底高按
  常用阈值直接解算，扫一眼就知道这个场子值不值得计划。报文是特选（`SPECI`）时
  会标出来。
- **时长**是该报文距离模拟器当前时刻有多久。显示 `ahead of clock` 说明你在
  开启实时天气的情况下把模拟时间调到了过去；显示 `stale` 说明这个站很久没更新了。
- **距离和方位**是从你当前位置算的大圆距离与真方位。

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
    panel_width     = 560,     -- 像素
    margin_x        = 28,      -- 距左边界
    margin_y        = 28,      -- 距上边界
    start_visible   = false,   -- 是否一载入就显示
    font            = "proportional",   -- 4K 屏可以改成 "helvetica18"

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
- **只想看大机场？** 把 `min_paved_runway_ft` 调大（例如 `6000`）。
- **嫌小场子碍眼？** 保持 `require_icao_code = true` 并提高跑道长度下限；
  「必须有报文」这条本身已经滤掉了绝大多数小场子。
- **想看更远的机场？** 调大 `search_radius_nm` 和 `candidate_limit`。
- **4K 屏上字太小？** 插件绘制的文字不会跟着游戏 UI 缩放走，这是 FlyWithLua 的
  限制。把 `font` 改成 `"helvetica18"` 换用更大的内置点阵字体，同时可以调大
  `panel_width`。
- **窗口里的文字是英文**：X-Plane 的插件字体没有中日韩字形，写中文会变成空白，
  所以面板刻意只用英文（航空用语本来也是英文）。

## 后台开销

apt.dat 大约上百万行。脚本每个会话只读一次，而且是拆成小片放在飞行循环里读
（默认每帧最多 4000 行、且最多 4 ms 的 CPU 时间），因此是几秒钟的分散开销，
不会卡帧。如果在扫描完成前就打开窗口，表头会显示 `scanning airports 42%`，
读完后列表立即补齐。

解析结果缓存在一个全局表里，所以切换机型或机场（FlyWithLua 会因此重跑所有脚本）
不会再去读一遍 apt.dat。如果你更希望「不用就不花这个开销」，把
`scan_on_load` 设为 `false`，扫描会在你第一次打开窗口时才开始。

## 需要知道的细节

- **没有实时天气就没有报文。** 显示的是 X-Plane 最近一次为这个站下载的报文，
  有可能已经过去一小时——所以每条后面都标了时长。
- **只看默认机场库。** 脚本读的是 FlyWithLua 自带的 default apt.dat。如果你装了
  第三方地景把某个机场改了（换了跑道），窗口描述的可能是默认版本。
- **地区名是粗略的。** `US Pacific`、`China`、`India` 这类标签来自脚本内置的
  一张粗粒度范围表；只有当模拟器给出的 UTC 偏移与范围表一致时才会显示标签，
  因此它永远不会和上面的时钟矛盾。UTC 偏移本身完全来自 X-Plane，是精确值。
  把 `zone_table` 设为 `false` 就只显示偏移。
- **离线验证，未在真机跑过。** 作者写这个脚本时手边没有 X-Plane 安装，脚本是在
  模拟 FlyWithLua 接口的环境里验证的（见下节）。

## 设计取舍

- **为什么用 FFI 而不是找现成的 Lua 接口？** FlyWithLua 本身没有暴露任何 METAR
  读取函数（`XSB_METAR` 那个变量只在连 VATSIM 的 XSquawkBox 在线时才有值）。
  `XPLMGetMETARForAirport` 是官方 SDK 里 XPLM400（也就是 X-Plane 12）提供的接口，
  而 FlyWithLua 用的 LuaJIT 自带 FFI，直接调用是最短路径。
- **为什么解析 apt.dat 而不去问导航数据库？** X-Plane 的导航数据库接口能给出
  机场位置和代码，但给不出**跑道铺装和长度**，而这两项正是你要的筛选条件。
  apt.dat 是唯一同时包含位置、名称、机场类型和跑道属性的数据源。
- **为什么要在扫描时排除直升机场/水上基地？** apt.dat 用行代码区分陆地机场(1)、
  水上基地(16)、直升机场(17)，这比拿名称做关键词匹配可靠得多。
- **为什么先查 10 个候选再挑 3 个？** 最近的三个机场里经常有一个不发报文。
  与其把「无报文」占掉一格，不如在最近的十个里优先挑有报文的；只有当确实不足
  三个时，才用最近的机场补齐并如实标注。
- **为什么窗口里带「天气等级」而不是只贴报文？** 报文是给要解读的人看的，
  而等级是给一眼扫过去的人看的；两者并存，信息量更大但窗口并不更乱。
- **为什么时区偏移要用两个 dataref 相减？** `sim/time/local_time_sec` 与
  `sim/time/zulu_time_sec` 都是「当天零点起的秒数」，差值（做 24 小时归一化后）
  就是模拟器正在使用的本地偏移，夏令时也一并包含了，比自己去查时区数据库更准。

## 验证情况

作者机器上没有 X-Plane，因此脚本是在一个模拟 FlyWithLua 的环境里跑的（Lua 虚拟机
+ 假的 `draw_string` / `measure_string` / `dataref` / `create_command` / OpenGL
调用 / 假的 FFI），配合一份合成的 apt.dat——里面同时放了铺装、草地、碎石、水面、
直升机场、水上基地和私人简易跑道。约六十项断言覆盖了：

- 筛选与按距离排序，包括 XP12 新增的 24、53 两个铺装色号；
- METAR 解算：VFR/MVFR/IFR/LIFR、`10SM`/`P6SM`/`1/2SM`/`1 1/2SM`/`M1/4SM`、
  米制能见度（`8000`、`9999`）、`BKN`/`OVC`/`VV` 云底、`CAVOK`、`SPECI`、
  无报文、以及报文时间领先于模拟时钟的情况；
- 时区换算，包括 UTC+8 跨零点、以及半小时偏移（UTC+05:30）；
- 版面：把每一段文字按量测宽度对照窗口矩形检查，确保任何内容都不会溢出；
  以及一条很长的 RMK 报文必须正确折行；
- 后台加载：两万行的文件分多帧切片读取期间进度可见，读完后窗口完整；
- 失败路径：没有 FFI、缺少 apt.dat、可用机场不足三个。

它无法证明的是你机器上的真实情况——你那版 X-Plane 的 apt.dat 具体排布，以及你的
天气模式实际下载回来的报文内容。如果发现哪里不对，把 `debug` 设为 `true`，
然后看 `Resources/plugins/FlyWithLua/Log.txt`，脚本会把读到的东西写进去。

## 文件

```
XP_Nearby_Weather/
  nearby_weather.lua                 脚本本体
  nearby_weather.README.md           英文说明
  nearby_weather.README.zh-CN.md     本文件
```
