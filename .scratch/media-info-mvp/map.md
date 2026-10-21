# media_info MVP 规格 — Wayfinder Map

## Destination

一份**可开工的 MVP 规格**：Windows + macOS 桌面应用，打开音视频文件后同时给出**语义字段**（时长、编码、采样率…）与**容器结构树**（可展开的块、偏移量、长度、原始 hex）。

规格定死四件事——范围与格式覆盖、解析架构、界面结构、分发形态——使实现者无需再问任何关键问题即可开工。

产物：[media_info MVP — 产品规格](spec.md)（已起草，`Status: ready-for-agent`；仍有 10 张决策票开放，其结论需回写进规格）。

## Notes

**领域**：音视频容器格式检视工具。术语以仓库根目录 `GLOSSARY.md` 为准（容器 / 块 / 轨道 / 语义字段 / 结构树）。

**每个会话必读的 skill**：`grilling` + `domain-modeling`（默认组合）；界面类票加 `prototype`，事实类票加 `research`。

**票的约定**（本追踪器特有）：票的 `Status:` 行只有两个取值——`claimed`（已认领）与 `resolved`（已完成）。**没有 `Status:` 行 = 开放且未认领**。`Blocked by: NN` 列出阻塞它的票号，全部为 `resolved` 时该票解锁。`Type:` 行标注 `research` / `prototype` / `grilling` / `task`。

**研究产物的存放**：调研结论写进 `docs/research/<票号>-<slug>.md`，随仓库提交，票内 `## Answer` 给出结论摘要 + 指向该文件的路径。（此处偏离了 wayfinder 默认的"throwaway branch + 永不合并"约定：本地 markdown 追踪器下，仓库内文件才是可被后续会话直接读到的产物，指向未合并分支反而需要额外 fetch。）

**本 effort 的既定前提**（charting 阶段由用户逐条确认，后续票默认继承，不再重开）：

- *产品定位*：比 MediaInfo 更深地展示容器原始结构——带偏移量、长度、可下钻到 hex——而不是重造一张字段表。
- *视图形态*：语义字段 + 结构树，两个视图。
- *MVP 格式集*：WAV / AIFF / FLAC / MP3（音频方向）+ MP4·MOV / MKV·WebM（视频方向）。**两个方向都必须覆盖**，不允许只做一个方向。
- *解析引擎*：纯 Dart 手写，每格式一个解析器，共享统一节点模型，以「解析器注册表」为扩展点。**MVP 不引入任何原生依赖**（FFmpeg / MediaInfoLib / C++ 均排除在本 effort 之外）。**理由（已被[现成方案的结构深度](issues/03-mediainfo-ffprobe-depth.md)改写）**：我们要的是**原始结构 + 结构化数据**，而现成方案给的是**解读 + 文本 blob**（MediaInfo 的 MediaTrace 是它自己的语义解读树、块名被替换、未知块被折叠、只给预渲染 XML、无 hex；FFmpeg 根本没有块树）。且引入任一原生库会立刻加上"必须有 macOS 构建机"的硬约束——`flutter build macos` 在非 macOS 主机上直接报错退出。
- *语义字段深度*：轨道级（分辨率、帧率、采样率、位深、声道数、推算的平均码率）。**不做**编码参数级（profile / level / 色度 / 真实码率）。
- *文件打开*：拖放 + 文件选择器 + 多标签页。命令行参数不进 MVP。
- *导出*：右键复制字段值 + 导出 JSON。CSV 不做。
- *hex 视图*：选中块可查看该块的原始 hex + ASCII 侧栏。
- *界面语言*：界面中文；**代码内部、字段名、块类型名一律英文**，以便与格式规范逐字对照。
- *承诺级别*：自用优先，开源但不承诺格式覆盖稳定性、不承诺 API、不承诺支持。
- *平台推进顺序*：**Windows 优先**——先跑通 Windows，macOS 随后由用户自己在 Mac 上验证。macOS 仍在 MVP 范围内，只是不并行推进。
- *验收标准*（两平台统一）：构建成功 + 手动点过主流程——启动 → 打开文件 → 同时看到语义字段与结构树 → 展开一个块看到原始 hex。

**仓库约定**：票存于 `.scratch/media-info-mvp/issues/`，本文件即地图。追踪器总约定见 `docs/agents/issue-tracker.md`。

## Decisions so far

<!-- 一行一条：已关闭票的标题 + 一句话结论。详情在票内。 -->

- [macOS 验证环境确认](issues/05-macos-verification-env.md): Windows 优先、macOS 随后由用户自验；验收标准 = 构建成功 + 手动点过主流程；不需要自托管 runner。
- [MediaInfo / ffprobe 到底能给出多深的结构](issues/03-mediainfo-ffprobe-depth.md): FFmpeg 彻底出局（无 box 树、AVIO_FLAG_TRACE 已不存在）；MediaInfo 有真块树（MediaTrace，带 offset+size）但那是它的**解读树**、只能拿到预渲染 XML、无 hex——**前提成立，理由改写**。

## Not yet specified

- **推算字段的标注方式** — 哪些字段是文件里直接读到的、哪些是推算的（如平均码率），界面要不要区分来源。
- **未知块与损坏文件的降级** — 遇到不认识的块、截断的文件、CRC 校验失败时，结构树和错误提示各怎么表达。
- **EBML 的未知长度与 VINT 边界** — FLAC / Matroska 特有的递归深度、哨兵值、无限长度元素的处理。
- **多标签页下的状态模型** — 每个标签独立解析、解析中的表示、是否并行。
- **性能预算** — 目标文件大小上限、"打开到出结果"的可接受延迟。
- **hex 视图的进阶能力** — 是否支持跳转、是否跟随选中块高亮、是否支持按偏移定位。
- **中文字段显示名对照表** — 英文技术名 ↔ 中文显示名的映射。
- **结构树的规模上限** — moov 可能上万节点，虚拟滚动与惰性展开的具体做法。

## Out of scope

- **播放 / 转码 / 预览** — 本工具只读元数据与结构，不解码媒体。
- **编辑 / 改写文件** — 只读工具，不写回容器。
- **原生解析后端（FFmpeg / MediaInfoLib）** — MVP 纯 Dart，**已定**（[现成方案的结构深度](issues/03-mediainfo-ffprobe-depth.md)：前提成立，理由改写）。若将来要引，作为**新 effort** 重新评估，而非在本 effort 内改道。
- **命令行 / 文件关联 / 系统右键菜单集成** — MVP 只有 GUI。
- **macOS 签名与公证（notarization）** — 需要付费 Apple Developer 账号，自成一个后续 effort。
- **移动端 / Web 端** — 本 effort 只做 Windows + macOS 桌面。
