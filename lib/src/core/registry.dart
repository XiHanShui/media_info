import 'byte_source.dart';
import 'engine.dart';
import 'errors.dart';
import 'extractor.dart';
import 'node.dart';
import 'position_index.dart';
import 'spec.dart';

/// 一个已注册的容器格式。
///
/// 注册表登记的是**规格表 + 可选的叶子提取器**，不是解析器对象：
/// 加一个新容器 = 写一张 [ContainerSpec] 表 + 注册一行。
class FormatSpec {
  const FormatSpec({
    required this.name, // 'WAV'、'MP4'、'Matroska'、'FLAC'、'MP3'
    required this.container, // ContainerSpec
    this.extractor, // 叶子提取器
    this.detect, // 嗅探：从文件头判断是不是这个格式
    this.parser, // 自定义解析入口（容器结构不规则时用）
    this.positionIndexBuilder, // 字节位置 → 播放时间 的映射（格式自知字段名）
  });

  /// 格式名。
  final String name;

  /// 容器规格表。
  final ContainerSpec container;

  /// 叶子提取器：从已解析的树里取语义字段。
  final LeafExtractor? extractor;

  /// 嗅探函数：从文件头判断是不是这个格式。
  final bool Function(ByteSource)? detect;

  /// 自定义解析入口。
  ///
  /// 默认为 null，即用 [parseContainer] 读 [container] 这张表。但有些格式的
  /// 结构**装不进通用表**：
  /// - RIFF / AIFF / LIST：载荷开头有 4 字节 form type，通用引擎按 [HeaderRule.prefixBytes] 处理
  /// - FLAC：元数据块头是 1 bit + 7 bit + 24 bit 的位域，不是普通的 size 字段
  /// - MP3：根本没有块树，是连续的帧序列
  ///
  /// 这类格式由自己的模块提供解析函数，通过本字段接进来，**调用方无需知道差别**——
  /// 统一走 [parseFormat]。
  final ParseResult Function(ByteSource source, {int depth})? parser;

  /// 位置索引构建器：把"文件里的字节位置"映射到"播放时间"。
  ///
  /// 格式自知自己的字段名与块结构（WAV 的 `fmt ` 块、AIFF 的 `COMM` 块、
  /// MP3 的帧表），所以由各格式模块提供。没提供时用通用的线性估算兜底。
  final PositionIndex? Function(ContainerNode root, Duration duration)?
  positionIndexBuilder;
}

final List<FormatSpec> _registry = <FormatSpec>[];

/// 注册一个格式。
///
/// 同名格式会被替换（保持原位置），因此重复注册是安全的。
void registerFormat(FormatSpec spec) {
  final index = _registry.indexWhere((f) => f.name == spec.name);
  if (index >= 0) {
    _registry[index] = spec;
  } else {
    _registry.add(spec);
  }
}

/// 全部已注册格式，按嗅探顺序排列。
List<FormatSpec> allFormats() => List<FormatSpec>.unmodifiable(_registry);

/// 按内容嗅探选出一个格式；识别不出返回 null。
///
/// 嗅探按注册顺序进行，第一个命中者胜出。
FormatSpec? detectFormat(ByteSource source) {
  for (final format in _registry) {
    final detect = format.detect;
    if (detect == null) continue;
    bool matched;
    try {
      matched = detect(source);
    } on TruncatedFile {
      // 文件短到连魔数都读不全：不算命中，交给解析层去报截断。
      continue;
    }
    if (matched) return format;
  }
  return null;
}

/// 清空注册表（测试用）。
void clearFormats() => _registry.clear();

/// 解析一个已注册格式的结构树。
///
/// 这是**调用方应该用的唯一入口**：格式自己 quirks（RIFF 的 form type、FLAC 的位域块头、
/// MP3 的帧序列）都封装在 [FormatSpec.parser] 或规格表里，调用方不需要按格式分支。
///
/// [depth] 是展开的层数，1 = 只建第一层。
ParseResult parseFormat(FormatSpec spec, ByteSource source, {int depth = 1}) {
  final parser = spec.parser;
  if (parser != null) return parser(source, depth: depth);
  return parseContainer(spec.container, source, depth: depth);
}
