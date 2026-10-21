import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:media_info/src/core/node.dart';

import '../support/golden_tree.dart';

void main() {
  group('golden 树快照', () {
    test('每个目标格式都有一份快照文件', () {
      expect(goldenTargets, hasLength(8));
      for (final target in goldenTargets) {
        final path = goldenPath(target.format);
        expect(File(path).existsSync(), isTrue, reason: '缺少 $path');
      }
    });

    for (final target in goldenTargets) {
      test('${target.format}：快照与当前解析结果一致', () {
        final path = goldenPath(target.format);
        final expected = File(path).readAsStringSync();
        final actual = buildGoldenText(target);

        expect(
          actual,
          expected,
          reason:
              '$path 与当前解析结果不一致；'
              '确认是预期的变化后重新生成：dart run tool/gen_golden.dart',
        );
      });
    }

    test('重新生成是逐字节稳定的（跑两遍结果一样）', () {
      for (final target in goldenTargets) {
        expect(buildGoldenText(target), buildGoldenText(target));
      }
    });

    test('快照里没有绝对路径，也没有时间戳', () {
      for (final target in goldenTargets) {
        final text = File(goldenPath(target.format)).readAsStringSync();

        // 仓库根目录的绝对路径不能出现（否则换个机器就 diff 不动）。
        expect(text, isNot(contains(':\\')), reason: target.format);
        expect(
          text,
          isNot(contains(Directory.current.path)),
          reason: target.format,
        );
        // 时间戳形态（2024-01-02 / 12:34:56）不能出现。
        expect(
          text,
          isNot(matches(RegExp(r'\d{4}-\d{2}-\d{2}'))),
          reason: target.format,
        );
      }
    });

    test('快照是合法 JSON，含类型 / 偏移 / 长度 / 不透明标记 / 字段 / 子节点', () {
      for (final target in goldenTargets) {
        final text = File(goldenPath(target.format)).readAsStringSync();
        final document = jsonDecode(text) as Map<String, Object?>;

        expect(document['format'], target.format);
        expect(document['fixture'], target.fixture);
        expect(document['generator'], 'tool/gen_golden.dart');
        expect(document['notes'], isA<List<Object?>>());

        final tree = document['tree']! as Map<String, Object?>;
        for (final key in <String>[
          'type',
          'offset',
          'size',
          'isOpaque',
          'fields',
          'children',
        ]) {
          expect(
            tree.containsKey(key),
            isTrue,
            reason: '${target.format}.$key',
          );
        }
      }
    });

    test('字节串渲染成十六进制字符串，不塞原始字节', () {
      // AIFF 的 COMM 里有 10 字节的 80 位扩展精度采样率。
      final document =
          jsonDecode(File(goldenPath('AIFF')).readAsStringSync())
              as Map<String, Object?>;
      final tree = document['tree']! as Map<String, Object?>;
      final form =
          (tree['children']! as List<Object?>).first as Map<String, Object?>;
      final comm =
          (form['children']! as List<Object?>).first as Map<String, Object?>;
      final rate =
          (comm['fields']! as List<Object?>).firstWhere(
                (f) => (f! as Map<String, Object?>)['key'] == 'sample_rate',
              )
              as Map<String, Object?>;

      expect(rate['value'], 'hex:400EBB80000000000000');
    });

    test('MP3 的快照是帧列表：每个帧一个节点', () {
      final document =
          jsonDecode(File(goldenPath('MP3')).readAsStringSync())
              as Map<String, Object?>;
      final tree = document['tree']! as Map<String, Object?>;
      final children = tree['children']! as List<Object?>;

      final frames = children
          .where(
            (c) => (c! as Map<String, Object?>)['type'] == 'MPEG Audio Frame',
          )
          .length;
      expect(frames, 12);
      // 帧列表没触发节点上限，notes 里写明了这一点。
      final notes = (document['notes']! as List<Object?>).cast<String>();
      expect(notes.any((n) => n.contains('帧列表')), isTrue);
    });
  });

  group('节点上限', () {
    test('子节点超过上限时截断，并记下总数', () {
      final node = _FakeNode(<ContainerNode>[
        for (var i = 0; i < 5; i++) _child('x$i'),
      ]);

      final json = nodeToJson(node, maxChildren: 3);
      expect((json['children']! as List<Object?>), hasLength(3));
      expect(json['childrenTotal'], 5);
      expect(json['childrenTruncated'], isTrue);
    });

    test('没超上限时不加截断标记', () {
      final node = _FakeNode(<ContainerNode>[_child('x')]);

      final json = nodeToJson(node, maxChildren: 3);
      expect(json.containsKey('childrenTotal'), isFalse);
      expect(json.containsKey('childrenTruncated'), isFalse);
    });
  });
}

/// 一个只有子节点的假节点（用来测节点上限，不依赖真实素材）。
class _FakeNode extends ContainerNode {
  _FakeNode(List<ContainerNode> children)
    : super(
        type: 'fake',
        offset: 0,
        size: 0,
        dataOffset: 0,
        dataSize: 0,
        children: children,
      );
}

/// 造一个只有类型的子节点。
ContainerNode _child(String type) =>
    ContainerNode(type: type, offset: 0, size: 0, dataOffset: 0, dataSize: 0);
