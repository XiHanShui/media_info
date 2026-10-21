# 调研 02：容器格式能否用声明式规格表描述

> 票号：`.scratch/media-info-mvp/issues/02-declarative-parsers.md`
> 目的：决定 MVP 的解析层是"N 个手写解析器"还是"N 张规格表 + 1 个通用引擎"。

---

## 结论摘要（先看这段）

**声明式可行，但可行的是"结构树"这一层，不是"语义字段"这一层。**

| 格式 | 容器框架（层级/偏移/长度/子块） | 叶子载荷（块内字段语义） | 判定 |
| --- | --- | --- | --- |
| EBML / Matroska / WebM | **完全声明式**——规范自己就发布了机器可读的 schema 表 | 完全声明式 | ✅ 表已经存在，Dart 引擎也已经存在 |
| FLAC metadata blocks | **完全声明式**——7 种 block，统一的 4 字节头 | 声明式，但需要"位域"字段类型 + 一处小端例外 | ✅ 表很小，引擎要支持位域 |
| RIFF（WAV / AVI） | **完全声明式**——所有 chunk 同一套规则 | 开放：chunk 类型无中心注册表，`fmt ` 载荷是 tagged union | ✅ 框架表极简；载荷按需手写 |
| ISO BMFF（MP4 / MOV） | **完全声明式**——box 头统一，层级由规范自己的表枚举 | 混合：sample entry 的类型是动态的、编解码器扩展块在别的规范里 | ✅ 结构表可行；叶子解码要手写 |

**单一最重要的一条发现**：Matroska 的元素层级**已经以声明式 schema 表的形式公开发布**（`ebml_matroska.xml`，262 个元素 / 262 个唯一 ID / 49 个 master 元素），而且 pub.dev 上已经有一个 `ebml` 包，把 RFC 8794 的 "EBML Schema" 数据结构直接实现成了 Dart 的数据类 + 一个通用解码引擎。换句话说，本票设想的两条路线中的"表 + 通用引擎"这一条，在 Matroska 上**既已被规范验证、也已被 Dart 生态验证**。

但要注意这条路的**边界**：声明式覆盖的是"结构树"（块名、偏移、长度、父子关系、原始 hex），这恰好就是 MVP 结构树视图需要的全部。而 MVP 的**语义字段**（时长、采样率、分辨率……）全部落在各格式的**叶子载荷**里，那里的确存在若干无法塞进一张表的异质点（见第 5 节）。所以最终形态是**混合式**，而不是"纯表"。

---

## 1. 各格式结构的规整度

### 1.1 ISO Base Media File Format（MP4 / MOV）

依据：ISO/IEC 14496-12:2012(E)（ISO 公开预览版；本机下载的副本见下方链接）与 ISO/IEC 14496-12:2022(E) 预览页。

- 公开 PDF（2012 版全文，196 页）：<https://ossrs.io/lts/zh-cn/assets/files/ISO_IEC_14496-12-base-format-2012-b70dd5f101daecd072700609842c9649.pdf>
- 2022 版预览（VDE Verlag，含 §6.3.1 Box 原文）：<https://assets.vde-verlag.de/iec-normen/preview-pdf/info_isoiec14496-12%7Bed7.0%7Den.pdf>
- 2022 版预览（ANSI，含目录）：<https://webstore.ansi.org/preview-pages/ISO/preview_ISO%2BIEC%2B14496-12-2022.pdf>
- ISO 官方条目：<https://www.iso.org/standard/83102.html>

#### 1.1.1 box 头是**一条**规则，覆盖所有 box

§4.2 Object Structure（2012 版第 5 页 / PDF 第 17 页）给出的 SDL：

```
aligned(8) class Box (unsigned int(32) boxtype, optional unsigned int(8)[16] extended_type) {
  unsigned int(32) size;
  unsigned int(32) type = boxtype;
  if (size==1) { unsigned int(64) largesize; }
  else if (size==0) { /* box extends to end of file */ }
  if (boxtype=='uuid') { unsigned int(8)[16] usertype = extended_type; }
}
```

以及 `FullBox`：

```
aligned(8) class FullBox(unsigned int(32) boxtype, unsigned int(8) v, bit(24) f) extends Box(boxtype) {
  unsigned int(8) version = v;
  bit(24) flags = f;
}
```

要点：

- `size == 1` → 后续 8 字节是 `largesize`（64 位总长）；`size == 0` → 该 box 延伸到文件末尾。**这两条是通用头规则的一部分，不是某个 box 的特例**，引擎里写一次就够。
- `type == 'uuid'` → 头后追加 16 字节 `extended_type`。同样是一次性的。
- 大量 box 带 `version` + 24 位 `flags`（`FullBox`），字段宽度随 `version` 变化，典型如 `tkhd`（§8.3.2.2）、`mdhd`（§8.4.2.2）：version 0 用 32 位时间/时长，version 1 用 64 位。规范同时规定 "Boxes with an unrecognized version shall be ignored and skipped."（§4.2）——对通用引擎而言，未知 version 降级成不透明叶子即可。

#### 1.1.2 层级是可枚举的，而且**规范自己就用一张表列出来了**

§6.2.3 Box Order 给出一张 "Table 1 — Box types, structure, and cross-reference"，用缩进表示容纳关系（2012 版第 12–14 页 / PDF 第 24–26 页）：

```
ftyp * 4.3 file type and compatibility
pdin 8.1.3 progressive download information
moov * 8.2.1 container for all the metadata
 mvhd * 8.2.2 movie header, overall declarations
 trak * 8.3.1 container for an individual track or stream
  tkhd * 8.3.2 track header, overall information about the track
  ...
  mdia * 8.4 container for the media information in a track
   minf * 8.4.4 media information container
    stbl * 8.5 sample table box, container for the time/space map
     stsd * 8.5.2 sample descriptions (codec types, initialization etc.)
```

这张表约 100 行，去重后 **88 种 box 类型**（`ftyp`…`prft`，含 `moov`/`trak`/`mdia`/`minf`/`stbl`/`stsd` 等容器）。每行还带条款交叉引用。

整个 ISO 家族在 MP4RA（注册机构）上已登记 **282 个 ISO 系 box code**，另有 42 个 user-data code 和 16 个 QuickTime code：
<https://mp4ra.org/registered-types/boxes>（页面标注 Last updated on: June 25, 2026）

所以"box 类型是否可枚举"的答案是：**能**，且枚举结果已经存在（规范 Table 1 + MP4RA 注册表）。

#### 1.1.3 变体与不规则点（精确清单）

| 现象 | 位置 | 对表结构的影响 |
| --- | --- | --- |
| `stco` / `co64` | §8.7.5.1 / §8.7.5.2 | **不是**同一个 box 的两种宽度，而是两个不同 type 的兄弟 box（"Exactly one variant must be present"）。表里写两条 box 规格，各带一个 `u32[]` / `u64[]` 数组即可。`co64` 只影响叶子载荷宽度，不影响框架。 |
| `stsz` / `stz2` | §8.7.3.2 / §8.7.3.3 | `stz2` 的条目位宽由载荷里的 `field_size` 决定（只能是 4 / 8 / 16），4 位时"每个字节装两个值"。这是一个**运行期决定宽度的数组**，需要引擎支持"按前一字段决定后续数组位宽"。 |
| `stsd` 的 sample entry | §8.5.2.2 | `SampleDescriptionBox` 内部是 `switch(handler_type)`：`'soun'` → `AudioSampleEntry`，`'vide'` → `VisualSampleEntry`，`'hint'`/`'meta'` 各有自己的。而 `SampleEntry extends Box(format)` —— **entry 的 box type 就是编码名**（`avc1` / `mp4a` / …），且 entry 的**字段布局**取决于这个 type。 |
| 视觉 sample entry 尾部的扩展 box | §8.5.2.2 `VisualSampleEntry` | SDL 末尾直接写 `// other boxes from derived specifications`，后面跟 `CleanApertureBox clap; // optional`、`PixelAspectRatioBox pasp; // optional`。`avcC` / `hvcC` / `esds` / `btrt` / `colr` 等**不在 14496-12 里**，而在 14496-15 等其它规范里。 |
| `colr` box | §8.5.2.2 | 载荷形状由 `colour_type` 决定（`'nclx'` 固定 7 字节 / `'rICC'` / `'prof'` 变长 ICC profile）。 |
| `compressorname` | §8.5.2.3 | 定长 32 字节字段，**首字节是实际长度**，其余是显示用字符。属于"定长 + 内嵌长度"型字符串。 |
| 字符串有三种形态 | 全篇 | 定长（`compressorname`）、NUL 结尾（`url `/`urn ` 的 location）、长度前缀（`dref` 内部其实是计数）。表里要区分这几种字段类型。 |
| 未知 box | §4.2 | "Boxes with an unrecognized type shall be ignored and skipped." → 通用引擎的兜底行为天然正确。 |

#### 1.1.4 "`stsd` → sample entry → `avcC` 能不能用同一张嵌套表表达？"

**部分能，但不可能只用 14496-12 一张表。**

- 框架层面能：`stsd` 是 FullBox + `entry_count` + N 个子 box；子 box 的 type 是动态的（编码名），所以表需要一个"按 type 分派到子表"的机制——**这是一张二级表，不是同一条表里的普通嵌套**。
- 但 `avcC` 的字段定义根本不在 14496-12 里，而在 ISO/IEC 14496-15（AVC file format）。所以"一张覆盖全 MP4 生态的嵌套表"必须跨规范拼装。
- 结论：**每份规范文档一张表，表与表之间用"按 type 分派"连接**。这仍然满足"表 + 引擎"的形态，只是表的粒度是"一份规范"而不是"一个格式"。

---

### 1.2 EBML / Matroska / WebM

依据：RFC 8794（EBML）、RFC 9559（Matroska）。

- <https://www.rfc-editor.org/rfc/rfc8794.html>
- <https://www.rfc-editor.org/rfc/rfc9559.html>

#### 1.2.1 VINT 编码

RFC 8794 §4：Variable-Size Integer = `VINT_WIDTH`（0 或多个 0 位）+ `VINT_MARKER`（单个 1 位）+ `VINT_DATA`。长度以 octet 计，1 octet 给 7 位数据，2 octet 给 14 位，以此类推（Table 1）。

- **Element ID**（§5）：默认 1–4 octet。`VINT_DATA` 不得全 0 或全 1，且**必须用最短编码**（否则非法）。
- **Element Data Size**（§6.1）：默认 1–8 octet。`VINT_DATA` **不要求**最短编码（所以同一长度可以有多种合法写法）。
- 长度范围见 §6.3 Table 6：1 octet 可表示 0…2⁷−2，8 octet 可表示 0…2⁵⁶−2（VINTMAX）。

#### 1.2.2 unknown size（未知长度）

RFC 8794 §6.2：

- "An Element Data Size with all VINT_DATA bits set to one is reserved as an indicator that the size of the EBML Element is unknown."
- "**Only a Master Element is allowed to be of unknown size**, and it can only be so if the `unknownsizeallowed` attribute of its EBML Schema is set to true."
- 结束位置由 schema 路径规则决定（Table 5 给了判定表）：新出现的 element 若路径合法，则按"是不是合法父元素 / 是不是同父兄弟 / 是不是 root"来决定未知长度 master 的结束。

对引擎的含义：unknown size 只能在 **master 元素**上出现，且需要引擎拿着 schema 的路径信息来判断何时收尾。这是**唯一一处"结构依赖语义表"的解析规则**——它恰好也是声明式的，因为 schema 表里就有 `path` / `unknownsizeallowed` 属性。

#### 1.2.3 元素层级就是一张声明式表，而且规范把它标准化了

RFC 8794 §11.1 定义了 **EBML Schema**——一份 XML 文档，用 `<element>` 节点描述每个元素：

```xml
<element name="EBMLReadVersion" path="\EBML\EBMLReadVersion"
  id="0x42F7" minOccurs="1" maxOccurs="1" range="1" default="1" type="uinteger"/>
```

属性（§11.1.6）：`name`、`path`、`id`、`minOccurs`、`maxOccurs`、`range`、`length`、`defaultValue`、`type`、`unknownsizeallowed`、`recursive`、`recurring`、`minver`、`maxver`。

元素类型只有 8 种（§7）：`integer`、`uinteger`、`float`、`string`、`utf-8`、`date`、`master`、`binary`。

也就是说：**"EBML Schema"这个概念本身就是本票想要的"声明式规格表"的标准化版本**，且是 IETF Standards Track 文档。

#### 1.2.4 Matroska 的表已经以机器可读形式发布

Matroska 规范仓库（RFC 9559 的源仓库）里就有 `ebml_matroska.xml`：
<https://github.com/ietf-wg-cellar/matroska-specification>
<https://raw.githubusercontent.com/ietf-wg-cellar/matroska-specification/master/ebml_matroska.xml>

本机实测统计（对 master 分支 raw 文件）：

- 总大小 141,668 字节
- `<element>` 条目 **262** 条，**唯一 `id` 262 个**
- `type="master"` 49 条；`unknownsizeallowed="1"` 2 条；`recurring="1"` 3 条
- 类型分布：`uinteger` 129、`master` 49、`binary` 30、`float` 19、`utf-8` 16、`string` 14、`integer` 4、`date` 1

样例（文件开头）：

```xml
<EBMLSchema xmlns="urn:ietf:rfc:8794" docType="matroska" version="4">
  <element name="Segment" path="\Segment" id="0x18538067" type="master"
            minOccurs="1" maxOccurs="1" unknownsizeallowed="1"> ... </element>
  <element name="SeekID" path="\Segment\SeekHead\Seek\SeekID" id="0x53AB"
            type="binary" length="4" minOccurs="1" maxOccurs="1"/>
```

RFC 9559 §4.3 追加的约束也很简单：docType 必须是 `"matroska"`、`EBMLMaxIDLength` 必须为 4、`EBMLMaxSizeLength` 在 1..8。

#### 1.2.5 Matroska 的不规则点

- **Block Lacing**（RFC 9559 §10.3）：`SimpleBlock` / `BlockGroup` 的载荷有 4 种 lacing（No Lacing / Xiph Lacing / EBML Lacing / Fixed-size Lacing），由 flags 里的 lacing 位决定。这意味着**块载荷内部不是固定字段序列**。但这属于"载荷语义"层；结构树里它就是一个不透明的二进制块。
- **Segment 可以是 unknown size**，且 Matroska 允许 EBML Stream（多个文档拼接，§4.5、RFC 8794 §9）。
- CRC-32 是 global element，可以出现在任意 master 里。

**判定：EBML 是四种格式里最"声明式友好"的，且它同时把表和引擎的概念都标准化了。**

---

### 1.3 RIFF（WAV / AVI）

依据：Library of Congress Sustainable Formats 条目 fdd000025（RIFF，Draft status: Full）+ Microsoft Learn 的 RIFF 文档。

- LOC FDD：<https://www.loc.gov/preservation/digital/formats/fdd/fdd000025.shtml>
- RIFF 概述（XAudio2）：<https://learn.microsoft.com/en-us/windows/win32/xaudio2/resource-interchange-file-format--riff->
- RIFF Services（父子 chunk 规则）：<https://learn.microsoft.com/en-us/previous-versions/ms713231(v=vs.85)>
- WAVEFORMATEX：<https://learn.microsoft.com/en-us/windows/win32/api/mmreg/ns-mmreg-waveformatex>

#### 1.3.1 框架规则只有两条

Microsoft Learn 的 RIFF 页原文：

```
RIFF chunk:  "RIFF", fileSize, fileType, data
other chunk: chunkID, chunkSize, data
```

- `fileSize` / `chunkSize` 是 4 字节值；`chunkSize` **不含** padding、chunkID、chunkSize 本身。
- "The data is always padded to the nearest WORD boundary."（奇数长度补 1 字节 padding）
- ms713231："The only chunks allowed to contain subchunks are those with a chunk identifier of `"RIFF"` or `"LIST"`."；RIFF 首个 4 字节是 **form type**（如 `WAVE`），LIST 首个 4 字节是 **list type**（如 `INFO`）。

#### 1.3.2 规整度评估

- **框架层：完全声明式**。一条 chunk 规则 + "RIFF/LIST 有子块、其它没有"。
- **载荷层：开放**。chunk type 是 FourCC，**没有中心注册表**（LOC FDD 原文："new chunk types can be defined"，并且明确说"Applications that play or render RIFF files may ignore chunks with labels they do not recognize"）。每个 FourCC 的载荷格式由具体子格式规定，不在 RIFF 规范里。
- `fmt ` chunk 是典型的 tagged union：`WAVEFORMATEX` 固定 18 字节（`wFormatTag`/`nChannels`/`nSamplesPerSec`/`nAvgBytesPerSec`/`nBlockAlign`/`wBitsPerSample`/`cbSize`），后面跟 `cbSize` 字节的扩展数据；`wFormatTag == WAVE_FORMAT_EXTENSIBLE` 时扩展区是 `WAVEFORMATEXTENSIBLE`（含 GUID + 声道掩码），其他 tag 则各不相同。
- `LIST` 的 list type（如 `INFO`）下面又是按 FourCC 命名的文本子块，且有"注册过的是大写、未注册的是小写"这种约定。

**判定：RIFF 的"结构树"可以完全由一张极小的表生成；但要从 `fmt ` 里读出采样率/位深/声道数，就必须按 `wFormatTag` 分派——这是手写代码，不是表。**

---

### 1.4 FLAC metadata blocks

依据：RFC 9639（FLAC，2024-12）。旧的 xiph.org/flac/format.html 页面现在只是一个指向 RFC 9639 的索引。

- <https://www.rfc-editor.org/rfc/rfc9639.html>
- <https://xiph.org/flac/format.html>（旧页，现为 RFC 9639 的导航）

#### 1.4.1 统一的块头

RFC 9639 §8.1：每个 metadata block 以 4 字节头开始——1 bit "是不是最后一个块" + 7 bit 类型 + 24 bit 长度（大端，不含这 4 字节）。类型取值：

| 值 | 类型 |
| --- | --- |
| 0 | STREAMINFO |
| 1 | PADDING |
| 2 | APPLICATION |
| 3 | SEEKTABLE |
| 4 | VORBIS_COMMENT |
| 5 | CUESHEET |
| 6 | PICTURE |
| 7–126 | Reserved |
| 127 | Forbidden（避免与帧同步码混淆） |

§6 原文："FLAC supports 127 kinds of metadata blocks; currently, 7 kinds are defined in Section 8."

#### 1.4.2 各块载荷是**位域**表，不是字节字段表

§8.2 STREAMINFO 的字段序列：

```
u(16) min block size      u(16) max block size
u(24) min frame size      u(24) max frame size
u(20) sample rate
u(3)  channels - 1
u(5)  bits per sample - 1
u(36) total samples
u(128) MD5
```

注意 `u(20)` / `u(3)` / `u(5)` / `u(36)` —— **不是字节对齐的**。所以引擎必须支持"位域"字段类型，而不只是"定长字节"字段。这是 FLAC 相对其它三种格式多出来的一个引擎要求。

其它块：

- PADDING（§8.3）：`u(n)`，n 是块长度 × 8，纯填充。
- APPLICATION（§8.4）：`u(32)` 应用 ID（IANA 注册）+ `u(n)` 应用数据。
- SEEKTABLE（§8.5）：数量由块长度 / 18 隐含，每条 seek point 固定 18 字节（`u(64)` 采样号 + `u(64)` 偏移 + `u(16)` 采样数）。
- VORBIS_COMMENT（§8.6）：4 字节 vendor 长度 + vendor 串 + 4 字节字段数 + 每个字段 4 字节长度 + 内容。**注意 §5 明说：FLAC 里所有数字都是大端，"except the field lengths used in Vorbis comments ... which are little-endian coded"** —— 这是唯一的字节序例外。
- CUESHEET（§8.7）：`u(128*8)` 目录号 + `u(64)` lead-in + `u(1)` 标志 + `u(7+258*8)` 保留 + `u(8)` 轨道数 + N 条 track 记录；track 记录里又是 `u(8)` 索引点数 + N 条索引记录（计数前缀的嵌套记录）。
- PICTURE（§8.8）：`u(32)` 类型 + `u(32)` MIME 长度 + MIME + `u(32)` 描述长度 + 描述 + 4 个 `u(32)` + `u(32)` 数据长度 + 数据。

#### 1.4.3 判定

**FLAC 的 metadata 层是四种格式里表最小、最规整的**——7 种块类型 + 1 条统一的头规则 + 每种块一张字段表。代价是引擎必须支持位域字段和"块内小端"这两种额外能力。

（FLAC 的**帧**部分——frame header / subframe / Rice 码——完全不适合声明式，但那是音频载荷，MVP 不解码音频，且结构树里它只是一个不透明的连续区。）

---

## 2. Dart 生态调查

搜索方式：pub.dev 通过 `PUB_HOSTED_URL=https://pub.flutter-io.cn` 镜像访问，本机用镜像的 `api/search` 与 `api/packages/<name>` 接口逐个核对（pub.dev 官方页面 URL 仍按惯例给出）。

### 2.1 通用"声明式二进制解析"库

| 包 | pub.dev | 说明 | 适配度 |
| --- | --- | --- | --- |
| `binstruct` | <https://pub.dev/packages/binstruct> | 0.2.5（2025-07-14）。"A binary struct parser/builder similar to Python's `construct`"。README 自称 "currently in its infancy"。 | ❌ **不能用**。实测源码（`lib/src/types.dart`，仅 147 行）只有 `Int8` / `Uint8` / `Int16` / `Uint16` / `Float32` 和一个 `StructField` 嵌套。**没有 32/64 位整数、没有数组、没有长度前缀、没有条件字段、没有 seek/switch、没有变长整数**。字节序是解析时的运行期参数而不是结构的一部分。pubspec 里没有 repository / homepage。 |

没有找到其他"表驱动二进制解析"库。搜索 `kaitai` 在 pub.dev 上没有任何相关包（返回的 10 个全是图标类包）——**Kaitai Struct 在 Dart 生态没有运行时**，`.ksy` 规范文件对本项目不可用。

### 2.2 格式专用包

| 包 | pub.dev | 说明 | 适配度 |
| --- | --- | --- | --- |
| `ebml` | <https://pub.dev/packages/ebml> | 1.0.1（2023-09-01），仓库 <https://github.com/abitofevrything/dart_ebml>。**"An RFC 8749 compliant Extensible Binary Meta Language parser"**，README 说按 RFC 8794 实现。 | ⭐ **形态完全对**。源码实测：`lib/src/schema/schema.dart` 里的 `Schema` / `SchemaElement` / `Path` / `PathAtom` / `GlobalPlaceholder` / `ElementType` / `Range` **逐字对应 RFC 8794 §11.1 的 EBML Schema 属性**；`lib/src/ebml/element.dart` 的 `Element` 子类（`SignedIntegerElement` / `UnsignedIntegerElement` / `FloatElement` / `StringElement` / `Utf8Element` / `DateElement` / `MasterElement` / `BinaryElement`）**逐字对应 RFC 8794 §7 的 8 种元素类型**；`lib/src/schema/predefined_schema.dart` 内置了 EBML Header 的 schema（`EBML` / `EBMLVersion` / `EBMLReadVersion` / `EBMLMaxIDLength` / …）。<br>⚠️ 但：**只内置 EBML Header 的表，没有 Matroska 的表**（Matroska 表得自己从 `ebml_matroska.xml` 转成 Dart 数据）；最后发布于 2023-09，仅 2 个版本；pubspec 描述里写的 "RFC 8749" 是已被 RFC 8794 取代的旧版 EBML RFC（README 才是 8794）；依赖 `petitparser` + `xml`。 |
| `mediaindex_dart` | <https://pub.dev/packages/mediaindex_dart> | 0.0.2（2022-06-05），仓库 <https://github.com/suconghou/mediaindex-dart>。"mp4 and webm media files sidx segment and ebml box parser for dart"。 | ❌ **不能用**。源码实测：`lib/ebml.dart` 里手写了 VINT 读取，再用硬编码 map `EBMLParserTypes.types` 只覆盖 Cues 子树（6 个 ID）。而且 pubspec 的 SDK 约束是 `>=2.15.1 <3.0.0`——**在本机 Dart 3.11.4 上根本 resolve 不下来**。 |
| `flac_metadata` | <https://pub.dev/packages/flac_metadata> | 1.1.0（2024-06-15），仓库 <https://github.com/zengkid/flac_metadata>。 | ⚠️ 只做 tag 提取（Vorbis comment / picture），**不做结构遍历**。 |
| `audio_metadata_reader` | <https://pub.dev/packages/audio_metadata_reader> | 1.8.1（2026-10-14），仓库 <https://github.com/ClementBeal/audio_metadata_reader>。 | ⚠️ "Support ID3, Vorbis comments and ILST itunes"——**标签级**，不是容器结构级。 |

### 2.3 小结

- **没有现成可用的 Dart"通用声明式二进制解析"库**。`binstruct` 太幼小，`kaitai` 无 Dart 运行时。
- **但"表 + 引擎"这个形态本身在 Dart 里已经被验证过一次**：`ebml` 包把 RFC 8794 的 EBML Schema 数据结构 + 一个通用 EBML 解码引擎写出来了（约 2,400 行）。它最大的价值不是代码本身，而是**它证明了 RFC 8794 的 schema 属性集合足以驱动一个通用引擎**。
- 因此最务实的路线是：**自建一个 ~300–500 行的规格表 DSL + 通用容器遍历引擎**，把 `ebml` 包的 schema 数据类当作字段清单的参考，而不是引入依赖。

---

## 3. Dart 侧的草图

### 3.1 规格表（伪代码）

一份统一的"规格表"模型，覆盖四种格式所需的表达能力：

```dart
// ---- 规格表的核心模型 ----

enum FieldKind {
  uint,        // 固定位宽无符号整数
  sint,        // 固定位宽有符号整数
  bits,        // 位域（FLAC 用：u(20) / u(36)）
  bytes,       // 原始字节，count 可由前一字段决定
  fourcc,      // 4 字节 ASCII 标识
  string,      // 长度策略由 lengthMode 决定
  version,     // 1 字节 version
  flags,       // 24 位 flags
}

enum LengthMode { fixed, remaining, count, prefix, nullTerminated, pascal32, cbSize }

class Field {
  final String name;
  final FieldKind kind;
  final int width;              // 位宽（uint/sint/bits）
  final LengthMode lengthMode;
  final int? countFrom;         // 数组长度来自哪个前驱字段
  final int? byteSizeFrom;      // 字节长度来自哪个前驱字段
  final int? offsetOf;          // 固定偏移（如 FLAC 的 128 字节 MD5）
  final int? byteLengthOf;      // 长度来自哪个前驱字段（如 RIFF 的 cbSize）
  final Endian endian;          // 大端 / 小端 / 继承
  final String? whenVersion;    // 条件字段：仅当 version == N 时存在
  final String? whenType;       // 条件字段：仅当分派键 == X 时存在
}

class ChunkSpec {
  final String name;            // 展示名，如 'stsd' / 'VideoSampleEntry'
  final String? id;             // box type / EBML element id / FLAC block type
  final bool isFullBox;         // 是否带 version + flags
  final List<Field> fields;
  final List<ChunkSpec> children;// 固定子块
  final String? dispatchOn;     // 按哪个字段分派子表
  final Map<String, ChunkSpec> dispatchTable;
  final bool opaque;            // 未知类型 → 不透明叶子
}
```

### 3.2 各格式的表长什么样（示意）

**MP4**——顶层只有一条"box 头规则"，其余是表：

```dart
// box 头是统一的，不属于任何一张 box 表
class BoxHeader {
  final int size;         // u32
  final String type;      // FourCC
  final int? largesize;   // size == 1 时存在
  final bool toEof;       // size == 0
  final String? uuid;     // type == 'uuid' 时存在
}

const mp4 = ContainerSpec(
  header: BoxHeaderRule(),          // 引擎内建一次
  children: {
    'moov': BoxSpec('moov', children: {
      'mvhd': BoxSpec('mvhd', isFullBox: true, fields: [
        Field('version', FieldKind.version),
        Field('flags', FieldKind.flags),
        If('version', 0, [
          Field('creation_time', FieldKind.uint, 32),
          Field('modification_time', FieldKind.uint, 32),
          Field('timescale', FieldKind.uint, 32),
          Field('duration', FieldKind.uint, 32),
        ]),
        If('version', 1, [
          Field('creation_time', FieldKind.uint, 64),
          Field('modification_time', FieldKind.uint, 64),
          Field('timescale', FieldKind.uint, 32),
          Field('duration', FieldKind.uint, 64),
        ]),
      ]),
      'trak': BoxSpec('trak', children: {
        'tkhd': BoxSpec('tkhd', isFullBox: true, fields: [ /* … */ ]),
        'mdia': BoxSpec('mdia', children: {
          'minf': BoxSpec('minf', children: {
            'stbl': BoxSpec('stbl', children: {
              'stsd': BoxSpec('stsd', isFullBox: true, fields: [
                Field('entry_count', FieldKind.uint, 32),
              ], children: [
                // 关键：子块 type 是动态的（编码名），按 handler_type + 编码名分派
                Dispatch('handler_type', {
                  'vide': BoxSpec('VideoSampleEntry', dispatchOn: 'format', dispatchTable: {
                    'avc1': BoxSpec('avc1', fields: [ /* VisualSampleEntry 公共字段 */ ],
                                    children: { 'avcC': /* 来自 14496-15 的另一张表 */ }),
                    'hvc1': BoxSpec('hvc1', /* … */),
                    '_default': BoxSpec('VideoSampleEntry', opaque: false),
                  }),
                  'soun': BoxSpec('AudioSampleEntry', dispatchOn: 'format', dispatchTable: { /* … */ }),
                }),
              ]),
              'stco': BoxSpec('stco', isFullBox: true, fields: [
                Field('entry_count', FieldKind.uint, 32),
                Repeat('entry_count', Field('chunk_offset', FieldKind.uint, 32)),
              ]),
              'co64': BoxSpec('co64', isFullBox: true, fields: [
                Field('entry_count', FieldKind.uint, 32),
                Repeat('entry_count', Field('chunk_offset', FieldKind.uint, 64)),
              ]),
              'stz2': BoxSpec('stz2', isFullBox: true, fields: [
                Field('field_size', FieldKind.uint, 8),   // 决定后续数组位宽
                Field('sample_count', FieldKind.uint, 32),
                Repeat('sample_count', Field('entry_size', FieldKind.uint, fromField: 'field_size')),
              ]),
            }),
          }),
        }),
      }),
    }),
    'ftyp': BoxSpec('ftyp', fields: [
      Field('major_brand', FieldKind.fourcc),
      Field('minor_version', FieldKind.uint, 32),
      Repeat('toEnd', Field('compatible_brands', FieldKind.fourcc)),
    ]),
    'mdat': BoxSpec('mdat', opaque: true),   // 叶子
  },
);
```

**EBML / Matroska**——表直接对应 RFC 8794 的 EBML Schema：

```dart
class ElementSpec {
  final String name;
  final int id;
  final String path;
  final ElementType type;       // master / uinteger / binary / utf-8 / …
  final int? minOccurs, maxOccurs;
  final int? length;            // 定长载荷（如 SeekID length=4）
  final bool unknownSizeAllowed;
  final bool recurring;
  final num? defaultValue;
  final Range? range;
}

// 直接从官方 ebml_matroska.xml 转出来的表（262 条）
final matroskaSchema = EbmlSchema(
  docType: 'matroska',
  version: 4,
  elements: [
    ElementSpec('Segment', 0x18538067, r'\Segment', ElementType.master,
                minOccurs: 1, maxOccurs: 1, unknownSizeAllowed: true),
    ElementSpec('SeekID', 0x53AB, r'\Segment\SeekHead\Seek\SeekID',
                ElementType.binary, length: 4, minOccurs: 1, maxOccurs: 1),
    ElementSpec('TimestampScale', 0x2AD7B1, r'\Segment\Info\TimestampScale',
                ElementType.uinteger, defaultValue: 1000000),
    // …共 262 条
  ],
);
```

**FLAC**——位域 + 一处小端：

```dart
const flacBlockTypes = {0: 'STREAMINFO', 1: 'PADDING', 2: 'APPLICATION',
                        3: 'SEEKTABLE', 4: 'VORBIS_COMMENT', 5: 'CUESHEET',
                        6: 'PICTURE'};

const flac = ContainerSpec(
  header: MetadataBlockHeaderRule(),   // 1 bit last + 7 bit type + 24 bit length
  children: {
    'STREAMINFO': BlockSpec(fields: [
      Field('min_block_size', FieldKind.uint, 16),
      Field('max_block_size', FieldKind.uint, 16),
      Field('min_frame_size', FieldKind.uint, 24),
      Field('max_frame_size', FieldKind.uint, 24),
      Field('sample_rate', FieldKind.bits, 20),
      Field('channels', FieldKind.bits, 3),
      Field('bits_per_sample', FieldKind.bits, 5),
      Field('total_samples', FieldKind.bits, 36),
      Field('md5', FieldKind.bytes, 16),
    ]),
    'VORBIS_COMMENT': BlockSpec(fields: [
      Field('vendor_length', FieldKind.uint, 32, endian: Endian.little),  // 例外
      Bytes('vendor', lengthFrom: 'vendor_length'),
      Field('field_count', FieldKind.uint, 32, endian: Endian.little),
      Repeat('field_count', Group([
        Field('length', FieldKind.uint, 32, endian: Endian.little),
        Bytes('value', lengthFrom: 'length'),
      ])),
    ]),
    // …
  },
);
```

**RIFF**——框架表极简，载荷走"不透明 + 可选手写解码器"：

```dart
const riff = ContainerSpec(
  header: ChunkHeaderRule(),   // FourCC + u32 size（LE）
  padTo: 2,                    // 奇数长度补 1 字节
  children: {
    'RIFF': ChunkSpec('RIFF', formType: true, children: { /* 任意 chunk */ }),
    'LIST': ChunkSpec('LIST', listType: true, children: { /* 任意 chunk */ }),
  },
  // 'fmt ' 不进 children 表：它的载荷按 wFormatTag 分派，交给手写解码器
);
```

### 3.3 最小通用引擎

引擎只需要做四件事：

```dart
// 1. 读头：按容器家族的 header rule 解出 size / type / 扩展头
// 2. 查表：type → ChunkSpec（查不到 → 不透明叶子，规范要求"忽略并跳过"）
// 3. 走字段：按 Field 列表读值，遇到 children / dispatch 就递归
// 4. 产出统一节点：每个节点带 name / type / offset / size / children / raw

class ParseResult {
  final List<Chunk> chunks;   // 统一节点模型
  final List<SemanticField> fields;  // 语义字段（由叶子提取器填充）
}

class Engine {
  Engine(this.spec);
  final ContainerSpec spec;

  ParseResult parse(ByteSource src) {
    // 外层循环：反复读 header + body，直到 EOF
    //   body → 按 spec 的 children / dispatch 递归
    //   任何未识别 type → 产出不透明叶子，不递归（保持健壮）
  }
}
```

引擎**必须**支持的能力清单（这是本次调研的主要工程产出）：

| 能力 | 需要它的格式 |
| --- | --- |
| 32 / 64 位长度 + "size==0 延伸到 EOF" | MP4（`largesize`）、EBML（VINT 到 8 octet） |
| 变长整数（VINT）解码 | EBML |
| unknown size + 基于路径的收尾判定 | EBML（`Segment`） |
| version 条件字段 | MP4（`tkhd`/`mdhd`…）、FLAC 无 |
| 24 位 flags | MP4（FullBox） |
| 按前一字段决定后续数组宽度 | MP4（`stz2` 的 `field_size`） |
| 计数前缀数组 / 嵌套记录 | MP4、FLAC（`CUESHEET`） |
| 长度前缀字节串 | FLAC（`PICTURE`/`VORBIS_COMMENT`）、MP4（`compressorname`） |
| 位域（bit-level）字段 | FLAC（`u(20)`/`u(36)`） |
| 块内字节序切换 | FLAC（Vorbis comment 小端） |
| 动态 type 分派 + 二级表 | MP4（`stsd` → sample entry） |
| 自描述尾部长度 | RIFF（`fmt ` 的 `cbSize`） |
| "未知即跳过"兜底 | 全部（规范明文要求） |

---

## 4. 各格式的"不规则点"精确清单

如果最终选择"表 + 引擎"，下面这些地方**必须**留手写逃生口（不能只靠表）：

**MP4 / MOV**
1. `stsd` 的 sample entry：box type 是动态的（编码名），entry 字段布局随 type 变。→ 需要"按 type 分派到二级表"的能力；表能表达，但表本身要跨规范（`avcC` 在 14496-15）。
2. `stz2` 的位宽由载荷决定（4/8/16，4 位时半字节打包）→ 需要"运行期定宽数组"。
3. `colr` 的 `colour_type` 决定载荷形状 → 需要"按 tag 分派的变长载荷"。
4. 编解码器配置记录本身（`avcC` / `hvcC` / `esds` / `btrt` …）不在 14496-12 里，要另立表或干脆当不透明。
5. `version`/`flags` 的**位级含义**（如 `tkhd` 的 `track_enabled`）不在 box 结构里，属语义层。

**EBML / Matroska**
1. `SimpleBlock` / `BlockGroup` 载荷的 4 种 lacing → 载荷不可表驱动；结构树里当不透明叶子即可。
2. unknown size 的收尾判定需要 schema 的路径信息（引擎能查表解决，但逻辑本身不是"读字段"）。
3. WebM 的子集限制（`ebml_matroska.xml` 里用 `<extension type="webmproject.org" webm="1"/>` 标注）与 Matroska 完整集不同，需要在表里保留这层信息。

**RIFF / WAV / AVI**
1. chunk type 无中心注册表 → 表只能是"通配 + 不透明"，不能穷举。
2. `fmt ` 载荷是 tagged union（`wFormatTag` 决定是 `WAVEFORMATEX` / `WAVEFORMATEXTENSIBLE` / 别的），且 `cbSize` 决定扩展长度 → 表能表达"定长头 + N 字节扩展"，但"扩展里是什么"必须按 tag 分派（手写）。
3. `LIST` 的 list type（如 `INFO`）下的子块语义也不在 RIFF 规范里。

**FLAC**
1. 块载荷是**位域**而非字节字段 → 引擎必须支持 bit-level（这是 FLAC 独有的额外要求）。
2. Vorbis comment 的长度字段是**小端**（FLAC 唯一的字节序例外）。
3. `PADDING` / `APPLICATION` 的尾部是纯字节（长度由块头决定）。

**共同问题**
- 三种格式的规范都要求"未识别的类型必须被忽略并跳过"，这对通用引擎是天然的好消息：引擎永远能产出一个完整的结构树，即使遇到没见过的扩展。

---

## 5. 对架构的影响

### 5.1 建议的解析层形态

不要在"N 个手写解析器"和"N 张表 + 1 个引擎"之间二选一。真实的最优形态是**三层**：

```
第 1 层：规格表（声明式数据）
  · mp4_boxes.dart / matroska_schema.dart / riff_chunks.dart / flac_blocks.dart
  · 数据，不是代码；每个格式一张（或几张，按规范文档切）

第 2 层：通用容器引擎（代码，一次）
  · 读头 → 查表 → 走字段 → 递归 → 产出统一节点
  · 支持位域、VINT、unknown size、版本条件、计数/长度前缀数组、动态 type 分派

第 3 层：叶子提取器（少量手写代码）
  · 从已解析的树里取语义字段：时长、采样率、位深、声道数、分辨率、帧率
  · 每个格式一个小的 extractor，不重复解析字节
```

**这个划分正好和 MVP 的既有前提对齐**：结构树（偏移/长度/hex）完全由第 1+2 层产出；语义字段（时长/采样率/分辨率）由第 3 层产出。地图里"语义字段深度：轨道级，不做编码参数级"的约束，恰好让第 3 层保持很小。

### 5.2 对"解析器注册表"扩展点的影响

地图里写的是"以『解析器注册表』为扩展点"。如果采纳本结论，注册表登记的应该是**规格表 + 可选的叶子提取器**，而不是解析器对象。扩展点形状不变，粒度变细——这反而更容易让第三方加一个新容器（写一张表）而不是写一整个解析器。

### 5.3 需要重新评估的前提

- **纯 Dart 手写**这条前提**不需要改**。第 1、2 层都是纯 Dart。
- "每格式一个解析器"这条前提**需要微调**：变成"每格式一张表 + 一个 extractor"，总量可能持平甚至更少，但换来了"未识别块自动降级成不透明叶子"的健壮性——这对一个"要展示原始结构"的工具是刚需，手写解析器通常不会为未知块写兜底。

### 5.4 不建议做的事

- **不要引入 `binstruct`**：实测它只有 8/16 位整数 + float32 + 嵌套 struct，要补齐 MP4/EBML/FLAC 需要的全部能力等于重写，而且没有维护者、没有 repository。
- **不要直接依赖 `ebml` 包**：它形态正确但 2023-09 后未更新、只内置 EBML Header 表、不含 Matroska 表、pubspec 描述里的 RFC 号是旧的。但它**值得当作 schema 属性清单的参考**（把它的 `SchemaElement` 字段设计抄进我们自己的 `ElementSpec`，再补上 MP4/RIFF/FLAC 需要的字段类型）。抄设计的成本远低于适配依赖的成本。
- **不要指望 Kaitai `.ksy`**：pub.dev 上没有 Dart 运行时。
- **不要把 `mediaindex_dart` 当起点**：SDK 约束 `<3.0.0`，在本机 resolve 不下来；实现也只是硬编码 map。

### 5.5 建议的后续动作

1. 把"声明式表 + 通用引擎"作为 MVP 解析层的正式架构决策写进规格（对应地图里的"解析架构"这一项）。
2. 先做一个**纵切验证**：用最小表集实现 MP4 的 `moov → trak → mdia → minf → stbl → stsd`，确认 `version` 条件字段 + 动态 type 分派这两处能在引擎里表达，再推广到其它三种格式。
3. 把 `ebml_matroska.xml` → Dart 表 的转换脚本当作独立小任务（它是机械转换，且有官方 XML 作为唯一真相源）。
4. 语义字段 extractor 的清单按地图"轨道级"约束逐格式列出，评估它是否小到可以接受（这决定了第 3 层会不会膨胀）。

---

## 参考来源清单

**规范（primary）**
- ISO/IEC 14496-12:2012(E)《ISO base media file format》—— <https://ossrs.io/lts/zh-cn/assets/files/ISO_IEC_14496-12-base-format-2012-b70dd5f101daecd072700609842c9649.pdf>（§4.2 Box/FullBox、§6.2.3 Table 1、§8.5.2 stsd、§8.7.3/§8.7.5）
- ISO/IEC 14496-12:2022(E) 预览 —— <https://assets.vde-verlag.de/iec-normen/preview-pdf/info_isoiec14496-12%7Bed7.0%7Den.pdf>、<https://webstore.ansi.org/preview-pages/ISO/preview_ISO%2BIEC%2B14496-12-2022.pdf>
- MP4RA 注册表（box types） —— <https://mp4ra.org/registered-types/boxes>
- RFC 8794《Extensible Binary Meta Language》 —— <https://www.rfc-editor.org/rfc/rfc8794.html>（§4 VINT、§5 ID、§6 Data Size / unknown size、§7 Element Types、§11.1 EBML Schema）
- RFC 9559《Matroska Media Container Format Specification》 —— <https://www.rfc-editor.org/rfc/rfc9559.html>（§4.3 附加约束、§10.3 Block Lacing）
- Matroska EBML Schema（机器可读） —— <https://github.com/ietf-wg-cellar/matroska-specification>、<https://raw.githubusercontent.com/ietf-wg-cellar/matroska-specification/master/ebml_matroska.xml>
- RFC 9639《FLAC》 —— <https://www.rfc-editor.org/rfc/rfc9639.html>（§5 字节序规则、§6 布局总览、§8.1–8.8 metadata blocks）
- Library of Congress Sustainable Formats: RIFF (fdd000025) —— <https://www.loc.gov/preservation/digital/formats/fdd/fdd000025.shtml>
- Microsoft Learn: Resource Interchange File Format (RIFF) —— <https://learn.microsoft.com/en-us/windows/win32/xaudio2/resource-interchange-file-format--riff->
- Microsoft Learn: RIFF Services —— <https://learn.microsoft.com/en-us/previous-versions/ms713231(v=vs.85)>
- Microsoft Learn: WAVEFORMATEX —— <https://learn.microsoft.com/en-us/windows/win32/api/mmreg/ns-mmreg-waveformatex>

**代码与包（primary）**
- `ebml` 1.0.1 —— <https://pub.dev/packages/ebml>、<https://github.com/abitofevrything/dart_ebml>、源码 `lib/src/schema/schema.dart`、`lib/src/ebml/element.dart`、`lib/src/schema/predefined_schema.dart`
- `binstruct` 0.2.5 —— <https://pub.dev/packages/binstruct>、源码 `lib/src/types.dart`
- `mediaindex_dart` 0.0.2 —— <https://pub.dev/packages/mediaindex_dart>、<https://github.com/suconghou/mediaindex-dart>、源码 `lib/ebml.dart`
- `flac_metadata` 1.1.0 —— <https://pub.dev/packages/flac_metadata>
- `audio_metadata_reader` 1.8.1 —— <https://pub.dev/packages/audio_metadata_reader>
