# X-Plane 12 实用 Lua 脚本集

Practical X-Plane 12 Lua scripts (FlyWithLua). 收集我自己在飞的、日常真正用得上的 XP12 Lua 脚本。

## 脚本列表

| 脚本 | 作用 | 依赖 |
|---|---|---|
| [Instant Quick-Looks](./XP_Instant_Quicklook/) | 把「跳转到已保存的 3D 座舱视角」从约 0.5 秒的缓动变成**瞬时**切换 | X-Plane 12 + FlyWithLua |

每个脚本都有自己的文件夹，里面包含脚本本体、说明文档（英文原版 + 中文版）。

## 安装

1. 确保已安装 [FlyWithLua](https://forums.x-plane.org/index.php?/files/file/38445-flywithlua-ng-next-generation-edition/)（X-Friese 版，2023 及以后）。
2. 把需要的 `.lua` 文件复制到：

   ```
   <X-Plane 12>/Resources/plugins/FlyWithLua/Scripts/
   ```

3. 启动 X-Plane 或在游戏内执行 Plugins → FlyWithLua → **Reload all Lua scripts**。
4. 具体用法见各脚本文件夹内的说明文档。

## 目录结构

```
XP12Lua/
  README.md
  LICENSE
  XP_Instant_Quicklook/
    instant_quicklook.lua
    instant_quicklook.README.md          英文说明
    instant_quicklook.README.zh-CN.md    中文说明
```

## 许可

MIT，见 [LICENSE](./LICENSE)。

---

## English

A small collection of practical X-Plane 12 Lua scripts for FlyWithLua.

| Script | What it does |
|---|---|
| [Instant Quick-Looks](./XP_Instant_Quicklook/) | Makes X-Plane's "go to saved 3-D cockpit location" snap **instantly** instead of gliding over ~0.5 s |

**Install:** copy the `.lua` files into `<X-Plane 12>/Resources/plugins/FlyWithLua/Scripts/`, then
Plugins → FlyWithLua → *Reload all Lua scripts*. See each script's own README for usage.

**License:** MIT.
