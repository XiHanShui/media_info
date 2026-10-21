/// 按素材的扩展名把它交给对应格式的解析器。
///
/// 各格式的 quirks（RIFF 的 form type、FLAC 的位域块头、MP3 的帧序列）
/// 都封装在格式模块自己的解析入口里，这里只做「扩展名 → 解析器」的分派，
/// 调用方不需要按格式分支。
library;

import 'package:media_info/src/core/byte_source.dart';
import 'package:media_info/src/core/engine.dart';
import 'package:media_info/src/formats/flac.dart';
import 'package:media_info/src/formats/isobmff.dart';
import 'package:media_info/src/formats/matroska.dart';
import 'package:media_info/src/formats/mp3.dart';
import 'package:media_info/src/formats/riff.dart';

import 'fixture_paths.dart';

/// 解析结构树需要的展开层数。
///
/// MP4 的层级最深：`moov` → `trak` → `mdia` → `minf` → `stbl` → `stsd` 共 6 层；
/// Matroska 是 5 层（`Segment` → `Tracks` → `TrackEntry` → `Video`/`Audio`）。
/// 统一取 8 层，一次覆盖所有格式。
const int kParseDepth = 8;

/// 解析一个素材文件。
///
/// 按扩展名分派：`.wav` / `.aiff` / `.flac` / `.mp3` / `.mp4` / `.mov` /
/// `.mkv` / `.webm`。扩展名不认识时抛 [ArgumentError]。
ParseResult parseFixtureFile(String fileName, {int depth = kParseDepth}) {
  final source = fixtureSource(fileName);
  try {
    return parseFixtureSource(source, fileName, depth: depth);
  } finally {
    source.close();
  }
}

/// 用已经打开的字节源解析素材（[fileName] 只用来决定用哪个解析器）。
ParseResult parseFixtureSource(
  ByteSource source,
  String fileName, {
  int depth = kParseDepth,
}) {
  final extension = fileName.split('.').last.toLowerCase();
  switch (extension) {
    case 'wav':
      return parseWav(source, depth: depth);
    case 'aiff':
      return parseAiff(source, depth: depth);
    case 'flac':
      return parseFlac(source, depth: depth);
    case 'mp3':
      return parseMp3(source, depth: depth);
    case 'mp4':
    case 'mov':
      return parseContainer(isoBmffContainer, source, depth: depth);
    case 'mkv':
    case 'webm':
      return parseContainer(matroskaFormat.container, source, depth: depth);
    default:
      throw ArgumentError('不认识的素材扩展名：$fileName');
  }
}

/// 按格式键与类别解析素材（如 `('mp4', FixtureCategory.normal)`）。
ParseResult parseFixture(
  String format,
  FixtureCategory category, {
  int depth = kParseDepth,
}) => parseFixtureFile(requireFixtureName(format, category), depth: depth);
