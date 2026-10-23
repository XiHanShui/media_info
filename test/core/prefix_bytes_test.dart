import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:media_info/src/core/engine.dart';
import 'package:media_info/src/core/node.dart';
import 'package:media_info/src/core/registry.dart';
import 'package:media_info/src/core/spec.dart';

import 'support/byte_fixtures.dart';
import 'support/memory_byte_source.dart';

/// 'RIFF' + size(12) + 'WAVE' + 'fmt ' + size(0)
///
/// 这就是 RIFF/AIFF 的形状：容器载荷开头是 4 字节 form type，后面才是子块。
/// RIFF 的 size 是载荷长度（不含 8 字节块头）：'WAVE'(4) + 'fmt '(4) + size(4) = 12。
List<int> riffLikeBytes() => concat([
  ascii('RIFF'),
  u32le(12),
  ascii('WAVE'),
  ascii('fmt '),
  u32le(0),
]);

ContainerSpec _riffLike({required bool withPrefix}) {
  // 载荷开头是 4 字节 form type（'WAVE'），后面才是子块。
  final inner = ContainerSpec(
    name: 'Chunks',
    header: HeaderRule(
      typeBytes: 4,
      sizeBytes: 4,
      sizeIncludesHeader: false,
      endian: Endian.little,
      prefixBytes: withPrefix ? 4 : 0,
    ),
    children: {
      'fmt ': const ChildSpec(type: 'fmt '),
    },
  );
  // 顶层：文件里第一个块是 'RIFF'，它是个容器。
  return ContainerSpec(
    name: 'RiffLike',
    header: const HeaderRule(
      typeBytes: 4,
      sizeBytes: 4,
      sizeIncludesHeader: false,
      endian: Endian.little,
    ),
    children: {
      'RIFF': ChildSpec(type: 'RIFF', container: inner),
    },
  );
}

void main() {
  group('HeaderRule.prefixBytes', () {
    test('skips the form type before reading children', () {
      final source = MemoryByteSource.of(riffLikeBytes());

      final result = parseContainer(_riffLike(withPrefix: true), source, depth: 2);

      // 结构是 root -> RIFF -> fmt '；form type 不能被当成子块。
      final riff = result.root.children.single;
      expect(riff.type, 'RIFF');
      expect(riff.children.map((c) => c.type).toList(), ['fmt ']);
      expect(riff.children.single.offset, 12);
      expect(result.truncated, isFalse);
    });

    test('without prefixBytes the form type is misread as a chunk', () {
      final source = MemoryByteSource.of(riffLikeBytes());

      final result = parseContainer(_riffLike(withPrefix: false), source, depth: 2);

      // 'WAVE' 被当成块头读出，它的长度字段落在 'fmt ' 上 —— 正是 prefixBytes 要修的坑。
      final riff = result.root.children.single;
      expect(riff.type, 'RIFF');
      expect(riff.children.map((c) => c.type).toList(), ['WAVE']);
    });
  });

  group('parseFormat', () {
    test('uses the custom parser when the format provides one', () {
      final calls = <int>[];
      final spec = FormatSpec(
        name: 'Custom',
        container: ContainerSpec(
          name: 'Custom',
          header: const HeaderRule(),
          children: const {},
        ),
        parser: (source, {depth = 1}) {
          calls.add(depth);
          return ParseResult(
            root: ContainerNode(
              type: 'Custom',
              offset: 0,
              size: source.length,
              dataOffset: 0,
              dataSize: source.length,
            ),
          );
        },
      );

      final result = parseFormat(spec, MemoryByteSource.of([0, 0, 0, 0]), depth: 7);

      expect(calls, [7]);
      expect(result.root.type, 'Custom');
    });

    test('falls back to the container spec when there is no custom parser', () {
      final spec = FormatSpec(
        name: 'Plain',
        container: ContainerSpec(
          name: 'Plain',
          header: const HeaderRule(),
          children: const {},
        ),
      );

      final result = parseFormat(spec, MemoryByteSource.of([0, 0, 0, 0]), depth: 2);

      expect(result.root.type, 'Plain');
      expect(result.root.size, 4);
    });
  });
}
