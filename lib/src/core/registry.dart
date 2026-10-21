import 'byte_source.dart';
import 'errors.dart';
import 'extractor.dart';
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
  });

  /// 格式名。
  final String name;

  /// 容器规格表。
  final ContainerSpec container;

  /// 叶子提取器：从已解析的树里取语义字段。
  final LeafExtractor? extractor;

  /// 嗅探函数：从文件头判断是不是这个格式。
  final bool Function(ByteSource)? detect;
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
