/// 扩展名与实际格式的一致性检查（纯函数，无 UI 依赖，便于单测）。
///
/// 判定只信内容：格式由 `detectFormat` 按文件头嗅探得出，扩展名不参与判定。
/// 这里只回答"扩展名写的和实际内容对不对得上"。
library;

/// 已知媒体扩展名 → 与之相符的格式名集合。
///
/// 只列**已知媒体**扩展名：不在表里的扩展名（`.bin` / `.txt` / 没有扩展名）
/// 一律不提示——扩展名缺失或未知**不算**不一致。
const Map<String, Set<String>> _knownMediaExtensions = <String, Set<String>>{
  'wav': <String>{'WAV'},
  'wave': <String>{'WAV'},
  'aiff': <String>{'AIFF'},
  'aif': <String>{'AIFF'},
  'aifc': <String>{'AIFF'},
  'flac': <String>{'FLAC'},
  'mp3': <String>{'MP3'},
  'mp4': <String>{'MP4'},
  'm4v': <String>{'MP4'},
  'm4a': <String>{'MP4'},
  'mov': <String>{'MP4'},
  'qt': <String>{'MP4'},
  '3gp': <String>{'MP4'},
  '3g2': <String>{'MP4'},
  // WebM 是 Matroska 的子集，共用同一张 EBML 表，所以两者互认。
  'mkv': <String>{'Matroska'},
  'webm': <String>{'Matroska', 'WebM'},
  'mka': <String>{'Matroska'},
  'mks': <String>{'Matroska'},
};

/// 扩展名与实际格式不一致时的提示文案；一致或无法判断时返回 `null`。
///
/// - 扩展名缺失、不是已知媒体扩展名 → `null`（不提示）；
/// - 扩展名与检测到的格式不符 → 中文提示，例如
///   「扩展名 `.wav` 与实际格式 `MP4` 不符」；
/// - [detectedFormat] 为 `null`（无法识别）→ `null`
///   （由"无法识别的文件格式"状态负责）。
///
/// 这是**提示不是报错**：解析照实际内容走。
String? checkExtension(String path, String? detectedFormat) {
  if (detectedFormat == null) return null;

  final extension = _extensionOf(path);
  if (extension == null) return null;

  final expected = _knownMediaExtensions[extension];
  if (expected == null) return null;
  if (expected.contains(detectedFormat)) return null;

  return '扩展名 `.$extension` 与实际格式 `$detectedFormat` 不符';
}

/// 取路径的小写扩展名（不含点）；没有扩展名时返回 `null`。
String? _extensionOf(String path) {
  final name = path.replaceAll('\\', '/');
  final slash = name.lastIndexOf('/');
  final fileName = slash < 0 ? name : name.substring(slash + 1);
  final dot = fileName.lastIndexOf('.');
  // dot <= 0：没有点，或者点开头（隐藏文件，没有真正的名字）。
  // dot == 末尾：点后面什么都没有（`take1.`）。
  if (dot <= 0 || dot == fileName.length - 1) return null;
  return fileName.substring(dot + 1).toLowerCase();
}
