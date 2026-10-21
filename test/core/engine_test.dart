import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:media_info/src/core/engine.dart';
import 'package:media_info/src/core/node.dart';
import 'package:media_info/src/core/spec.dart';

import 'support/byte_fixtures.dart';
import 'support/memory_byte_source.dart';

/// 深度优先遍历结构树，返回 (节点, 层级)。
List<(ContainerNode, int)> walk(ContainerNode node, [int level = 0]) {
  final out = <(ContainerNode, int)>[(node, level)];
  for (final child in node.children) {
    out.addAll(walk(child, level + 1));
  }
  return out;
}

void main() {
  group('通用容器引擎', () {
    test('解析出第一层子块并读出大端定长整数', () {
      final spec = ContainerSpec(
        name: 'T',
        header: HeaderRule(),
        children: {
          'data': ChildSpec(
            type: 'data',
            fields: [FieldSpec('value', type: FieldType.uint32)],
          ),
        },
      );
      final source = MemoryByteSource.of(
        concat([ascii('data'), u32be(12), u32be(0x01020304)]),
      );

      final result = parseContainer(spec, source);

      expect(result.truncated, isFalse);
      expect(result.error, isNull);
      expect(result.root.type, 'T');
      expect(result.root.children, hasLength(1));

      final child = result.root.children.single;
      expect(child.type, 'data');
      expect(child.offset, 0);
      expect(child.size, 12);
      expect(child.dataOffset, 8);
      expect(child.dataSize, 4);
      expect(child.isOpaque, isFalse);
      expect(child.fields.single.key, 'value');
      expect(child.fields.single.value, 0x01020304);
      expect(child.fields.single.source, 'data');
    });

    test('读出小端整数、fourcc、长度前缀字节串与计数前缀数组', () {
      final spec = ContainerSpec(
        name: 'T',
        header: HeaderRule(),
        children: {
          'meta': ChildSpec(
            type: 'meta',
            fields: [
              FieldSpec('tag', type: FieldType.fourcc),
              FieldSpec('len', type: FieldType.uint16, endian: Endian.little),
              FieldSpec('name', type: FieldType.bytes, lengthFrom: 'len'),
              FieldSpec('count', type: FieldType.uint8),
              FieldSpec(
                'item',
                type: FieldType.uint16,
                endian: Endian.little,
                countFrom: 'count',
              ),
            ],
          ),
        },
      );
      final payload = concat([
        ascii('fmt '),
        u16le(3),
        ascii('abc'),
        u8(2),
        u16le(0x1111),
        u16le(0x2222),
      ]);
      final source = MemoryByteSource.of(
        concat([ascii('meta'), u32be(8 + payload.length), payload]),
      );

      final result = parseContainer(spec, source);

      expect(result.truncated, isFalse);
      final fields = {
        for (final field in result.root.children.single.fields)
          field.key: field.value,
      };
      expect(fields['tag'], 'fmt ');
      expect(fields['len'], 3);
      expect(fields['name'], Uint8List.fromList(ascii('abc')));
      expect(fields['count'], 2);
      expect(fields['item'], [0x1111, 0x2222]);
    });

    test('读出位域与单 bit 布尔值', () {
      final spec = ContainerSpec(
        name: 'T',
        header: HeaderRule(),
        children: {
          'bits': ChildSpec(
            type: 'bits',
            fields: [
              FieldSpec('flags', type: FieldType.bits, bitWidth: 3),
              FieldSpec('ratio', type: FieldType.bits, bitWidth: 5),
              FieldSpec('has_audio', type: FieldType.boolean),
            ],
          ),
        },
      );
      // 101 00110 1 → flags=5, ratio=6, has_audio=true
      final source = MemoryByteSource.of(
        concat([
          ascii('bits'),
          u32be(10),
          [0xA6, 0x80],
        ]),
      );

      final result = parseContainer(spec, source);

      final fields = {
        for (final field in result.root.children.single.fields)
          field.key: field.value,
      };
      expect(fields['flags'], 5);
      expect(fields['ratio'], 6);
      expect(fields['has_audio'], isTrue);
    });

    test('读出定长字节串与 UTF-8 文本', () {
      final spec = ContainerSpec(
        name: 'T',
        header: HeaderRule(),
        children: {
          'text': ChildSpec(
            type: 'text',
            fields: [
              FieldSpec('magic', type: FieldType.bytes, length: 2),
              FieldSpec('title', type: FieldType.utf8),
            ],
          ),
        },
      );
      final source = MemoryByteSource.of(
        concat([ascii('text'), u32be(8 + 2 + 6), ascii('ab'), utf8('标题')]),
      );

      final result = parseContainer(spec, source);

      final fields = {
        for (final field in result.root.children.single.fields)
          field.key: field.value,
      };
      expect(fields['magic'], Uint8List.fromList(ascii('ab')));
      expect(fields['title'], '标题');
    });

    test('EBML 风格：变长类型 id 与变长长度', () {
      final spec = ContainerSpec(
        name: 'EBML',
        header: HeaderRule(
          typeBytes: 0,
          sizeBytes: 0,
          vintId: true,
          vintSize: true,
          sizeIncludesHeader: false,
        ),
        children: {
          '0x1A45DFA3': ChildSpec(
            type: '0x1A45DFA3',
            fields: [FieldSpec('value', type: FieldType.uint8)],
          ),
        },
      );
      final source = MemoryByteSource.of(
        concat([
          [0x1A, 0x45, 0xDF, 0xA3],
          [0x81],
          [0x2A],
        ]),
      );

      final result = parseContainer(spec, source);

      expect(result.truncated, isFalse);
      final child = result.root.children.single;
      expect(child.type, '0x1A45DFA3');
      expect(child.offset, 0);
      expect(child.dataOffset, 5);
      expect(child.dataSize, 1);
      expect(child.fields.single.value, 0x2A);
    });

    test('EBML 风格：两字节宽的变长长度', () {
      final spec = ContainerSpec(
        name: 'EBML',
        header: HeaderRule(
          typeBytes: 0,
          sizeBytes: 0,
          vintId: true,
          vintSize: true,
          sizeIncludesHeader: false,
        ),
        children: const {},
      );
      // 0x40 0x05 → 宽度 2，值 5
      final source = MemoryByteSource.of(
        concat([
          [0x1A, 0x45, 0xDF, 0xA3],
          [0x40, 0x05],
          [1, 2, 3, 4, 5],
        ]),
      );

      final result = parseContainer(spec, source);

      final child = result.root.children.single;
      expect(child.dataOffset, 6);
      expect(child.dataSize, 5);
    });

    test('EBML 风格：未知长度哨兵表示一直到父块末尾', () {
      final spec = ContainerSpec(
        name: 'EBML',
        header: HeaderRule(
          typeBytes: 0,
          sizeBytes: 0,
          vintId: true,
          vintSize: true,
          sizeIncludesHeader: false,
          unknownSizeAllowed: true,
        ),
        children: const {},
      );
      // 0xFF → 宽度 1，数据位全 1 = 未知长度
      final source = MemoryByteSource.of(
        concat([
          [0x1A, 0x45, 0xDF, 0xA3],
          [0xFF],
          [1, 2, 3, 4],
        ]),
      );

      final result = parseContainer(spec, source);

      final child = result.root.children.single;
      expect(child.dataOffset, 5);
      expect(child.dataSize, 4);
    });

    test('size == 1 时读 64 位扩展长度', () {
      final spec = ContainerSpec(
        name: 'MP4',
        header: HeaderRule(sizeFirst: true, extendedSizeWhenOne: true),
        children: {
          'mdat': ChildSpec(
            type: 'mdat',
            fields: [FieldSpec('value', type: FieldType.uint32)],
          ),
        },
      );
      final source = MemoryByteSource.of(
        concat([u32be(1), ascii('mdat'), u64be(20), u32be(0xABCD)]),
      );

      final result = parseContainer(spec, source);

      expect(result.truncated, isFalse);
      final child = result.root.children.single;
      expect(child.type, 'mdat');
      expect(child.size, 20);
      expect(child.dataOffset, 16);
      expect(child.dataSize, 4);
      expect(child.fields.single.value, 0xABCD);
    });

    test('size == 0 表示一直到文件尾', () {
      final spec = ContainerSpec(
        name: 'MP4',
        header: HeaderRule(sizeFirst: true, sizeZeroMeansToEof: true),
        children: const {},
      );
      final source = MemoryByteSource.of(
        concat([
          u32be(0),
          ascii('mdat'),
          [1, 2, 3, 4, 5, 6],
        ]),
      );

      final result = parseContainer(spec, source);

      expect(result.truncated, isFalse);
      final child = result.root.children.single;
      expect(child.type, 'mdat');
      expect(child.size, 14);
      expect(child.dataOffset, 8);
      expect(child.dataSize, 6);
    });

    test('表里没有的类型产出不透明叶子，不报错', () {
      final spec = ContainerSpec(
        name: 'T',
        header: HeaderRule(),
        children: {
          'knwn': ChildSpec(
            type: 'known',
            fields: [FieldSpec('value', type: FieldType.uint8)],
          ),
        },
      );
      final source = MemoryByteSource.of(
        concat([
          ascii('junk'),
          u32be(9),
          [0x01],
          ascii('knwn'),
          u32be(9),
          [0x02],
        ]),
      );

      final result = parseContainer(spec, source);

      expect(result.truncated, isFalse);
      expect(result.error, isNull);
      expect(result.root.children, hasLength(2));
      final junk = result.root.children.first;
      expect(junk.type, 'junk');
      expect(junk.isOpaque, isTrue);
      expect(junk.fields, isEmpty);
      expect(junk.dataSize, 1);
      expect(result.root.children.last.type, 'knwn');
      expect(result.root.children.last.isOpaque, isFalse);
    });

    test('文件被截断：标记 truncated、给出中文说明并返回已解析的部分', () {
      final spec = ContainerSpec(
        name: 'T',
        header: HeaderRule(),
        children: {
          'data': ChildSpec(
            type: 'data',
            fields: [FieldSpec('value', type: FieldType.uint32)],
          ),
        },
      );
      // 声明 100 字节载荷，文件里只有 4 字节。
      final source = MemoryByteSource.of(
        concat([
          ascii('data'),
          u32be(108),
          [1, 2, 3, 4],
        ]),
      );

      final result = parseContainer(spec, source);

      expect(result.truncated, isTrue);
      expect(result.error, isNotNull);
      expect(result.error, contains('截断'));
      expect(result.error, contains('还差'));
      final child = result.root.children.single;
      expect(child.type, 'data');
      expect(child.dataSize, 4);
      expect(child.isOpaque, isTrue);
    });

    test('第二个块被截断时，第一个块照常返回', () {
      final spec = ContainerSpec(
        name: 'T',
        header: HeaderRule(),
        children: {'one1': ChildSpec(type: 'one1')},
      );
      final source = MemoryByteSource.of(
        concat([
          ascii('one1'),
          u32be(8),
          ascii('two1'),
          u32be(99),
          [1, 2],
        ]),
      );

      final result = parseContainer(spec, source);

      expect(result.truncated, isTrue);
      expect(result.root.children, hasLength(2));
      expect(result.root.children.first.type, 'one1');
      expect(result.root.children.first.isOpaque, isFalse);
      expect(result.root.children.last.type, 'two1');
      expect(result.root.children.last.dataSize, 2);
    });

    test('块长度撒谎（超出父块边界）走同一条截断路径', () {
      final inner = ContainerSpec(
        name: 'inner',
        header: HeaderRule(),
        children: {'leaf': ChildSpec(type: 'leaf')},
      );
      final outer = ContainerSpec(
        name: 'outer',
        header: HeaderRule(),
        children: {'box1': ChildSpec(type: 'box1', container: inner)},
      );
      // box 载荷只有 10 字节，里面的 leaf 却声明 64 字节。
      // 文件末尾还有 6 个字节：父块边界落在文件内部，子块越界的是父块。
      final source = MemoryByteSource.of(
        concat([
          ascii('box1'),
          u32be(18),
          ascii('leaf'),
          u32be(64),
          [1, 2],
          [0, 0, 0, 0, 0, 0],
        ]),
      );

      final result = parseContainer(outer, source, depth: 2);

      expect(result.truncated, isTrue);
      expect(result.error, contains('超出父块边界'));
      expect(result.root.children, hasLength(1));
      expect(result.root.children.single.children, hasLength(1));
      expect(result.root.children.single.children.single.dataSize, 2);
    });

    test('按字段值动态分派到二级 ChildSpec', () {
      final spec = ContainerSpec(
        name: 'T',
        header: HeaderRule(),
        children: {
          'ent1': ChildSpec(
            type: 'entry',
            fields: [FieldSpec('format', type: FieldType.fourcc)],
            dispatchOn: 'format',
          ),
          'vid1': ChildSpec(
            type: 'vid1',
            fields: [FieldSpec('width', type: FieldType.uint16)],
          ),
        },
      );
      final source = MemoryByteSource.of(
        concat([ascii('ent1'), u32be(14), ascii('vid1'), u16be(1920)]),
      );

      final result = parseContainer(spec, source);

      final child = result.root.children.single;
      expect(child.type, 'ent1');
      expect(child.isOpaque, isFalse);
      final fields = {for (final f in child.fields) f.key: f.value};
      expect(fields['format'], 'vid1');
      expect(fields['width'], 1920);
    });

    test('分派找不到二级表时降级为不透明叶子', () {
      final spec = ContainerSpec(
        name: 'T',
        header: HeaderRule(),
        children: {
          'ent1': ChildSpec(
            type: 'entry',
            fields: [FieldSpec('format', type: FieldType.fourcc)],
            dispatchOn: 'format',
          ),
        },
      );
      final source = MemoryByteSource.of(
        concat([ascii('ent1'), u32be(12), ascii('zzzz')]),
      );

      final result = parseContainer(spec, source);

      final child = result.root.children.single;
      expect(child.isOpaque, isTrue);
      expect(child.fields.single.value, 'zzzz');
    });

    test('depth 控制惰性展开的层数', () {
      final inner = ContainerSpec(
        name: 'inner',
        header: HeaderRule(),
        children: {
          'leaf': ChildSpec(
            type: 'leaf',
            fields: [FieldSpec('value', type: FieldType.uint8)],
          ),
        },
      );
      final outer = ContainerSpec(
        name: 'outer',
        header: HeaderRule(),
        children: {'box1': ChildSpec(type: 'box1', container: inner)},
      );
      final source = MemoryByteSource.of(
        concat([
          ascii('box1'),
          u32be(17),
          ascii('leaf'),
          u32be(9),
          [7],
        ]),
      );

      final shallow = parseContainer(outer, source);
      expect(shallow.root.children, hasLength(1));
      expect(shallow.root.children.single.children, isEmpty);

      final deep = parseContainer(outer, source, depth: 2);
      expect(deep.root.children.single.children, hasLength(1));
      expect(deep.root.children.single.children.single.fields.single.value, 7);
    });

    test('规格表成环时受递归深度上限保护', () {
      final children = <String, ChildSpec>{};
      final loop = ContainerSpec(
        name: 'loop',
        header: HeaderRule(),
        children: children,
      );
      children['loop'] = ChildSpec(type: 'loop', container: loop);
      // 每层块头 8 字节，载荷里再套一层同样的块。
      var chunk = concat([ascii('loop'), u32be(8)]);
      for (var i = 0; i < 70; i++) {
        chunk = concat([ascii('loop'), u32be(8 + chunk.length), chunk]);
      }
      final source = MemoryByteSource.of(chunk);

      final result = parseContainer(loop, source, depth: 200);

      expect(result.truncated, isFalse);
      final nodes = walk(result.root);
      final deepest = nodes.reduce((a, b) => a.$2 >= b.$2 ? a : b);
      expect(deepest.$2, 64);
      expect(deepest.$1.isOpaque, isTrue);
    });

    test('字段读数超出块范围时降级并保留已读出的字段', () {
      final spec = ContainerSpec(
        name: 'T',
        header: HeaderRule(),
        children: {
          'meta': ChildSpec(
            type: 'meta',
            fields: [
              FieldSpec('len', type: FieldType.uint32),
              FieldSpec('name', type: FieldType.bytes, lengthFrom: 'len'),
            ],
          ),
        },
      );
      final source = MemoryByteSource.of(
        concat([ascii('meta'), u32be(12), u32be(100)]),
      );

      final result = parseContainer(spec, source);

      expect(result.truncated, isTrue);
      expect(result.error, contains('超出块范围'));
      final child = result.root.children.single;
      expect(child.isOpaque, isTrue);
      expect(child.fields.single.key, 'len');
      expect(child.fields.single.value, 100);
    });

    test('读出有符号整数与 24 位整数', () {
      final spec = ContainerSpec(
        name: 'T',
        header: HeaderRule(),
        children: {
          'nums': ChildSpec(
            type: 'nums',
            fields: [
              FieldSpec('small', type: FieldType.sint8),
              FieldSpec('medium', type: FieldType.sint16),
              FieldSpec('large', type: FieldType.sint32),
              FieldSpec('mid', type: FieldType.uint24),
            ],
          ),
        },
      );
      final source = MemoryByteSource.of(
        concat([
          ascii('nums'),
          u32be(18),
          [0xFF], // -1
          u16be(0xFFFE), // -2
          u32be(0xFFFFFFFD), // -3
          u24be(0x010203), // 66051
        ]),
      );

      final result = parseContainer(spec, source);

      final fields = {
        for (final field in result.root.children.single.fields)
          field.key: field.value,
      };
      expect(fields['small'], -1);
      expect(fields['medium'], -2);
      expect(fields['large'], -3);
      expect(fields['mid'], 0x010203);
    });

    test('RIFF 风格：长度不含块头 + 奇数长度补一个对齐字节', () {      final spec = ContainerSpec(
        name: 'RIFF',
        header: HeaderRule(
          sizeBytes: 4,
          sizeIncludesHeader: false,
          endian: Endian.little,
          padTo: 2,
        ),
        children: const {},
      );
      final source = MemoryByteSource.of(
        concat([
          ascii('fmt '),
          u32le(5),
          [1, 2, 3, 4, 5],
          [0], // 对齐填充
          ascii('data'),
          u32le(2),
          [6, 7],
        ]),
      );

      final result = parseContainer(spec, source);

      expect(result.truncated, isFalse);
      expect(result.root.children, hasLength(2));
      final fmt = result.root.children.first;
      expect(fmt.type, 'fmt ');
      expect(fmt.size, 13);
      expect(fmt.dataSize, 5);
      final data = result.root.children.last;
      expect(data.type, 'data');
      expect(data.offset, 14);
      expect(data.dataSize, 2);
    });
  });
}
