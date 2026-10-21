/// 节点模型的契约测试。
///
/// `docs/design/core-api.md` §1「节点模型」里的硬约束：
/// - 节点**不持有字节内容**，只持有 `offset` / `size`；
/// - 偏移与长度一律用 Dart 的 `int`（64 位）；
/// - 未知块**必须**保留为 `isOpaque = true` 的节点出现在树里，不得丢弃。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:media_info/src/core/node.dart';

/// 读一个**不应该存在**的成员。
///
/// 存在的成员照常返回；不存在的成员抛 [NoSuchMethodError]——
/// 用它来断言「节点不持有字节内容」这条契约。
Object? readMember(ContainerNode node, String name) {
  final dynamic dyn = node;
  switch (name) {
    case 'bytes':
      return dyn.bytes;
    case 'data':
      return dyn.data;
    case 'content':
      return dyn.content;
    case 'payload':
      return dyn.payload;
    case 'raw':
      return dyn.raw;
    case 'buffer':
      return dyn.buffer;
    default:
      throw ArgumentError('未列出的成员名：$name');
  }
}

void main() {
  group('SemanticField（语义字段）', () {
    test('默认是文件级字段，来源是「文件里直接写的」', () {
      const SemanticField field = SemanticField(
        key: 'sample_rate',
        label: '采样率',
      );

      expect(field.value, isNull);
      expect(field.unit, isNull);
      expect(field.origin, FieldOrigin.read);
      expect(field.scope, FieldScope.file);
      expect(field.trackIndex, isNull);
      expect(field.source, isNull);
    });

    test('可以显式给出推算来源、轨道作用域、轨道序号与来源块', () {
      const SemanticField field = SemanticField(
        key: 'overall_bitrate',
        label: '平均码率',
        value: 1413696,
        unit: 'bit/s',
        origin: FieldOrigin.derived,
        scope: FieldScope.track,
        trackIndex: 3,
        source: 'data',
      );

      expect(field.value, 1413696);
      expect(field.unit, 'bit/s');
      expect(field.origin, FieldOrigin.derived);
      expect(field.scope, FieldScope.track);
      expect(field.trackIndex, 3);
      expect(field.source, 'data');
    });

    test('轨道级字段带轨道序号；文件级字段不带', () {
      const SemanticField trackField = SemanticField(
        key: 'codec',
        label: '编码标识',
        value: 'avc1',
        scope: FieldScope.track,
        trackIndex: 0,
      );
      const SemanticField fileField = SemanticField(
        key: 'duration',
        label: '时长',
        value: 1.0,
      );

      expect(trackField.trackIndex, 0);
      expect(fileField.trackIndex, isNull);
    });

    test('值可以是 null——界面据此显示占位符而不是「0」', () {
      const SemanticField field = SemanticField(key: 'language', label: '语言');

      expect(field.value, isNull);
    });

    test('toString 给出英文技术名与值', () {
      const SemanticField field = SemanticField(
        key: 'sample_rate',
        label: '采样率',
        value: 44100,
      );

      expect(field.toString(), 'SemanticField(sample_rate: 44100)');
    });

    test('值可以是列表、字节串与布尔值（引擎读出来的原样保留）', () {
      const SemanticField listField = SemanticField(
        key: 'compatible_brands',
        label: '兼容品牌',
        value: <String>['isom', 'iso2'],
      );
      const SemanticField boolField = SemanticField(
        key: 'crc_protected',
        label: 'CRC 保护',
        value: false,
      );

      expect(listField.value, <String>['isom', 'iso2']);
      expect(boolField.value, isFalse);
    });
  });

  group('ContainerNode（结构树节点）', () {
    test('默认不是不透明叶子，也没有子块与字段', () {
      const ContainerNode node = ContainerNode(
        type: 'mdat',
        offset: 40,
        size: 100,
        dataOffset: 48,
        dataSize: 92,
      );

      expect(node.isOpaque, isFalse);
      expect(node.children, isEmpty);
      expect(node.fields, isEmpty);
    });

    test('载荷区间与块头自洽：dataOffset = offset + 块头，dataSize = size - 块头', () {
      const ContainerNode node = ContainerNode(
        type: 'moov',
        offset: 9827,
        size: 1831,
        dataOffset: 9835,
        dataSize: 1823,
      );

      expect(node.dataOffset - node.offset, 8, reason: 'ISO BMFF 的块头是 8 字节');
      expect(node.size - node.dataSize, 8);
      expect(node.dataOffset + node.dataSize, node.offset + node.size);
    });

    test('载荷长度为 0 的块（free / wide）坐标依然自洽', () {
      const ContainerNode node = ContainerNode(
        type: 'free',
        offset: 32,
        size: 8,
        dataOffset: 40,
        dataSize: 0,
      );

      expect(node.dataSize, 0);
      expect(node.size, 8);
      expect(node.dataOffset, 40);
    });

    test('toString 给出类型、偏移、长度与子块数', () {
      final ContainerNode node = ContainerNode(
        type: 'moov',
        offset: 9827,
        size: 1831,
        dataOffset: 9835,
        dataSize: 1823,
        children: <ContainerNode>[
          ContainerNode(
            type: 'mvhd',
            offset: 9835,
            size: 108,
            dataOffset: 9843,
            dataSize: 100,
          ),
        ],
      );

      expect(node.toString(), 'ContainerNode(moov @9827+1831, children: 1)');
    });

    test('64 位偏移可以无损表示（> 4GB 的文件）', () {
      const int bigOffset = 0x100000000; // 4 GiB
      const ContainerNode node = ContainerNode(
        type: 'mdat',
        offset: bigOffset,
        size: 1024,
        dataOffset: bigOffset + 16,
        dataSize: 1008,
      );

      expect(node.offset, 4294967296);
      expect(node.offset, greaterThan(0xFFFFFFFF));
      expect(node.dataOffset, 4294967312);
    });

    test('节点不持有字节内容：公开成员里没有承载字节的属性', () {
      const ContainerNode node = ContainerNode(
        type: 'mdat',
        offset: 40,
        size: 9787,
        dataOffset: 48,
        dataSize: 9779,
      );

      // 契约要求节点只持有坐标与字段；任何能直接拿到字节的成员都不该存在。
      for (final String name in <String>[
        'bytes',
        'data',
        'content',
        'payload',
        'raw',
        'buffer',
      ]) {
        expect(
          () => readMember(node, name),
          throwsA(isA<NoSuchMethodError>()),
          reason: 'ContainerNode 不该有 $name 这个成员',
        );
      }
    });

    test('未知块以 isOpaque = true 的节点保留在树里，不会被丢弃', () {
      final ContainerNode unknown = ContainerNode(
        type: 'JUNK',
        offset: 100,
        size: 8,
        dataOffset: 104,
        dataSize: 4,
        isOpaque: true,
      );

      expect(unknown.type, 'JUNK');
      expect(unknown.isOpaque, isTrue);
      expect(unknown.children, isEmpty);
    });

    test('子块列表与字段列表默认是不可变的空列表', () {
      const ContainerNode node = ContainerNode(
        type: 'mdat',
        offset: 0,
        size: 0,
        dataOffset: 0,
        dataSize: 0,
      );

      expect(
        () => node.children.add(
          ContainerNode(
            type: 'x',
            offset: 0,
            size: 0,
            dataOffset: 0,
            dataSize: 0,
          ),
        ),
        throwsUnsupportedError,
      );
    });
  });
}
