import 'package:flutter_test/flutter_test.dart';
import 'package:media_info/src/core/engine.dart';
import 'package:media_info/src/core/node.dart';

import '../support/fixture_paths.dart';
import '../support/format_parsers.dart';

/// 遍历结构树，收集所有节点。
List<ContainerNode> walk(ContainerNode node) => <ContainerNode>[
  node,
  for (final child in node.children) ...walk(child),
];

void main() {
  group('截断与长度撒谎的素材', () {
    final damaged = <String>[
      for (final name in listFixtureNames())
        if (parseFixtureName(name).category == FixtureCategory.truncated ||
            parseFixtureName(name).category == FixtureCategory.liesize)
          name,
    ];

    test('素材目录里确实有截断与撒谎的样本', () {
      expect(damaged, hasLength(9));
      expect(
        damaged.where(
          (n) => parseFixtureName(n).category == FixtureCategory.liesize,
        ),
        hasLength(1),
      );
    });

    for (final name in damaged) {
      test('$name：解析不抛异常，报截断，返回部分结构', () {
        ParseResult? result;
        expect(() => result = parseFixtureFile(name), returnsNormally);

        final parsed = result!;
        // 截断必须被标记出来。
        expect(parsed.truncated, isTrue, reason: name);
        // 错误说明是引擎给的中文文案。
        expect(parsed.error, isNotNull, reason: name);
        expect(parsed.error, contains('截断'), reason: name);
        expect(parsed.error, contains('偏移'), reason: name);
        // 已解析的部分照常返回：不是一棵空树。
        expect(parsed.root.children, isNotEmpty, reason: name);
      });

      test('$name：结构树不越界', () {
        final length = fixtureFile(name).lengthSync();
        final result = parseFixtureFile(name);

        for (final node in walk(result.root)) {
          expect(node.offset, greaterThanOrEqualTo(0), reason: name);
          expect(
            node.offset + node.size,
            lessThanOrEqualTo(length),
            reason: '$name 里 ${node.type} 越界',
          );
          expect(
            node.dataOffset + node.dataSize,
            lessThanOrEqualTo(length),
            reason: '$name 里 ${node.type} 的载荷越界',
          );
        }
      });
    }

    test('撒谎的 WAV：声明长度超出文件，报截断而不是越界', () {
      const name = 'wav_pcm_s16le_44100_stereo.normal.liesize.wav';
      final length = fixtureFile(name).lengthSync();
      final result = parseFixtureFile(name);

      expect(result.truncated, isTrue);
      expect(result.error, contains('截断'));
      // 文件本身完好无损，坏的是块头里声明的长度。
      expect(length, 44178);
      final data = walk(result.root).firstWhere((n) => n.type == 'data');
      expect(data.dataOffset + data.dataSize, lessThanOrEqualTo(length));
    });

    test('截断的 MP3：最后一帧留在树里并标记不透明', () {
      const name = 'mp3_cbr128_44100_stereo.normal.truncated.mp3';
      final result = parseFixtureFile(name);

      expect(result.truncated, isTrue);
      final frames = result.root.children
          .where((n) => n.type == 'MPEG Audio Frame')
          .toList();
      expect(frames, isNotEmpty);
      expect(frames.last.isOpaque, isTrue);
    });
  });
}
