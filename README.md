# mkxp-z 兼容加载器 · RGSS2 (RPG Maker VX)

> **作者 / Author: DeepSeek V4.1 Flash**

一个**不修改游戏文件**的运行时兼容层，让老国产 RGSS2 游戏能在 [mkxp-z](https://github.com/mkxp-z/mkxp-z) 上正常运行，
从而吃到 **GPU 渲染**（原版 RGSS2 播放器是 GDI 纯软件渲染，全部压在单核 CPU 上）。

本仓库最初为《Changed-special》(AppID 1069790) 开发并实测通过，其中的修复对**同类老 VX 游戏**同样适用。

## 它解决什么问题

mkxp-z 是 RGSS 的重写实现（RPG Maker XP / VX / VX Ace），性能和兼容性都远好于原版播放器，
但一批用老脚本的国产 VX 游戏直接丢进去跑会遇到四个坑：

| # | 问题 | 表现 | 本加载器的做法 |
|---|------|------|----------------|
| 1 | mkxp-z 自身的 `Data/Scripts.rvdata` 加载流程对这类游戏不生效 | 窗口全黑、脚本从不执行、几秒后自己退出 | 手动读取 → 解压 → 按顺序 `eval`，等效 RGSS 的脚本加载流程 |
| 2 | 老脚本用了 Ruby 1.8 才认的写法（如行尾带冒号的 `if cond:`） | Ruby 3.x 下语法错误，游戏起不来 | `eval` 之前做一次文本兼容转换（只动行尾多余冒号） |
| 3 | 「截图存档」类脚本用 `Win32API + RtlMoveMemory` 按 Ruby 1.8 的对象布局（`object_id * 2 + 16`）直接读写 Bitmap 内存 | Ruby 3.x 里 `object_id` 已不是地址 → 往野地址写数据 → **读档必段错误** | `eval` 后检测并覆盖 `Bitmap#_dump` / `Bitmap._load`，改走 `raw_data`（没有该扩展时回退 `get_pixel`/`set_pixel`），**存档数据结构不变** |
| 4 | mkxp-z 里 `Input::A` 默认没绑到 Shift | 原版里 A 键=Shift（疾跑、对话瞬间显示、菜单快捷键）全部失灵 | 在引擎层把物理 Shift 映射成 `Input::A`（`press?` / `trigger?` / `repeat?`） |

另外还接住了 mkxp-z 的引擎级 `F12`（它会直接抛 `Reset` 把游戏关掉），改成 **F12 = 回到标题画面**。

## 效果（《Changed-special》实测）

| | 原版播放器（GDI 软渲染） | 本加载器 + mkxp-z |
|---|---|---|
| 帧率 | 60 FPS，重场景掉到 8~21 FPS | 稳定 60 FPS |
| CPU | 单核 60~72% | 单核 **约 10%** |
| 渲染 | 全部 CPU 软件 blit（缩放另外再吃一份） | ANGLE → **Direct3D 11**（GPU） |

## 前置要求

1. **正版游戏**（本仓库不含、也不会包含任何游戏内容）
2. **mkxp-z**：官方 Windows 构建没有直接下载链接，需要从作者的
   [Discord](https://discord.gg/A8xHE8P) 或 GitHub 的
   [Automatic Builds](https://github.com/mkxp-z/mkxp-z/actions/workflows/autobuild.yml)（登录后下载 artifact）获取。
   本项目在 `mkxp-z v2.4.2`（enumag 的 fork 构建）上实测通过。

## 安装

1. 把 `mkxp_loader.rb` 和 `mkxp.json` 复制到**游戏目录**（与 `Game.exe` 同级）；
2. 把 mkxp-z 的可执行文件（及其附带的 dll）也放进该目录；
3. 双击 mkxp-z 运行。

或者直接用附带的脚本：

```powershell
# 在游戏目录里执行（会把两个文件复制到位；已存在的 mkxp.json 会先备份）
powershell -ExecutionPolicy Bypass -File .\install.ps1 -GameDir "D:\Games\YourVXGame"
```

运行日志写在游戏目录的 `dsh_log.txt`（每秒/每场景一行，用于确认它在正常工作）。

## 按键

| 键 | 作用 |
|---|---|
| `Shift` | 原版的 A 键（疾跑、对话瞬间显示、菜单快捷键） |
| `F12` | 回到标题画面（原版行为；按住不放会连续重载几次，按一下即可） |
| `F1` | mkxp-z 自带的设置菜单（缩放/滤镜/按键绑定等） |
| `F2` | mkxp-z 自带的帧率显示开关 |
| `Alt+Enter` | 全屏（GPU 缩放，几乎不吃 CPU） |

## 帧率说明（重要）

RGSS 里 **`Graphics.update` 同时是渲染和逻辑 tick**，所以"解锁帧率"= 整体加速（等于变速齿轮），
不存在"只提帧率、逻辑不变"的引擎内做法。本加载器因此把帧率锁定在 **60（原速）**。

- 想要整体加速：改 `mkxp.json` 里的 `"fixedFramerate"`（例如 `90` ≈ 1.5 倍速，`120` ≈ 2 倍速）。
- 想要"只提帧率、速度不变"：只能用**外部插帧**，例如 Lossless Scaling 的 Frame Generation（LSFG）。

## 多显卡机器（黑屏排查）

如果机器上有多张显卡（尤其是计算卡 / 虚拟显示适配器），ANGLE 可能挑到没有显示输出的那张，
表现为**窗口全黑**。给 mkxp-z 单独指定显卡即可：

- 设置 → 系统 → 屏幕 → 显卡 → 添加桌面应用 → 选择 mkxp-z.exe → 选带显示输出的那张（或"省电"= 核显/显示卡）；
- 等价注册表（`GpuPreference=1` 表示非"高性能"那张）：
  `HKCU\Software\Microsoft\DirectX\UserGpuPreferences` 下新建字符串值，名称为 mkxp-z.exe 的完整路径，值为 `GpuPreference=1;`

## 已知问题

- **旧存档的缩略图**外观可能不对：老存档里的缩略图像素是原版播放器的内存布局（自下而上/通道顺序不同），
  用 mkxp 解出来会翻或偏色。在 mkxp 里**重新存一次档**即可恢复正常（不影响存档内容与游戏本身）。
- `F12` 触发的是"重新加载脚本"，会有约 0.2 秒的卡顿与少量资源残留。

## 许可与声明

- **作者：DeepSeek V4.1 Flash**
- 本仓库**只包含加载器代码**，不含任何游戏内容、素材或游戏脚本；请自备正版游戏。
- 本项目采用 MIT 许可（见 `LICENSE`）。
- mkxp-z 采用 GPL 许可，本项目未修改 mkxp-z 源码，仅作为其 `customScript` 运行，二者各自遵循自己的许可。
- 感谢 mkxp / mkxp-z 的作者与维护者，以及公开脚本「vx新截图存档」的作者（本加载器只做运行时兼容，不包含其代码）。
