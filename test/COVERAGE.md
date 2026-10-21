# 测试覆盖与需求追溯表（COVERAGE.md）

> 本文件把 `.scratch/media-info-mvp/spec.md` 里的 **56 条 User Story**
> 逐条映射到具体测试。
>
> - **测试文件**一列给出文件路径；**测试名**一列给出 `group` / `test` 的名字。
> - 「状态」一列：
>   - `已覆盖` —— 有断言直接对应这条故事的可观察行为；
>   - `部分覆盖` —— 能测的部分测了，剩下的部分**说明为什么测不了 / 没测**；
>   - `未覆盖` —— 没有对应测试，并说明原因；
>   - `与实现矛盾` —— 测试存在但**当前是失败的**，说明实现与规格相悖（见文末「已知缺陷」）。
>
> 本次新增的测试文件（15 个，404 个测试）：

| 文件 | 测试数 | 覆盖的主题 |
|---|---|---|
| `test/core/node_model_test.dart` | 14 | 节点模型不变量 |
| `test/core/engine_contract_test.dart` | 39 | 通用容器引擎契约 |
| `test/core/registry_contract_test.dart` | 17 | 格式注册表与嗅探顺序 |
| `test/formats/format_structure_test.dart` | 47 | 各格式的结构树 |
| `test/formats/format_semantic_fields_test.dart` | 44 | 各格式的语义字段 |
| `test/app/semantic_view_render_test.dart` | 38 | 语义字段视图渲染 |
| `test/app/export_json_shape_test.dart` | 24 | 导出 JSON 的形状 |
| `test/app/parse_service_fields_test.dart` | 25 | 解析服务的字段补齐与错误 |
| `test/app/extension_mismatch_test.dart` | 20 | 扩展名不一致提示 |
| `test/app/file_strip_layout_test.dart` | 19 | 胶片条布局与配色 |
| `test/app/app_shell_workflow_test.dart` | 20 | 应用外壳交互 |
| `test/app/copy_value_format_test.dart` | 30 | 复制到剪贴板的文本格式 |
| `test/ui/structure_tree_columns_test.dart` | 26 | 结构树的行、列与展开 |
| `test/ui/hex_panel_render_test.dart` | 26 | hex 面板渲染 |
| `test/platform/packaging_test.dart` | 18 | 平台、CI、不联网、样本齐备 |

辅助文件：`test/support/document_builder.dart`（造 `ParsedDocument` / `ContainerNode` / `SemanticField` / `Tag` 的 helper，无测试）。

---

## 打开与浏览文件

| # | 故事（短标题） | 测试文件 | 测试名 | 状态 |
|---|---|---|---|---|
| 1 | 拖进窗口就打开 | `test/app/app_shell_workflow_test.dart` | 拖放打开文件 › 把文件拖进窗口就打开它 | 已覆盖 |
| 1 | 拖进窗口就打开（空态） | `test/app/app_shell_workflow_test.dart` | 拖放打开文件 › **空态下也能把文件拖进来打开** | **与实现矛盾**（见缺陷 #1） |
| 2 | 通过文件选择器打开文件 | `test/app/app_shell_workflow_test.dart` | 空态 › 点「打开文件」在没有平台实现时不崩溃 | 部分覆盖——文件选择器是系统窗口，测不了；只断言了「没有平台实现时不崩溃、不弹异常」 |
| 3 | 同时打开多个文件各占一个标签页 | `test/app/app_shell_workflow_test.dart` | 标签页 › 同时打开多个文件各占一个标签页；拖放打开文件 › 拖进来一个列表会逐个打开 | 已覆盖 |
| 4 | 在标签页之间快速切换 | `test/app/app_shell_workflow_test.dart` | 标签页 › 在标签页之间切换，当前内容随之改变；标签页 › Ctrl+Tab 切到下一个标签页 | 已覆盖 |
| 5 | 关闭一个标签页后其余不受影响 | `test/app/app_shell_workflow_test.dart` | 标签页 › **关闭一个标签页，其余标签不受影响（不重新解析）** | **与实现矛盾**（见缺陷 #2） |
| 6 | 界面告诉我当前打开的是哪个文件 | `test/app/app_shell_workflow_test.dart` | 标签页 › 打开一个文件就多一个标签，标签上是文件名；当前打开的是哪个文件 › 工具条右侧显示当前文件的文件名 | 已覆盖 |
| 7 | 打开大文件时界面不要卡死 | `test/app/app_shell_workflow_test.dart` | 解析中的状态 › 解析还没完成时显示「解析中…」 | 已覆盖（解析在 isolate 里跑，界面先给「解析中…」） |
| 7 | 打开大文件时界面不要卡死 | `test/app/parse_service_fields_test.dart` | 后台 isolate 解析 › parseFileInIsolate 在新 isolate 里也能注册格式并完成解析 | 已覆盖 |

## 语义字段

| # | 故事（短标题） | 测试文件 | 测试名 | 状态 |
|---|---|---|---|---|
| 8 | 看到这个文件的时长 | `test/formats/format_semantic_fields_test.dart` | WAV › 时长是 0.25 秒，来源是文件里写的数据；AIFF › 时长由采样帧数与采样率算出；FLAC › 时长是推算值；MP4 › 时长 1.0 秒，时间刻度 1000 tick；MKV › 时长与时间戳刻度 | 已覆盖 |
| 9 | 文件大小和推算的平均码率 | `test/formats/format_semantic_fields_test.dart` | WAV › 文件大小是文件的真实字节数，单位是 byte；WAV › 平均码率是推算值；MP4 › 平均码率是推算值 | 已覆盖 |
| 10 | 看到它有几条轨道 | `test/app/semantic_view_render_test.dart` | 轨道分组 › 每条轨道一个标题，序号从 0 起 | 已覆盖（轨道数由「轨道 N」标题的个数体现；词表里**没有** `track_count` 字段，见「已知缺口 #1」） |
| 11 | 每条轨道的 codec 标识 | `test/formats/format_semantic_fields_test.dart` | WAV › 轨道级字段：采样率 / 位深 / 声道数 / codec；MP3 › 容器格式是 MP3，codec 是 MPEG-1 Layer 3；MKV › 音频轨道：A_OPUS、48kHz、1 声道、16bit | 已覆盖 |
| 12 | 视频轨道的分辨率和帧率 | `test/formats/format_semantic_fields_test.dart` | MP4 › 视频轨道：类型 / codec / 分辨率 / 帧率；MOV › 视频轨道的 codec 是 mp4v，时长 1.0 秒 | 部分覆盖——**Matroska 不产出 `frame_rate`**（见「已知缺口 #2」） |
| 13 | 音频轨道的采样率、位深和声道数 | `test/formats/format_semantic_fields_test.dart` | WAV › 轨道级字段…；FLAC › 轨道级字段…；MP4 › 音频轨道：codec / 采样率 / 位深 / 声道数；WebM › 视频 V_VP8、音频 A_VORBIS（44.1kHz / 32bit） | 已覆盖 |
| 14 | 音频和视频的字段分组显示 | `test/app/semantic_view_render_test.dart` | 轨道分组 › 每条轨道一个标题，序号从 0 起；轨道分组 › 轨道标题在它的字段之前 | 已覆盖 |
| 15 | 知道字段是直接写的还是推算的 | `test/app/semantic_view_render_test.dart` | 推算值的标记 › 推算值带「（推算）」标记；推算值的标记 › 文件里直接写的值不带推算标记；推算值的标记 › 推算标记用紫色（推算色） | 已覆盖 |
| 16 | 右键复制一个字段的值 | `test/app/copy_value_format_test.dart` | 全部 30 个测试（值的文本格式：不含单位、时长 `HH:MM:SS.mmm`、二进制转十六进制） | 已覆盖（**文本格式**部分）；右键菜单的交互由并行工作流的 `test/app/semantic_view_copy_test.dart` 覆盖 |

## 结构树

| # | 故事（短标题） | 测试文件 | 测试名 | 状态 |
|---|---|---|---|---|
| 17 | 看到文件内部的结构树 | `test/formats/format_structure_test.dart` | WAV：RIFF chunk 布局 › 根节点是 WAV，顶层是 RIFF 块…；MP4：完整 box 树 › 顶层块按文件顺序排列…；MKV / WebM：EBML 元素树 › Segment 下有 SeekHead、Info、Tracks、Cluster、Cues | 已覆盖 |
| 18 | 每个块显示偏移量和长度 | `test/ui/structure_tree_columns_test.dart` | 行顺序与坐标列 › 每行给出精确的偏移量与长度；行顺序与坐标列 › 子块在展开前不出现 | 已覆盖 |
| 19 | 逐层展开嵌套的块 | `test/ui/structure_tree_columns_test.dart` | 行顺序与坐标列 › 子块在展开前不出现；折叠 › 折叠后子块一起收起来 | 已覆盖 |
| 20 | 块的原始类型标识（英文规范名） | `test/ui/structure_tree_columns_test.dart` | 显示名 › 普通块类型名原样显示，不翻译；显示名 › Matroska 的十六进制元素 ID 显示成元素名 | 已覆盖 |
| 21 | 折叠某个块时它的子块一起收起来 | `test/ui/structure_tree_columns_test.dart` | 折叠 › 折叠后子块一起收起来 | 已覆盖 |
| 22 | 不认识的块仍然显示出来 | `test/formats/format_structure_test.dart` | WAV：RIFF chunk 布局 › 不认识的子块（ISFT）仍然出现在树里，不会被丢掉 | 已覆盖 |
| 22 | 不认识的块仍然显示出来 | `test/core/engine_contract_test.dart` | 「未知即跳过」兜底 › 表里查不到的 type 产出不透明叶子，不递归也不报错；未知块不会挡住后面的已知块 | 已覆盖 |
| 23 | 几千个子条目也不会把界面拖垮 | `test/ui/structure_tree_columns_test.dart` | 虚拟滚动 › 几千个子条目也只构建可见的行 | 已覆盖 |
| 24 | 展开一个块时才去读它的内容 | `test/ui/structure_tree_columns_test.dart` | 展开按钮 › 展开时按更大的深度重新解析，并接上新的子块；展开按钮 › 不透明节点不触发惰性展开；展开按钮 › 重新解析后确实没有子块，就不再显示展开按钮 | 已覆盖 |

## 原始字节

| # | 故事（短标题） | 测试文件 | 测试名 | 状态 |
|---|---|---|---|---|
| 25 | 选中一个块时看到它的原始 hex | `test/ui/hex_panel_render_test.dart` | 面板标题 › 标题给出块的类型、偏移与大小；大块：截断显示，不整块读入 › 大块不会被整块渲染出来（只渲染前 N 字节的行） | 已覆盖 |
| 26 | 在 hex 旁边看到 ASCII 侧栏 | `test/ui/hex_panel_render_test.dart` | ASCII 侧栏 › 不可打印的字节替换成点；0x20（空格）是可打印的；0x7E（~）是可打印的；0x1F 与 0x7F 不可打印 | 已覆盖 |
| 27 | 能看到当前高亮的是哪几个字节 | — | — | **未覆盖——功能不存在**：`HexView` 没有「高亮某几个字节」的能力（见「已知缺口 #3」） |
| 28 | hex 视图能独立滚动 | `test/ui/hex_panel_render_test.dart` | 独立滚动 › hex 面板有自己的滚动视图；独立滚动 › 横向滚动条存在（长行可以左右看） | 已覆盖 |

## 格式覆盖

| # | 故事（短标题） | 测试文件 | 测试名 | 状态 |
|---|---|---|---|---|
| 29 | 读 WAV 的 RIFF chunk 布局 | `test/formats/format_structure_test.dart` | WAV：RIFF chunk 布局 › RIFF 的子块按文件顺序排列：fmt 、LIST、data；WAV：RIFF chunk 布局 › fmt 与 data 各自的大小与偏移是精确的 | 已覆盖 |
| 30 | 从 WAV 读到 16bit、采样率、声道数 | `test/formats/format_structure_test.dart` | WAV：RIFF chunk 布局 › fmt 块给出 16bit / 采样率 / 声道数；WAV：RIFF chunk 布局 › 8bit 单声道边界样本：位深 8、采样率 8000、声道 1 | 已覆盖 |
| 31 | 读 AIFF 的 FORM chunk 结构 | `test/formats/format_structure_test.dart` | AIFF：FORM chunk 结构 › 根节点是 AIFF，顶层是 FORM 块，form type 是 AIFF；AIFF：FORM chunk 结构 › AIFF 的长度字段是大端（与 WAV 的小端不同） | 已覆盖 |
| 32 | 读 FLAC 的 metadata block 和 STREAMINFO | `test/formats/format_structure_test.dart` | FLAC：metadata block 与 STREAMINFO › 根节点是 FLAC，子块是 STREAMINFO 与 VORBIS_COMMENT、PADDING；FLAC › STREAMINFO 给出位深 / 采样率 / 总采样数 / MD5 | 已覆盖 |
| 33 | 读 MP3 的帧头 | `test/formats/format_structure_test.dart` | MP3：帧头 › 帧头给出版本 / 层 / 码率 / 采样率；MP3：帧头 › VBR 边界样本：MPEG-2、每帧 576 个样本 | 已覆盖 |
| 34 | 读 MP4 的完整 box 树 | `test/formats/format_structure_test.dart` | MP4：完整 box 树 › moov 下是 mvhd、trak、trak、udta；trak 下是 tkhd、edts、mdia；顶层块的偏移量与长度是精确的 | 已覆盖 |
| 35 | 从 MP4 读到时长、分辨率、帧率、codec 标识 | `test/formats/format_semantic_fields_test.dart` | MP4 › 容器格式取 ftyp 的主品牌 isom；MP4 › 时长 1.0 秒，时间刻度 1000 tick；MP4 › 视频轨道：类型 / codec / 分辨率 / 帧率 | 已覆盖 |
| 36 | 读 MOV | `test/formats/format_structure_test.dart` | MOV：QuickTime 素材 › 顶层块是 ftyp、wide、mdat、moov；MOV › ftyp 的主品牌是 qt（QuickTime）；MOV › QuickTime 的 wide 占位盒保留在树里 | 已覆盖 |
| 37 | 读 MKV/WebM 的 EBML 元素树 | `test/formats/format_structure_test.dart` | MKV / WebM：EBML 元素树 › 顶层是 EBML 头与 Segment；Segment 下有 SeekHead、Info、Tracks、Cluster、Cues；Cluster 的 SimpleBlock 是不透明叶子 | 已覆盖 |
| 38 | 从 MKV 读到时长、轨道信息、视频尺寸 | `test/formats/format_semantic_fields_test.dart` | MKV › 时长与时间戳刻度；MKV › 视频轨道：V_VP9、320x240；MKV › 音频轨道：A_OPUS、48kHz、1 声道、16bit | 已覆盖 |
| 39 | 遇到还没支持的格式时收到清楚的提示而不是崩溃 | `test/app/app_shell_workflow_test.dart` | 异常状态 › 不是媒体文件：显示「无法识别的文件格式」 | 已覆盖 |
| 39 | 遇到还没支持的格式时收到清楚的提示而不是崩溃 | `test/app/parse_service_fields_test.dart` | 文件级字段的统一补齐 › 无法识别的文件：没有 container_format（不是猜一个）；错误与缺席 › 文件不存在：错误说明是「文件不存在」 | 已覆盖 |
| 40 | 一个文件的所有轨道的字段都列出来 | `test/formats/format_semantic_fields_test.dart` | MP4 › 两条轨道的字段都列出来，一条都不漏；MP4 › 没有音轨的边界样本只有一条轨道 | 已覆盖 |

## 导出与协作

| # | 故事（短标题） | 测试文件 | 测试名 | 状态 |
|---|---|---|---|---|
| 41 | 把整个分析结果导出成 JSON | `test/app/export_json_shape_test.dart` | 顶层键的集合与顺序 › 顶层键固定，且顺序固定；tool 与 schemaVersion 是固定值 | 已覆盖 |
| 42 | 导出的 JSON 同时包含语义字段和结构树 | `test/app/export_json_shape_test.dart` | 语义字段区 › fileFields 用英文技术名做键；结构树区 › 结构树是递归的；结构树区 › 结构树的节点键与顺序固定 | 已覆盖 |
| 43 | 导出的字段名用英文技术名 | `test/app/export_json_shape_test.dart` | 语义字段区 › fileFields 用英文技术名做键；语义字段区 › 重名的字段不会被丢掉：第二个起加 #2 后缀 | 已覆盖 |
| 41 | 导出的 JSON 逐字节可复现 | `test/app/export_json_shape_test.dart` | 两次导出逐字节相同 › 同一个文档导出两次，文本完全一致；两次独立解析出来的文档导出结果也完全一致；写文件写出来的内容与 buildDocumentJson 一致 | 已覆盖 |

## 平台与体验

| # | 故事（短标题） | 测试文件 | 测试名 | 状态 |
|---|---|---|---|---|
| 44 | Windows 上双击 exe 就用起来 | `test/platform/packaging_test.dart` | CI：双端矩阵与钉死的 Flutter 版本 › 矩阵里有 windows-latest 与 macos-latest；两端都出 zip（Windows 用 zip，macOS 用 tar.gz 包 .app）；CI 跑 analyze 与 test | 部分覆盖——CI 配置与打包脚本可断言；**真正的 exe 产物只能在 Windows 上手工验证**（规格的验收标准也是「手动点过主流程」） |
| 45 | macOS 上也有同样功能的版本 | `test/platform/packaging_test.dart` | 平台 › 只做桌面：windows 与 macos 的脚手架都在；CI › 矩阵里有 windows-latest 与 macos-latest | 部分覆盖——同上，**macOS 产物需要真实 Mac 才能验证** |
| 46 | 界面是中文的 | `test/app/app_shell_workflow_test.dart` | 界面语言 › 界面文案是中文，字段名与块名保持英文；空态 › 没有打开文件时给出中文提示与「打开文件」按钮 | 已覆盖 |
| 47 | 界面里的字段名和块名保持英文原词 | `test/ui/structure_tree_columns_test.dart` | 显示名 › 普通块类型名原样显示，不翻译 | 已覆盖 |
| 47 | 界面里的字段名和块名保持英文原词 | `test/app/semantic_view_render_test.dart` | 字段行：中文显示名 + 英文技术名 + 单位 › 英文技术名不翻译（保持规范原词） | 已覆盖 |
| 48 | 遇到损坏或截断的文件时看到明确的错误说明 | `test/formats/format_structure_test.dart` | 损坏文件：已读到的部分结构仍然返回（8 个测试，逐个格式断言中文错误说明的**原文**） | 已覆盖 |
| 49 | 解析失败时仍然能看到已经读到的部分结构 | `test/formats/format_structure_test.dart` | 损坏文件：已读到的部分结构仍然返回 › MP4 被截断：标记截断、给出中文说明、已读的 ftyp 仍在；WAV 被截断：data 块被裁到实际长度 | 已覆盖 |
| 50 | 工具本身不联网、不上传文件 | `test/platform/packaging_test.dart` | 工具本身不联网、不上传文件 › 依赖里没有任何网络客户端；源码里没有发起网络请求的调用；唯一的运行时依赖是 Flutter 自带的与 file_selector | 已覆盖 |
| 51 | 项目的解析器易于新增格式 | `test/core/registry_contract_test.dart` | 注册表的基本动作 › 注册表登记的是规格表本身（同一个实例）；全部已注册格式 › 每个已注册格式都带嗅探函数与叶子提取器 | 已覆盖 |
| 51 | 项目的解析器易于新增格式 | `test/platform/packaging_test.dart` | 新增格式的扩展点 › 注册表登记的是规格表 + 可选的提取器，不是解析器对象 | 已覆盖 |
| 52 | 每个格式的解析都有可复现的样本与断言 | `test/formats/format_structure_test.dart` | 块覆盖率清单 › 每个格式的必查块都能在结构树里找到 | 已覆盖 |
| 52 | 每个格式的解析都有可复现的样本与断言 | `test/platform/packaging_test.dart` | 每个格式都有可复现的样本与断言 › 每个格式至少有三类样本：正常 / 边界 / 损坏 | **与实现矛盾**（见缺陷 #3） |
| 53 | 按文件内容判定格式而不是信扩展名 | `test/app/parse_service_fields_test.dart` | 按内容判定格式（不看扩展名） › 把 WAV 的字节改名成 .mp4，仍然被认成 WAV；把 MP4 的字节改名成 .wav，仍然被认成 MP4 | 已覆盖 |
| 54 | 扩展名与实际格式不一致时看到明确提示 | `test/app/extension_mismatch_test.dart` | 全部 20 个测试（提示文案原文、哪些情况不提示） | 已覆盖 |
| 54 | 扩展名与实际格式不一致时看到明确提示 | `test/app/app_shell_workflow_test.dart` | 异常状态 › 扩展名与实际格式不符：给出明确的提示条 | 已覆盖 |
| 55 | 结构树里看到每个块占文件大小的比例 | `test/ui/structure_tree_columns_test.dart` | 占比列 › 百分比文本按大小分级取整；大小为 0 的块显示 0%；占比条的宽度与块的大小成正比 | 已覆盖 |
| 56 | 上方有一条按比例画出顶层块的文件地图 | `test/app/file_strip_layout_test.dart` | 全部 19 个测试（比例、累计位置、琥珀/青/暗灰配色、选中高亮、tooltip） | 已覆盖 |

---

## 解析核心的契约（不属于某一条 user story，但规格写死了）

| 契约 | 测试文件 | 测试名 |
|---|---|---|
| 节点不持有字节内容；偏移长度用 64 位 int；未知块保留为不透明节点 | `test/core/node_model_test.dart` | 全部 14 个测试 |
| 长度字段的六种语义；截断降级；九种字段类型；动态 type 分派；递归深度上限；`prefixBytes` | `test/core/engine_contract_test.dart` | 全部 39 个测试 |
| 注册表按内容嗅探、注册顺序即嗅探顺序、`parser` 覆盖 | `test/core/registry_contract_test.dart` | 全部 17 个测试 |

---

## 已知缺陷（当前失败的测试）

以下 3 条测试**故意保留为失败**——它们断言的是规格要求的行为，而当前实现不满足。
按约定**不改生产代码、不削弱断言、不删测试**。

### 缺陷 #1 —— 空态下没有拖放目标

- **测试**：`test/app/app_shell_workflow_test.dart` › `拖放打开文件 › 空态下也能把文件拖进来打开`
- **规格**：user story 1「把文件拖进窗口就打开」；空态文案「把媒体文件拖进来，或点「打开文件」」。
- **实现**：`lib/src/app/app.dart:370-402` `_buildBody()` —— `if (_paths.isEmpty) return _EmptyState(onOpen: _pickFiles);`
  只有在**已经有标签页**时才会返回带 `DragTarget` 的 `IndexedStack`。
- **后果**：一个文件都没打开时把文件拖进窗口**没有任何反应**，而界面却写着「把媒体文件拖进来」。
  失败信息：`Found 0 widgets with type "DragTarget<Object>"`。
- **修法**：把 `DragTarget` 提到 `_EmptyState` 外面（或让 `_EmptyState` 也在 `DragTarget` 里）。

### 缺陷 #2 —— 关闭一个标签页会让其余标签页重新解析

- **测试**：`test/app/app_shell_workflow_test.dart` › `标签页 › 关闭一个标签页，其余标签不受影响（不重新解析）`
- **规格**：user story 5「关闭一个标签页后其余不受影响，我不会丢掉正在看的内容」。
- **实现**：`lib/src/app/app.dart:388-400` `_buildBody()` 里的
  `IndexedStack(index: _selectedIndex, children: [DocumentTab(key: ValueKey(path)), …])`。
  Flutter 的 `IndexedStack` 会把每个子节点包进 **没有 key 的 `Visibility`**，
  `MultiChildRenderObjectElement.updateChildren` 只能**按位置**匹配这些 `Visibility`——
  于是关掉第 1 个标签后，第 2 个槽位上的 `DocumentTab` 从「文件 A」变成「文件 B」，
  key 变了 ⇒ 旧 State 被丢弃 ⇒ **B 被重新解析**（界面上闪回「解析中…」，
  结构树的展开状态与选中的块也一并丢失）。
- **失败信息**：`Expected: no matching candidates, Actual: Found 1 widget with text "解析中…"`。
- **修法**：给 `IndexedStack` 的直接子节点加 key（例如把 `DocumentTab` 的 key 提到 `Visibility` 外层，
  或改用 `PageView` / 自己管理可见性）。

### 缺陷 #3 —— MOV 与 WebM 缺「边界样本」

- **测试**：`test/platform/packaging_test.dart` › `每个格式都有可复现的样本与断言 › 每个格式至少有三类样本：正常 / 边界 / 损坏`
- **规格**：Testing Decisions「每个目标格式（WAV、AIFF、FLAC、MP3、MP4、MOV、MKV、WebM）
  至少覆盖三类样本：正常样本、边界样本（最小尺寸、罕见但合法的参数组合）、损坏样本」。
- **实现**：`test/fixtures/` 里 `mov_*` 只有 `normal` 与 `truncated`，`webm_*` 只有 `normal` 与 `truncated`，
  **没有 `.edge.` 素材**。
- **失败信息**：`Expected: empty, Actual: ['mov.edge', 'webm.edge']`。
- **修法**：用 `dart run tool/gen_fixtures.dart` 补两支边界素材（例如 MOV 的罕见参数组合、
  WebM 的最小尺寸样本）。

---

## 已知缺口（功能本身不存在，因此无测试）

### 缺口 #1 —— 没有「轨道数」字段

user story 10「看到它有几条轨道」。统一词表（`.scratch/media-info-mvp/issues/08-field-vocabulary.md`）
的 5 个文件级键与 10 个轨道级键里**没有 `track_count`**。
现在只能靠语义字段视图里「轨道 0 / 轨道 1 …」标题的个数来数（测试已断言标题个数 = 轨道数），
但没有一个可复制、可导出的数值字段。

### 缺口 #2 —— Matroska / WebM 不产出 `frame_rate`

user story 12「看到视频轨道的分辨率和帧率」。
`lib/src/formats/matroska.dart` 的提取器只取 `Video/PixelWidth`、`Video/PixelHeight`
与 `Video/FrameRate`（`0x2383E3`）；MKV/WebM 素材里没有这个元素，
但**有 `DefaultDuration`（`0x23E383`）**，可以换算成帧率——目前没有换算。
所以 MKV / WebM 的轨道级字段里**没有 `frame_rate`**（测试已断言 MP4/MOV 有、MKV 没有）。

### 缺口 #3 —— hex 视图没有「高亮某几个字节」

user story 27「能看到当前高亮的是哪几个字节，这样我能把 hex 和字段值对应起来」。
`lib/src/ui/hex_view.dart` 的 `HexView` 只接受 `node` + `filePath` + `byteLimit`，
没有任何「要高亮哪几个字节」的入参，渲染里也没有高亮逻辑。
因此**这条故事无法测试**——功能尚未实现。

### 缺口 #4 —— `uint64` 超过 2^63-1 会回绕

`FieldType.uint64` 的文档注释已经写明「> 2^63 的值不可表示」。
Dart 的 `int` 是 64 位有符号数，所以读出 `0xFFFFFFFFFFFFFFFF` 会得到 `-1`。
`co64`（> 4GB 的偏移）用的范围是 2^53…2^63-1，实际没问题；
但 8 字节无符号整数的**上半区间**不可表示。测试只断言了可表示区间
（`0x0000FFFFFFFFFFFF` → `281474976710655`）。

---

## 没被本次测试覆盖、但由并行工作流拥有的文件

以下文件由另一条工作流维护，本次**没有改动**，它们的测试同样计入仓库的总测试数：

- `test/app/app_widget_test.dart`
- `test/app/file_strip_test.dart`
- `test/app/export_json_document_test.dart`
- `test/app/export_test.dart`
- `test/app/app_render_test.dart`
- `test/app/parse_service_test.dart`
- `test/app/extension_check_test.dart`
- `test/app/all_formats_test.dart`
- `test/app/semantic_view_copy_test.dart`
