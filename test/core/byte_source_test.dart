import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:media_info/src/core/byte_source.dart';
import 'package:media_info/src/core/errors.dart';

void main() {
  group('文件字节源', () {
    late Directory tempDir;
    late File file;
    late FileByteSource source;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('media_info_core_test');
      file = File('${tempDir.path}/sample.bin');
      file.writeAsBytesSync([0, 1, 2, 3, 4, 5, 6, 7]);
      source = FileByteSource(file);
    });

    tearDown(() {
      source.close();
      tempDir.deleteSync(recursive: true);
    });

    test('报告文件长度并按偏移随机读取', () {
      expect(source.length, 8);
      expect(source.read(2, 3), [2, 3, 4]);
      expect(source.read(0, 2), [0, 1]);
      expect(source.read(8, 0), isEmpty);
    });

    test('读越界抛 TruncatedFile 而不是返回垃圾数据', () {
      expect(
        () => source.read(6, 4),
        throwsA(isA<TruncatedFile>().having((e) => e.offset, 'offset', 6)),
      );
    });

    test('可以按路径打开文件', () {
      final other = FileByteSource.fromPath(file.path);
      addTearDown(other.close);

      expect(other.length, 8);
      expect(other.read(7, 1), [7]);
    });
  });
}
