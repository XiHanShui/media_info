/// 重新生成 `test/golden/` 下的结构树快照。
///
/// ```powershell
/// dart run tool/gen_golden.dart
/// ```
///
/// 输出是**逐字节稳定**的：键顺序固定、没有时间戳、没有绝对路径，
/// 所以没有解析结果变化时重新跑一遍不会产生任何 git diff。
library;

import 'dart:io';

import '../test/support/golden_tree.dart';

void main(List<String> args) {
  final directory = Directory(goldenRoot);
  directory.createSync(recursive: true);

  for (final target in goldenTargets) {
    final path = goldenPath(target.format);
    final text = buildGoldenText(target);
    File(path).writeAsStringSync(text);
    stdout.writeln('写出 $path（${text.length} 字节）');
  }
}
