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
- *解析引擎*：纯 Dart 手写，**解析层分三层**——① 规格表（声明式数据，每格式一张：MP4 box 表 / Matroska element 表 / RIFF chunk 表 / FLAC block 表）；② 通用容器引擎（代码只写一次：读头 → 查表 → 走字段 → 递归 → 产出统一节点）；③ 叶子提取器（少量手写，从已解析的树里取语义字段，不重复解析字节）。**MVP 不引入任何原生依赖**（FFmpeg / MediaInfoLib / C++ 均排除在本 effort 之外）。**理由（已被[现成方案的结构深度](issues/03-mediainfo-ffprobe-depth.md)改写）**：我们要的是**原始结构 + 结构化数据**，而现成方案给的是**解读 + 文本 blob**（MediaInfo 的 MediaTrace 是它自己的语义解读树、块名被替换、未知块被折叠、只给预渲染 XML、无 hex；FFmpeg 根本没有块树）。且引入任一原生库会立刻加上"必须有 macOS 构建机"的硬约束——`flutter build macos` 在非 macOS 主机上直接报错退出。**Dart 生态无可用的通用声明式二进制解析库**（见[声明式规格表](issues/02-declarative-parsers.md)），需自建 DSL + 引擎。
- *注册表扩展点*：形状不变、粒度变细——注册表登记的是**规格表 + 可选的叶子提取器**，不是解析器对象。第三方加一个新容器 = 写一张表。
- *语义字段深度*：轨道级（分辨率、帧率、采样率、位深、声道数、推算的平均码率）。**不做**编码参数级（profile / level / 色度 / 真实码率）。
- *文件打开*：拖放 + 文件选择器 + 多标签页。命令行参数不进 MVP。
- *导出*：右键复制字段值 + 导出 JSON。CSV 不做。
- *hex 视图*：选中块可查看该块的原始 hex + ASCII 侧栏。
- *界面语言*：界面中文；**代码内部、字段名、块类型名一律英文**，以便与格式规范逐字对照。
- *承诺级别*：自用优先，开源但不承诺格式覆盖稳定性、不承诺 API、不承诺支持。
- *平台推进顺序*：**Windows 优先**——先跑通 Windows，macOS 随后由用户自己在 Mac 上验证。macOS 仍在 MVP 范围内，只是不并行推进。
- *验收标准*（两平台统一）：构建成功 + 手动点过主流程——启动 → 打开文件 → 同时看到语义字段与结构树 → 展开一个块看到原始 hex。

**仓库约定**：票存于 `.scratch/media-info-mvp/issues/`，本文件即地图。追踪器总约定见 `docs/agents/issue-tracker.md`。

**实现阶段**：12 张决策票已全部解完，规格已完整。实现工作在 `integration/media-info-mvp` 分支上进行，实现票为 13–25 号（`Status: ready-for-agent` → `Status: resolved`）。**实现层的强制契约是 `docs/design/core-api.md`**——并行开发的 agent 靠它对齐，任何偏离都会导致分支无法合并。

## Decisions so far

<!-- 一行一条：已关闭票的标题 + 一句话结论。详情在票内。 -->

- [macOS 验证环境确认](issues/05-macos-verification-env.md): Windows 优先、macOS 随后由用户自验；验收标准 = 构建成功 + 手动点过主流程；不需要自托管 runner。
- [MediaInfo / ffprobe 到底能给出多深的结构](issues/03-mediainfo-ffprobe-depth.md): FFmpeg 彻底出局（无 box 树、AVIO_FLAG_TRACE 已不存在）；MediaInfo 有真块树（MediaTrace，带 offset+size）但那是它的**解读树**、只能拿到预渲染 XML、无 hex——**前提成立，理由改写**。
- [容器格式能否用声明式规格表描述](issues/02-declarative-parsers.md): 声明式可行，但只覆盖**结构树**层；解析层定为**三层**——规格表 + 通用容器引擎 + 叶子提取器。Dart 生态无可用声明式二进制解析库（binstruct 能力不足、Kaitai 无 Dart 运行时、mediaindex_dart SDK 约束过旧），需自建 DSL + 引擎（约 300–500 行）。
- [测试素材获取与归档](issues/04-test-fixtures.md): 素材全部由本机 ffmpeg 本地确定性生成，不下载外部内容；`test/fixtures/` 24 个文件约 550 KB，随仓库提交，不需 LFS。
- [统一节点模型与双视图的数据来源](issues/01-unified-node-model.md): **一棵节点树，两个视图都是投影**。节点持有 `type/offset/size/dataOffset/dataSize/isOpaque/children/fields`，字段持有 `key/label/value/unit/origin/scope/trackIndex/source`。契约见 `docs/design/core-api.md`。
- [字节访问与大文件策略](issues/06-byte-access-large-files.md): `RandomAccessFile` 随机访问、不整体读入内存；偏移用 64 位 `int`；惰性展开（初始只建第一层）；截断与长度撒谎走同一条路径，**已解析的部分照常返回**。
- [界面布局与多文件交互](issues/07-ui-layout-prototype.md): **左右分栏**——左语义字段（文件级/轨道级/标签三区段），右结构树，hex 面板在右栏下方展开；解析失败仍展示已读到的部分结构；树用虚拟滚动。
- [统一语义字段词表](issues/08-field-vocabulary.md): 统一词表只管**键名**（英文技术名=代码标识符）；各格式原生字段名不丢，额外带 `source`。文件级 5 个 + 轨道级 10 个通用键，格式特有字段不进统一词表。
- [标签 / 元数据与语义字段的边界](issues/09-tag-vs-field-boundary.md): 标签**单独成区**（左栏第三区段），与技术属性、容器技术属性三者划清；`GLOSSARY.md` 增补「标签」词条。
- [CI 双平台构建](issues/10-ci-dual-platform.md): GitHub Actions 矩阵 `windows-latest` + `macos-latest`，Flutter 钉死 3.41.6；产物 Windows zip / macOS tar.gz；CI 上不设中国镜像环境变量；macOS 只保证构建成功。
- [分发形态与签名](issues/11-distribution-form.md): **双端都发 zip**——Windows 免安装 zip，macOS `.app` 打 tar.gz；不签名/公证、不做安装包、不做自动更新。
- [视觉语言：暗色仪器面板](docs/design/visual-language.md)（实现期决定，不是一张决策票）：底色偏蓝石墨灰、数据一律等宽、区段眉标是丝印小字、1px 发丝线；配色只有四个且**颜色是编码**——琥珀=媒体载荷、青=结构与坐标、紫=推算值、玫红=出问题。签名元素是**胶片条**：顶层块按真实位置与比例排开的一条文件地图，与结构树选中双向联动。
- [以 MediaTrace 作为结构树的离线校验基准](issues/12-mediatrace-offline-oracle.md): **不采纳**（CI 成本高、映射层是主要工作量、只单向可用）。替代：每个格式维护**块覆盖率清单**（人写规范，不继承别人的盲区）。

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
