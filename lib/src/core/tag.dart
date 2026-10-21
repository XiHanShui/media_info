import 'node.dart';

/// 标签 = 作者写进文件的元数据（与技术属性分开）。
class Tag {
  const Tag({required this.key, this.value, this.source});

  /// 英文原名，不翻译（如 'TITLE'、'ARTIST'）。
  final String key;

  /// 标签值。
  final Object? value;

  /// 来自哪个块（如 'ilst'、'VORBIS_COMMENT'）。
  final String? source;

  @override
  String toString() => 'Tag($key: $value)';
}

/// 标签的收集结果。
///
/// 各格式的实现（MP4 的 `udta`/`meta`/`ilst`、FLAC 的 Vorbis Comment、
/// MP3 的 ID3v2）在本票之后各自补齐；当前返回空列表。
List<Tag> collectTags(ContainerNode root) => const <Tag>[];
