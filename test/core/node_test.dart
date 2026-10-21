import 'package:flutter_test/flutter_test.dart';
import 'package:media_info/src/core/node.dart';
import 'package:media_info/src/core/tag.dart';

void main() {
  group('节点模型', () {
    test('语义字段的默认值：来源 read、作用域 file', () {
      const field = SemanticField(key: 'sample_rate', label: '采样率');

      expect(field.key, 'sample_rate');
      expect(field.label, '采样率');
      expect(field.value, isNull);
      expect(field.unit, isNull);
      expect(field.origin, FieldOrigin.read);
      expect(field.scope, FieldScope.file);
      expect(field.trackIndex, isNull);
      expect(field.source, isNull);
    });

    test('结构树节点默认不透明、不带子块与字段', () {
      const node = ContainerNode(
        type: 'moov',
        offset: 0,
        size: 32,
        dataOffset: 8,
        dataSize: 24,
      );

      expect(node.type, 'moov');
      expect(node.offset, 0);
      expect(node.size, 32);
      expect(node.dataOffset, 8);
      expect(node.dataSize, 24);
      expect(node.isOpaque, isFalse);
      expect(node.children, isEmpty);
      expect(node.fields, isEmpty);
    });
  });

  group('标签骨架', () {
    test('collectTags 目前返回空列表', () {
      const node = ContainerNode(
        type: 'moov',
        offset: 0,
        size: 8,
        dataOffset: 8,
        dataSize: 0,
      );

      expect(collectTags(node), isEmpty);
    });

    test('标签保留英文原名与来源', () {
      const tag = Tag(key: 'TITLE', value: '标题', source: 'ilst');

      expect(tag.key, 'TITLE');
      expect(tag.value, '标题');
      expect(tag.source, 'ilst');
    });
  });
}
