// 把 Matroska 官方 EBML Schema（ebml_matroska.xml）转成 Dart 表
// `lib/src/formats/matroska_schema.dart`。
//
// 用法：
//   dart run tool/convert_ebml_schema.dart              # 用仓库内的快照 tool/ebml_matroska.xml
//   dart run tool/convert_ebml_schema.dart --fetch      # 从官方地址重新下载后再生成
//   dart run tool/convert_ebml_schema.dart --source <xml> --out <dart>
//
// 脚本是幂等的：同样的输入永远产出同样的输出（元素按 path 排序，字段顺序固定）。
// 生成后会调用 `dart format` 规范化输出，保证与仓库里的文件逐字节一致。
//
// 真相源：https://github.com/ietf-wg-cellar/matroska-specification
//         （RFC 9559 的机器可读 EBML Schema，262 个元素 / 49 个 master 元素）

import 'dart:convert';
import 'dart:io';

/// 官方 EBML Schema 的地址。
const String kSchemaUrl =
    'https://raw.githubusercontent.com/ietf-wg-cellar/matroska-specification/master/ebml_matroska.xml';

/// 仓库内的快照路径（离线也能重跑）。
const String kDefaultSource = 'tool/ebml_matroska.xml';

/// 生成文件的默认路径。
const String kDefaultOutput = 'lib/src/formats/matroska_schema.dart';

/// EBML 头（RFC 8794 §11.2）的元素。
///
/// `ebml_matroska.xml` 只声明了 EBML 头里的 `EBMLMaxIDLength` /
/// `EBMLMaxSizeLength` 两个元素，头本身以及其余头元素来自 RFC 8794，
/// 这里补齐，好让整棵树都有 schema 条目。
const List<_Element> _ebmlHeaderSupplement = <_Element>[
  _Element(
    name: 'EBML',
    id: '0x1A45DFA3',
    path: r'\EBML',
    type: 'master',
    minOccurs: '1',
    maxOccurs: '1',
  ),
  _Element(
    name: 'EBMLVersion',
    id: '0x4286',
    path: r'\EBML\EBMLVersion',
    type: 'uinteger',
    range: '1',
    defaultValue: '1',
    minOccurs: '1',
    maxOccurs: '1',
  ),
  _Element(
    name: 'EBMLReadVersion',
    id: '0x42F7',
    path: r'\EBML\EBMLReadVersion',
    type: 'uinteger',
    range: '1',
    defaultValue: '1',
    minOccurs: '1',
    maxOccurs: '1',
  ),
  _Element(
    name: 'DocType',
    id: '0x4282',
    path: r'\EBML\DocType',
    type: 'string',
    minOccurs: '1',
    maxOccurs: '1',
  ),
  _Element(
    name: 'DocTypeVersion',
    id: '0x4287',
    path: r'\EBML\DocTypeVersion',
    type: 'uinteger',
    minOccurs: '1',
    maxOccurs: '1',
  ),
  _Element(
    name: 'DocTypeReadVersion',
    id: '0x4285',
    path: r'\EBML\DocTypeReadVersion',
    type: 'uinteger',
    minOccurs: '1',
    maxOccurs: '1',
  ),
  // 全局元素：可以出现在任何 master 元素里。
  _Element(
    name: 'Void',
    id: '0xEC',
    path: r'\Void',
    type: 'binary',
    isGlobal: true,
  ),
  _Element(
    name: 'CRC-32',
    id: '0xBF',
    path: r'\CRC-32',
    type: 'binary',
    isGlobal: true,
  ),
];

Future<void> main(List<String> args) async {
  final options = _Options.parse(args);
  if (options.help) {
    stdout.writeln(_usage);
    return;
  }

  final String xml;
  if (options.source != null) {
    final file = File(options.source!);
    if (!file.existsSync()) {
      stderr.writeln('找不到 XML 文件：${file.path}');
      exitCode = 1;
      return;
    }
    xml = file.readAsStringSync();
  } else if (options.fetch || !File(kDefaultSource).existsSync()) {
    stdout.writeln('正在下载 $kSchemaUrl …');
    xml = await _download(kSchemaUrl);
    if (options.fetch) {
      final snapshot = File(kDefaultSource);
      snapshot.parent.createSync(recursive: true);
      snapshot.writeAsStringSync(xml);
      stdout.writeln('已保存快照：${snapshot.path}');
    }
  } else {
    xml = File(kDefaultSource).readAsStringSync();
  }

  final elements = _parseElements(xml);
  final merged = _merge(elements);
  final dart = _render(merged, source: _sourceName(options), xml: xml);

  final out = File(options.out);
  out.parent.createSync(recursive: true);
  out.writeAsStringSync(dart);
  stdout.writeln(
    '已生成 ${out.path}：${merged.length} 个元素'
    '（master ${merged.where((e) => e.type == 'master').length} 个，'
    'WebM ${merged.where((e) => e.isWebm).length} 个）',
  );

  _format(out.path);
}

const String _usage = '''
用法：dart run tool/convert_ebml_schema.dart [选项]

  --source <path>   用本地 XML 作为输入（默认 tool/ebml_matroska.xml）
  --fetch           先从官方地址下载并刷新本地快照
  --out <path>      输出文件（默认 lib/src/formats/matroska_schema.dart）
  --help            显示本帮助
''';

class _Options {
  _Options({
    this.source,
    this.out = kDefaultOutput,
    this.fetch = false,
    this.help = false,
  });

  final String? source;
  final String out;
  final bool fetch;
  final bool help;

  static _Options parse(List<String> args) {
    String? source;
    var out = kDefaultOutput;
    var fetch = false;
    var help = false;
    for (var i = 0; i < args.length; i++) {
      final arg = args[i];
      switch (arg) {
        case '--source':
          source = args[++i];
        case '--out':
          out = args[++i];
        case '--fetch':
          fetch = true;
        case '--help':
        case '-h':
          help = true;
        default:
          stderr.writeln('未知参数：$arg');
          help = true;
      }
    }
    return _Options(source: source, out: out, fetch: fetch, help: help);
  }
}

/// 脚本内部用的元素记录（还没转成 Dart 字面量）。
class _Element {
  const _Element({
    required this.name,
    required this.id,
    required this.path,
    required this.type,
    this.length,
    this.range,
    this.defaultValue,
    this.minOccurs,
    this.maxOccurs,
    this.minver,
    this.maxver,
    this.unknownSizeAllowed = false,
    this.recurring = false,
    this.recursive = false,
    this.isWebm = false,
    this.isGlobal = false,
  });

  final String name;
  final String id;
  final String path;
  final String type;
  final String? length;
  final String? range;
  final String? defaultValue;
  final String? minOccurs;
  final String? maxOccurs;
  final String? minver;
  final String? maxver;
  final bool unknownSizeAllowed;
  final bool recurring;
  final bool recursive;
  final bool isWebm;
  final bool isGlobal;
}

/// 解析 `ebml_matroska.xml`，取出全部 `<element>` 条目。
List<_Element> _parseElements(String xml) {
  final out = <_Element>[];
  final openRe = RegExp(r'<element\b([^>]*?)(/?)>', dotAll: true);
  for (final match in openRe.allMatches(xml)) {
    final attrs = _parseAttributes(match.group(1)!);
    final String block;
    if (match.group(2) == '/') {
      block = match.group(0)!;
    } else {
      final close = xml.indexOf('</element>', match.end);
      if (close < 0) continue;
      block = xml.substring(match.start, close + '</element>'.length);
    }
    out.add(
      _Element(
        name: attrs['name'] ?? '',
        id: _normalizeId(attrs['id'] ?? ''),
        path: attrs['path'] ?? '',
        type: attrs['type'] ?? 'binary',
        length: attrs['length'],
        range: attrs['range'],
        defaultValue: attrs['default'],
        minOccurs: attrs['minOccurs'],
        maxOccurs: attrs['maxOccurs'],
        minver: attrs['minver'],
        maxver: attrs['maxver'],
        unknownSizeAllowed: attrs['unknownsizeallowed'] == '1',
        recurring: attrs['recurring'] == '1',
        recursive: attrs['recursive'] == '1',
        isWebm: block.contains('webmproject.org'),
      ),
    );
  }
  return out;
}

/// 解析标签属性。
Map<String, String> _parseAttributes(String text) {
  final out = <String, String>{};
  final re = RegExp(r'([A-Za-z][A-Za-z0-9:]*)\s*=\s*"([^"]*)"');
  for (final m in re.allMatches(text)) {
    out[m.group(1)!] = m.group(2)!;
  }
  return out;
}

/// 元素 ID 统一成 `0x` + 大写偶数位十六进制（与核心引擎的节点 type 一致）。
String _normalizeId(String id) {
  final raw = id.startsWith('0x') || id.startsWith('0X') ? id.substring(2) : id;
  final value = int.tryParse(raw, radix: 16);
  if (value == null) return id.toUpperCase();
  var hex = value.toRadixString(16).toUpperCase();
  if (hex.length.isOdd) hex = '0$hex';
  return '0x$hex';
}

/// 把 RFC 8794 的 EBML 头元素补进表里（同名以官方 XML 为准）。
List<_Element> _merge(List<_Element> fromXml) {
  final byName = <String, _Element>{for (final e in fromXml) e.name: e};
  final out = List<_Element>.of(fromXml);
  for (final extra in _ebmlHeaderSupplement) {
    if (byName.containsKey(extra.name)) continue;
    out.add(extra);
  }
  return out;
}

/// 渲染成 Dart 源码。
String _render(
  List<_Element> elements, {
  required String source,
  required String xml,
}) {
  final sorted = List<_Element>.of(elements)
    ..sort((a, b) {
      final byPath = a.path.compareTo(b.path);
      return byPath != 0 ? byPath : a.id.compareTo(b.id);
    });

  final buffer = StringBuffer();
  buffer.writeln('// GENERATED FILE —— 请勿手工编辑。');
  buffer.writeln('//');
  buffer.writeln('// 由 `dart run tool/convert_ebml_schema.dart` 生成。');
  buffer.writeln('//');
  buffer.writeln('// 真相源：$kSchemaUrl');
  buffer.writeln('// 本地输入：$source');
  final fingerprint = _fnv1a64(xml).toRadixString(16).padLeft(16, '0');
  buffer.writeln('// 源文件校验（FNV-1a 64 位）：0x$fingerprint');
  buffer.writeln('//');
  buffer.writeln('// Matroska 官方 schema 的 262 个元素 + RFC 8794 的 EBML 头元素。');
  buffer.writeln();
  buffer.writeln('/// EBML 元素的数据类型（RFC 8794 §7）。');
  buffer.writeln('enum EbmlElementType {');
  buffer.writeln('  /// master 元素（含子元素）。');
  buffer.writeln('  master,');
  buffer.writeln();
  buffer.writeln('  /// 无符号整数（1–8 字节，最短编码）。');
  buffer.writeln('  uinteger,');
  buffer.writeln();
  buffer.writeln('  /// 有符号整数（1–8 字节，最短编码）。');
  buffer.writeln('  integer,');
  buffer.writeln();
  buffer.writeln('  /// 浮点数（4 或 8 字节 IEEE 754）。');
  buffer.writeln('  float,');
  buffer.writeln();
  buffer.writeln('  /// ASCII 字符串（尾部 NUL 补齐）。');
  buffer.writeln('  string,');
  buffer.writeln();
  buffer.writeln('  /// UTF-8 字符串。');
  buffer.writeln('  utf8,');
  buffer.writeln();
  buffer.writeln('  /// 日期（自 2001-01-01 起的纳秒数，8 字节）。');
  buffer.writeln('  date,');
  buffer.writeln();
  buffer.writeln('  /// 原始二进制。');
  buffer.writeln('  binary,');
  buffer.writeln('}');
  buffer.writeln();
  buffer.writeln('/// EBML Schema 里的一个元素（RFC 8794 §11.1）。');
  buffer.writeln('class EbmlElement {');
  buffer.writeln('  const EbmlElement({');
  buffer.writeln('    required this.name,');
  buffer.writeln('    required this.id,');
  buffer.writeln('    required this.path,');
  buffer.writeln('    required this.type,');
  buffer.writeln('    this.length,');
  buffer.writeln('    this.range,');
  buffer.writeln('    this.defaultValue,');
  buffer.writeln('    this.minOccurs,');
  buffer.writeln('    this.maxOccurs,');
  buffer.writeln('    this.minver,');
  buffer.writeln('    this.maxver,');
  buffer.writeln('    this.unknownSizeAllowed = false,');
  buffer.writeln('    this.recurring = false,');
  buffer.writeln('    this.recursive = false,');
  buffer.writeln('    this.webm = false,');
  buffer.writeln('    this.global = false,');
  buffer.writeln('  });');
  buffer.writeln();
  buffer.writeln('  /// 元素名，如 \'Segment\'。');
  buffer.writeln('  final String name;');
  buffer.writeln();
  buffer.writeln('  /// 元素 ID 的十六进制文本，如 \'0x18538067\'。');
  buffer.writeln('  ///');
  buffer.writeln('  /// 核心引擎用 VINT 读出元素 ID，节点 type 就是这个十六进制文本。');
  buffer.writeln('  final String id;');
  buffer.writeln();
  buffer.writeln('  /// 元素的完整路径，如 `r\'\\Segment\\Info\'`。');
  buffer.writeln('  final String path;');
  buffer.writeln();
  buffer.writeln('  /// 数据类型。');
  buffer.writeln('  final EbmlElementType type;');
  buffer.writeln();
  buffer.writeln('  /// 定长载荷的字节数（可选）。');
  buffer.writeln('  final int? length;');
  buffer.writeln();
  buffer.writeln('  /// 取值范围（schema 原文）。');
  buffer.writeln('  final String? range;');
  buffer.writeln();
  buffer.writeln('  /// 默认值（schema 原文）。');
  buffer.writeln('  final String? defaultValue;');
  buffer.writeln();
  buffer.writeln('  /// 最小出现次数。');
  buffer.writeln('  final int? minOccurs;');
  buffer.writeln();
  buffer.writeln('  /// 最大出现次数。');
  buffer.writeln('  final int? maxOccurs;');
  buffer.writeln();
  buffer.writeln('  /// 引入该元素的 schema 版本。');
  buffer.writeln('  final int? minver;');
  buffer.writeln();
  buffer.writeln('  /// 该元素被移除的 schema 版本。');
  buffer.writeln('  final int? maxver;');
  buffer.writeln();
  buffer.writeln('  /// 允许"未知长度"（RFC 8794 §6.2）：收尾靠路径判定，不靠声明长度。');
  buffer.writeln('  final bool unknownSizeAllowed;');
  buffer.writeln();
  buffer.writeln('  /// 同一父元素下可以出现多次。');
  buffer.writeln('  final bool recurring;');
  buffer.writeln();
  buffer.writeln('  /// 可以递归包含自己。');
  buffer.writeln('  final bool recursive;');
  buffer.writeln();
  buffer.writeln(
    '  /// 属于 WebM 子集（schema 里的 `<extension type="webmproject.org" webm="1"/>`）。',
  );
  buffer.writeln('  final bool webm;');
  buffer.writeln();
  buffer.writeln('  /// 全局元素（Void / CRC-32），可以出现在任何 master 元素里。');
  buffer.writeln('  final bool global;');
  buffer.writeln();
  buffer.writeln('  /// 是否 master 元素。');
  buffer.writeln('  bool get isMaster => type == EbmlElementType.master;');
  buffer.writeln('}');
  buffer.writeln();
  buffer.writeln('/// Matroska / WebM 的 EBML Schema 全表。');
  buffer.writeln(
    'const List<EbmlElement> matroskaSchemaElements = <EbmlElement>[',
  );
  for (final e in sorted) {
    buffer.writeln('  EbmlElement(');
    buffer.writeln("    name: '${_escape(e.name)}',");
    buffer.writeln("    id: '${_escape(e.id)}',");
    buffer.writeln("    path: r'${_escapeRaw(e.path)}',");
    buffer.writeln('    type: EbmlElementType.${_dartType(e.type)},');
    if (e.length != null) buffer.writeln('    length: ${e.length},');
    if (e.range != null) buffer.writeln("    range: '${_escape(e.range!)}',");
    if (e.defaultValue != null) {
      buffer.writeln("    defaultValue: '${_escape(e.defaultValue!)}',");
    }
    if (e.minOccurs != null) buffer.writeln('    minOccurs: ${e.minOccurs},');
    if (e.maxOccurs != null) buffer.writeln('    maxOccurs: ${e.maxOccurs},');
    if (e.minver != null) buffer.writeln('    minver: ${e.minver},');
    if (e.maxver != null) buffer.writeln('    maxver: ${e.maxver},');
    if (e.unknownSizeAllowed) buffer.writeln('    unknownSizeAllowed: true,');
    if (e.recurring) buffer.writeln('    recurring: true,');
    if (e.recursive) buffer.writeln('    recursive: true,');
    if (e.isWebm) buffer.writeln('    webm: true,');
    if (e.isGlobal) buffer.writeln('    global: true,');
    buffer.writeln('  ),');
  }
  buffer.writeln('];');
  buffer.writeln();
  return buffer.toString();
}

String _dartType(String xmlType) => switch (xmlType) {
  'master' => 'master',
  'uinteger' => 'uinteger',
  'integer' => 'integer',
  'float' => 'float',
  'string' => 'string',
  'utf-8' => 'utf8',
  'date' => 'date',
  _ => 'binary',
};

String _escape(String value) => value
    .replaceAll(r'\', r'\\')
    .replaceAll("'", r"\'")
    .replaceAll(r'$', r'\$');

/// raw string（r'…'）里只有 `'` 与 `$` 需要转义，反斜杠保持原样。
String _escapeRaw(String value) =>
    value.replaceAll("'", r"\'").replaceAll(r'$', r'\$');

String _sourceName(_Options options) =>
    options.source ?? (options.fetch ? kSchemaUrl : kDefaultSource);

/// FNV-1a 64 位哈希（只为给生成文件留一个可对照的源文件指纹）。
int _fnv1a64(String text) {
  const int offsetBasis = 0xcbf29ce484222325;
  const int prime = 0x100000001b3;
  var hash = offsetBasis;
  for (final byte in utf8.encode(text)) {
    hash ^= byte;
    hash = (hash * prime) & 0xFFFFFFFFFFFFFFFF;
  }
  return hash & 0x7FFFFFFFFFFFFFFF;
}

/// 下载 XML。
Future<String> _download(String url) async {
  final client = HttpClient();
  try {
    final request = await client.getUrl(Uri.parse(url));
    final response = await request.close();
    if (response.statusCode != 200) {
      throw HttpException('HTTP ${response.statusCode}', uri: Uri.parse(url));
    }
    return await response.transform(utf8.decoder).join();
  } finally {
    client.close();
  }
}

/// 跑一次 `dart format`，保证生成结果与仓库里的文件逐字节一致。
void _format(String path) {
  final executable = Platform.resolvedExecutable;
  final result = Process.runSync(executable, <String>['format', path]);
  if (result.exitCode != 0) {
    stderr.writeln('警告：dart format 失败（${result.stderr}）');
  }
}
