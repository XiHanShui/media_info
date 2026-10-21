/// 通用容器引擎的契约测试。
///
/// 契约见 `docs/design/core-api.md` §3 / §4：
/// - 长度字段的六种语义（含头与否、0 表示到文件尾、`size == 1` 的 64 位扩展、
///   变长整数、未知长度哨兵）；
/// - 字段的九种类型；
/// - 动态 type 分派；
/// - **"未知即跳过"兜底**；
/// - 递归深度上限；
/// - 读到的字节少于声明长度 → 立即停止、`truncated = true`、给出中文说明，
///   **已解析的部分结构照常返回**。
library;

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:media_info/src/core/engine.dart';
import 'package:media_info/src/core/node.dart';
import 'package:media_info/src/core/spec.dart';

import 'support/byte_fixtures.dart';
import 'support/memory_byte_source.dart';

/// 造一张最简单的规格表：4 字节类型 + 4 字节长度（含头）。
ContainerSpec simpleSpec({
  String name = 'T',
  Map<String, ChildSpec> children = const <String, ChildSpec>{},
  HeaderRule header = const HeaderRule(),
}) => ContainerSpec(name: name, header: header, children: children);

void main() {
  group('ParseResult 契约', () {
    test('默认不是截断，也没有错误说明', () {
      const ParseResult result = ParseResult(
        root: ContainerNode(
          type: 'T',
          offset: 0,
          size: 0,
          dataOffset: 0,
          dataSize: 0,
        ),
      );

      expect(result.truncated, isFalse);
      expect(result.error, isNull);
    });

    test('根节点覆盖整个文件', () {
      final ParseResult result = parseContainer(
        simpleSpec(),
        MemoryByteSource.of(<int>[1, 2, 3, 4, 5]),
      );

      expect(result.root.type, 'T');
      expect(result.root.offset, 0);
      expect(result.root.size, 5);
      expect(result.root.dataOffset, 0);
      expect(result.root.dataSize, 5);
      expect(result.root.isOpaque, isFalse);
      expect(result.root.children, isEmpty);
    });

    test('rootType 可以改掉根节点的显示名', () {
      final ParseResult result = parseContainer(
        ContainerSpec(
          name: 'MP4',
          rootType: 'ISO-BMFF',
          header: const HeaderRule(),
          children: const <String, ChildSpec>{},
        ),
        MemoryByteSource.of(<int>[1, 2, 3, 4]),
      );

      expect(result.root.type, 'ISO-BMFF');
    });

    test('没给 rootType 时根节点用规格表的名字', () {
      expect(
        ContainerSpec(
          name: 'WAV',
          header: const HeaderRule(),
          children: const <String, ChildSpec>{},
        ).effectiveRootType,
        'WAV',
      );
    });
  });

  group('惰性展开（depth）', () {
    ContainerSpec nested() {
      final ContainerSpec inner = ContainerSpec(
        name: 'inner',
        header: const HeaderRule(),
        children: <String, ChildSpec>{
          'leaf': ChildSpec(
            type: 'leaf',
            fields: <FieldSpec>[FieldSpec('value', type: FieldType.uint8)],
          ),
        },
      );
      return ContainerSpec(
        name: 'outer',
        header: const HeaderRule(),
        children: <String, ChildSpec>{
          'box1': ChildSpec(type: 'box1', container: inner),
        },
      );
    }

    test('depth 1 只建第一层子块', () {
      final ParseResult result = parseContainer(
        nested(),
        MemoryByteSource.of(
          concat(<List<int>>[
            ascii('box1'),
            u32be(17),
            ascii('leaf'),
            u32be(9),
            <int>[7],
          ]),
        ),
        depth: 1,
      );

      expect(result.root.children, hasLength(1));
      expect(result.root.children.single.children, isEmpty);
    });

    test('depth 2 建到第二层', () {
      final ParseResult result = parseContainer(
        nested(),
        MemoryByteSource.of(
          concat(<List<int>>[
            ascii('box1'),
            u32be(17),
            ascii('leaf'),
            u32be(9),
            <int>[7],
          ]),
        ),
        depth: 2,
      );

      expect(result.root.children.single.children, hasLength(1));
      expect(
        result.root.children.single.children.single.fields.single.value,
        7,
      );
    });

    test('depth 小于 1 时按第一层处理', () {
      final ParseResult result = parseContainer(
        nested(),
        MemoryByteSource.of(
          concat(<List<int>>[
            ascii('box1'),
            u32be(17),
            ascii('leaf'),
            u32be(9),
            <int>[7],
          ]),
        ),
        depth: 0,
      );

      expect(result.root.children, hasLength(1));
      expect(result.root.children.single.children, isEmpty);
    });

    test('超过 maxDepth 的块不再展开，并被标记为不透明', () {
      final ParseResult result = parseContainer(
        nested(),
        MemoryByteSource.of(
          concat(<List<int>>[
            ascii('box1'),
            u32be(17),
            ascii('leaf'),
            u32be(9),
            <int>[7],
          ]),
        ),
        depth: 8,
        maxDepth: 1,
      );

      final ContainerNode box = result.root.children.single;
      expect(box.isOpaque, isTrue);
      expect(box.children, isEmpty);
    });
  });

  group('"未知即跳过"兜底', () {
    test('表里查不到的 type 产出不透明叶子，不递归也不报错', () {
      final ParseResult result = parseContainer(
        simpleSpec(
          children: <String, ChildSpec>{
            'knwn': ChildSpec(
              type: 'knwn',
              fields: <FieldSpec>[FieldSpec('value', type: FieldType.uint8)],
            ),
          },
        ),
        MemoryByteSource.of(
          concat(<List<int>>[
            ascii('junk'),
            u32be(9),
            <int>[0x01],
            ascii('knwn'),
            u32be(9),
            <int>[0x02],
          ]),
        ),
      );

      expect(result.truncated, isFalse);
      expect(result.error, isNull);
      expect(result.root.children, hasLength(2));
      expect(result.root.children.first.type, 'junk');
      expect(result.root.children.first.isOpaque, isTrue);
      expect(result.root.children.first.children, isEmpty);
      expect(result.root.children.last.type, 'knwn');
      expect(result.root.children.last.isOpaque, isFalse);
    });

    test('未知块不会挡住后面的已知块', () {
      final ParseResult result = parseContainer(
        simpleSpec(
          children: <String, ChildSpec>{'knwn': ChildSpec(type: 'knwn')},
        ),
        MemoryByteSource.of(
          concat(<List<int>>[ascii('zzzz'), u32be(8), ascii('knwn'), u32be(8)]),
        ),
      );

      expect(result.root.children.map((ContainerNode c) => c.type), <String>[
        'zzzz',
        'knwn',
      ]);
    });
  });

  group('长度字段的六种语义', () {
    test('size == 1 时跟一个 64 位扩展长度', () {
      final ParseResult result = parseContainer(
        simpleSpec(
          header: const HeaderRule(sizeFirst: true, extendedSizeWhenOne: true),
          children: <String, ChildSpec>{'mdat': ChildSpec(type: 'mdat')},
        ),
        MemoryByteSource.of(
          concat(<List<int>>[
            u32be(1),
            ascii('mdat'),
            u64be(20),
            <int>[1, 2, 3, 4],
          ]),
        ),
      );

      final ContainerNode child = result.root.children.single;
      expect(child.size, 20);
      expect(child.dataOffset, 16);
      expect(child.dataSize, 4);
      expect(result.truncated, isFalse);
    });

    test('扩展长度字段本身被截断时给出明确说明', () {
      final ParseResult result = parseContainer(
        simpleSpec(
          header: const HeaderRule(sizeFirst: true, extendedSizeWhenOne: true),
        ),
        MemoryByteSource.of(
          concat(<List<int>>[
            u32be(1),
            ascii('mdat'),
            <int>[0, 0, 0, 0],
          ]),
        ),
      );

      expect(result.truncated, isTrue);
      expect(result.error, '文件在偏移 8 处截断，扩展长度字段不完整');
    });

    test('size == 0 表示一直到文件尾', () {
      final ParseResult result = parseContainer(
        simpleSpec(
          header: const HeaderRule(sizeFirst: true, sizeZeroMeansToEof: true),
        ),
        MemoryByteSource.of(
          concat(<List<int>>[
            u32be(0),
            ascii('mdat'),
            <int>[1, 2, 3, 4, 5, 6],
          ]),
        ),
      );

      final ContainerNode child = result.root.children.single;
      expect(child.size, 14);
      expect(child.dataOffset, 8);
      expect(child.dataSize, 6);
      expect(result.truncated, isFalse);
    });

    test('长度不含块头时载荷长度就是长度字段的值', () {
      final ParseResult result = parseContainer(
        simpleSpec(header: const HeaderRule(sizeIncludesHeader: false)),
        MemoryByteSource.of(
          concat(<List<int>>[
            ascii('fmt '),
            u32be(12),
            <int>[1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12],
          ]),
        ),
      );

      final ContainerNode child = result.root.children.single;
      expect(child.dataOffset, 8);
      expect(child.dataSize, 12);
      expect(child.size, 20);
    });

    test('全 1 的长度是"未知长度"哨兵，载荷一直到文件尾', () {
      final ParseResult result = parseContainer(
        simpleSpec(header: const HeaderRule(unknownSizeAllowed: true)),
        MemoryByteSource.of(
          concat(<List<int>>[
            ascii('data'),
            <int>[0xFF, 0xFF, 0xFF, 0xFF],
            <int>[1, 2, 3, 4],
          ]),
        ),
      );

      final ContainerNode child = result.root.children.single;
      expect(child.dataOffset, 8);
      expect(child.dataSize, 4);
      expect(result.truncated, isFalse);
    });

    test('声明的长度小于块头长度时报错并停止', () {
      final ParseResult result = parseContainer(
        simpleSpec(),
        MemoryByteSource.of(concat(<List<int>>[ascii('data'), u32be(2)])),
      );

      expect(result.truncated, isTrue);
      expect(result.error, '块 data 在偏移 0 处声明的长度 2 小于块头长度 8');
      final ContainerNode child = result.root.children.single;
      expect(child.isOpaque, isTrue);
      expect(child.dataSize, 0);
    });
  });

  group('截断降级', () {
    test('文件在偏移 X 处截断，声明长度还差 N 字节', () {
      final ParseResult result = parseContainer(
        simpleSpec(),
        MemoryByteSource.of(
          concat(<List<int>>[
            ascii('data'),
            u32be(108),
            <int>[1, 2, 3, 4],
          ]),
        ),
      );

      expect(result.truncated, isTrue);
      expect(result.error, '文件在偏移 12 处截断，声明长度还差 96 字节');
    });

    test('已解析的部分结构照常返回', () {
      final ParseResult result = parseContainer(
        simpleSpec(
          children: <String, ChildSpec>{'one1': ChildSpec(type: 'one1')},
        ),
        MemoryByteSource.of(
          concat(<List<int>>[
            ascii('one1'),
            u32be(8),
            ascii('two1'),
            u32be(99),
            <int>[1, 2],
          ]),
        ),
      );

      expect(result.truncated, isTrue);
      expect(result.root.children, hasLength(2));
      expect(result.root.children.first.type, 'one1');
      expect(result.root.children.first.isOpaque, isFalse);
      expect(result.root.children.last.type, 'two1');
      expect(result.root.children.last.dataSize, 2);
      expect(result.root.children.last.isOpaque, isTrue);
    });

    test('块类型字段本身被截断', () {
      final ParseResult result = parseContainer(
        simpleSpec(),
        MemoryByteSource.of(<int>[0x61, 0x62]),
      );

      expect(result.truncated, isTrue);
      expect(result.error, '文件在偏移 0 处截断，块类型不完整');
    });

    test('长度字段本身被截断', () {
      final ParseResult result = parseContainer(
        simpleSpec(),
        MemoryByteSource.of(ascii('data')),
      );

      expect(result.truncated, isTrue);
      expect(result.error, '文件在偏移 4 处截断，长度字段不完整');
    });

    test('缺少对齐填充字节', () {
      final ParseResult result = parseContainer(
        simpleSpec(header: const HeaderRule(padTo: 2)),
        MemoryByteSource.of(
          concat(<List<int>>[
            ascii('data'),
            u32be(13),
            <int>[1, 2, 3, 4, 5],
          ]),
        ),
      );

      expect(result.truncated, isTrue);
      expect(result.error, '文件在偏移 14 处截断，缺少对齐填充字节');
    });

    test('引擎不抛异常：乱码输入也返回 ParseResult', () {
      final ParseResult result = parseContainer(
        simpleSpec(),
        MemoryByteSource.of(
          List<int>.generate(64, (int index) => (index * 37) & 0xFF),
        ),
      );

      expect(result.root, isNotNull);
      expect(result.error, anyOf(isNull, isA<String>()));
    });
  });

  group('字段类型', () {
    test('字节序可逐字段指定', () {
      final ParseResult result = parseContainer(
        simpleSpec(
          children: <String, ChildSpec>{
            'nums': ChildSpec(
              type: 'nums',
              fields: <FieldSpec>[
                FieldSpec('be', type: FieldType.uint32),
                FieldSpec('le', type: FieldType.uint32, endian: Endian.little),
              ],
            ),
          },
        ),
        MemoryByteSource.of(
          concat(<List<int>>[
            ascii('nums'),
            u32be(16),
            u32be(0x01020304),
            u32le(0x01020304),
          ]),
        ),
      );

      final Map<String, Object?> values = <String, Object?>{
        for (final SemanticField f in result.root.children.single.fields)
          f.key: f.value,
      };
      expect(values['be'], 0x01020304);
      expect(values['le'], 0x01020304);
    });

    test('位域可以跨字节读', () {
      final ParseResult result = parseContainer(
        simpleSpec(
          children: <String, ChildSpec>{
            'bits': ChildSpec(
              type: 'bits',
              fields: <FieldSpec>[
                FieldSpec('wide', type: FieldType.bits, bitWidth: 12),
              ],
            ),
          },
        ),
        MemoryByteSource.of(
          concat(<List<int>>[
            ascii('bits'),
            u32be(10),
            <int>[0xAB, 0xCD],
          ]),
        ),
      );

      expect(result.root.children.single.fields.single.value, 0xABC);
    });

    test('布尔值读成 true / false', () {
      final ParseResult result = parseContainer(
        simpleSpec(
          children: <String, ChildSpec>{
            'flag': ChildSpec(
              type: 'flag',
              fields: <FieldSpec>[
                FieldSpec('yes', type: FieldType.boolean),
                FieldSpec('no', type: FieldType.boolean),
              ],
            ),
          },
        ),
        MemoryByteSource.of(
          concat(<List<int>>[
            ascii('flag'),
            u32be(9),
            <int>[0x80],
          ]),
        ),
      );

      final List<SemanticField> fields = result.root.children.single.fields;
      expect(fields[0].value, isTrue);
      expect(fields[1].value, isFalse);
    });

    test('有符号整数读出负数', () {
      final ParseResult result = parseContainer(
        simpleSpec(
          children: <String, ChildSpec>{
            'nums': ChildSpec(
              type: 'nums',
              fields: <FieldSpec>[
                FieldSpec('small', type: FieldType.sint8),
                FieldSpec('medium', type: FieldType.sint16),
                FieldSpec('large', type: FieldType.sint32),
                FieldSpec('mid', type: FieldType.uint24),
              ],
            ),
          },
        ),
        MemoryByteSource.of(
          concat(<List<int>>[
            ascii('nums'),
            u32be(18),
            <int>[0xFF],
            u16be(0xFFFE),
            u32be(0xFFFFFFFD),
            u24be(0x010203),
          ]),
        ),
      );

      final Map<String, Object?> values = <String, Object?>{
        for (final SemanticField f in result.root.children.single.fields)
          f.key: f.value,
      };
      expect(values['small'], -1);
      expect(values['medium'], -2);
      expect(values['large'], -3);
      expect(values['mid'], 0x010203);
    });

    test('64 位整数读出大于 2^32 的值', () {
      final ParseResult result = parseContainer(
        simpleSpec(
          children: <String, ChildSpec>{
            'bigs': ChildSpec(
              type: 'bigs',
              fields: <FieldSpec>[FieldSpec('value', type: FieldType.uint64)],
            ),
          },
        ),
        MemoryByteSource.of(
          concat(<List<int>>[
            ascii('bigs'),
            u32be(16),
            u64be(0x0000FFFFFFFFFFFF),
          ]),
        ),
      );

      expect(result.root.children.single.fields.single.value, 281474976710655);
    });

    test('没有长度也没有 lengthFrom 的字节串读到块载荷末尾', () {
      final ParseResult result = parseContainer(
        simpleSpec(
          children: <String, ChildSpec>{
            'rest': ChildSpec(
              type: 'rest',
              fields: <FieldSpec>[FieldSpec('data', type: FieldType.bytes)],
            ),
          },
        ),
        MemoryByteSource.of(
          concat(<List<int>>[
            ascii('rest'),
            u32be(11),
            <int>[1, 2, 3],
          ]),
        ),
      );

      expect(result.root.children.single.fields.single.value, <int>[1, 2, 3]);
    });

    test('lengthFrom 指向不存在的字段时用 defaultValue', () {
      final ParseResult result = parseContainer(
        simpleSpec(
          children: <String, ChildSpec>{
            'meta': ChildSpec(
              type: 'meta',
              fields: <FieldSpec>[
                FieldSpec(
                  'name',
                  type: FieldType.bytes,
                  lengthFrom: 'missing',
                  defaultValue: 2,
                ),
              ],
            ),
          },
        ),
        MemoryByteSource.of(
          concat(<List<int>>[
            ascii('meta'),
            u32be(10),
            <int>[7, 8],
          ]),
        ),
      );

      expect(result.root.children.single.fields.single.value, <int>[7, 8]);
    });

    test('lengthFrom 指向不存在的字段且没有 defaultValue 时长度为 0', () {
      final ParseResult result = parseContainer(
        simpleSpec(
          children: <String, ChildSpec>{
            'meta': ChildSpec(
              type: 'meta',
              fields: <FieldSpec>[
                FieldSpec('name', type: FieldType.bytes, lengthFrom: 'missing'),
              ],
            ),
          },
        ),
        MemoryByteSource.of(
          concat(<List<int>>[
            ascii('meta'),
            u32be(9),
            <int>[7],
          ]),
        ),
      );

      expect(result.root.children.single.fields.single.value, isEmpty);
    });

    test('countFrom 指向不存在的字段时用 defaultValue 作为次数', () {
      final ParseResult result = parseContainer(
        simpleSpec(
          children: <String, ChildSpec>{
            'meta': ChildSpec(
              type: 'meta',
              fields: <FieldSpec>[
                FieldSpec(
                  'item',
                  type: FieldType.uint8,
                  countFrom: 'missing',
                  defaultValue: 3,
                ),
              ],
            ),
          },
        ),
        MemoryByteSource.of(
          concat(<List<int>>[
            ascii('meta'),
            u32be(11),
            <int>[1, 2, 3],
          ]),
        ),
      );

      expect(result.root.children.single.fields.single.value, <int>[1, 2, 3]);
    });

    test('countFrom 指向不存在的字段且没有 defaultValue 时是空列表', () {
      final ParseResult result = parseContainer(
        simpleSpec(
          children: <String, ChildSpec>{
            'meta': ChildSpec(
              type: 'meta',
              fields: <FieldSpec>[
                FieldSpec('item', type: FieldType.uint8, countFrom: 'missing'),
              ],
            ),
          },
        ),
        MemoryByteSource.of(concat(<List<int>>[ascii('meta'), u32be(8)])),
      );

      expect(result.root.children.single.fields.single.value, isEmpty);
    });

    test('UTF-8 文本遇到非法字节不抛异常', () {
      final ParseResult result = parseContainer(
        simpleSpec(
          children: <String, ChildSpec>{
            'text': ChildSpec(
              type: 'text',
              fields: <FieldSpec>[FieldSpec('title', type: FieldType.utf8)],
            ),
          },
        ),
        MemoryByteSource.of(
          concat(<List<int>>[
            ascii('text'),
            u32be(10),
            <int>[0xFF, 0xFE],
          ]),
        ),
      );

      expect(result.truncated, isFalse);
      expect(result.root.children.single.fields.single.value, isA<String>());
    });

    test('字段带 source = 所属块的类型名', () {
      final ParseResult result = parseContainer(
        simpleSpec(
          children: <String, ChildSpec>{
            'fmt ': ChildSpec(
              type: 'fmt ',
              fields: <FieldSpec>[FieldSpec('value', type: FieldType.uint8)],
            ),
          },
        ),
        MemoryByteSource.of(
          concat(<List<int>>[
            ascii('fmt '),
            u32be(9),
            <int>[3],
          ]),
        ),
      );

      final SemanticField field = result.root.children.single.fields.single;
      expect(field.key, 'value');
      expect(field.source, 'fmt ');
      expect(field.origin, FieldOrigin.read);
      expect(field.scope, FieldScope.file);
    });
  });

  group('动态 type 分派', () {
    test('按本块字段的值选二级表', () {
      final ParseResult result = parseContainer(
        simpleSpec(
          children: <String, ChildSpec>{
            'ent1': ChildSpec(
              type: 'entry',
              fields: <FieldSpec>[FieldSpec('format', type: FieldType.fourcc)],
              dispatchOn: 'format',
            ),
            'vid1': ChildSpec(
              type: 'vid1',
              fields: <FieldSpec>[FieldSpec('width', type: FieldType.uint16)],
            ),
          },
        ),
        MemoryByteSource.of(
          concat(<List<int>>[
            ascii('ent1'),
            u32be(14),
            ascii('vid1'),
            u16be(1920),
          ]),
        ),
      );

      final ContainerNode child = result.root.children.single;
      expect(child.isOpaque, isFalse);
      final Map<String, Object?> values = <String, Object?>{
        for (final SemanticField f in child.fields) f.key: f.value,
      };
      expect(values['format'], 'vid1');
      expect(values['width'], 1920);
    });

    test('分派键可以沿作用域链从祖先继承', () {
      final ContainerSpec inner = ContainerSpec(
        name: 'inner',
        // 载荷开头 4 字节是 `kind`（'vid'），子块从它后面开始。
        header: const HeaderRule(prefixBytes: 4),
        children: <String, ChildSpec>{
          'ent1': ChildSpec(type: 'entry', dispatchOn: 'kind'),
          'vid1': ChildSpec(
            type: 'vid1',
            fields: <FieldSpec>[FieldSpec('width', type: FieldType.uint16)],
          ),
        },
      );
      final ParseResult result = parseContainer(
        simpleSpec(
          children: <String, ChildSpec>{
            'box1': ChildSpec(
              type: 'box1',
              fields: <FieldSpec>[FieldSpec('kind', type: FieldType.fourcc)],
              container: inner,
            ),
          },
        ),
        MemoryByteSource.of(
          concat(<List<int>>[
            ascii('box1'),
            u32be(22),
            ascii('vid1'),
            ascii('ent1'),
            u32be(10),
            u16be(1920),
          ]),
        ),
        depth: 3,
      );

      final ContainerNode box = result.root.children.single;
      expect(box.isOpaque, isFalse);
      final ContainerNode entry = box.children.single;
      expect(entry.isOpaque, isFalse);
      final Map<String, Object?> values = <String, Object?>{
        for (final SemanticField f in entry.fields) f.key: f.value,
      };
      expect(values['width'], 1920);
    });

    test('分派找不到二级表时降级为不透明叶子，但保留已读字段', () {
      final ParseResult result = parseContainer(
        simpleSpec(
          children: <String, ChildSpec>{
            'ent1': ChildSpec(
              type: 'entry',
              fields: <FieldSpec>[FieldSpec('format', type: FieldType.fourcc)],
              dispatchOn: 'format',
            ),
          },
        ),
        MemoryByteSource.of(
          concat(<List<int>>[ascii('ent1'), u32be(12), ascii('zzzz')]),
        ),
      );

      final ContainerNode child = result.root.children.single;
      expect(child.isOpaque, isTrue);
      expect(child.fields.single.value, 'zzzz');
    });
  });

  group('容器载荷的前缀字节', () {
    ContainerSpec prefixSpec(int prefixBytes) {
      final ContainerSpec inner = ContainerSpec(
        name: 'Chunks',
        header: HeaderRule(
          sizeBytes: 4,
          sizeIncludesHeader: false,
          endian: Endian.little,
          prefixBytes: prefixBytes,
        ),
        children: <String, ChildSpec>{'fmt ': const ChildSpec(type: 'fmt ')},
      );
      return simpleSpec(
        header: const HeaderRule(
          sizeBytes: 4,
          sizeIncludesHeader: false,
          endian: Endian.little,
        ),
        children: <String, ChildSpec>{
          'RIFF': ChildSpec(type: 'RIFF', container: inner),
        },
      );
    }

    test('prefixBytes 跳过 form type 再读子块', () {
      final ParseResult result = parseContainer(
        prefixSpec(4),
        MemoryByteSource.of(
          concat(<List<int>>[
            ascii('RIFF'),
            u32le(12),
            ascii('WAVE'),
            ascii('fmt '),
            u32le(0),
          ]),
        ),
        depth: 2,
      );

      final ContainerNode riff = result.root.children.single;
      expect(riff.children.map((ContainerNode c) => c.type), <String>['fmt ']);
      expect(riff.children.single.offset, 12);
      expect(result.truncated, isFalse);
    });

    test('前缀比载荷还长时被裁到载荷末尾，不越界', () {
      final ParseResult result = parseContainer(
        prefixSpec(64),
        MemoryByteSource.of(
          concat(<List<int>>[
            ascii('RIFF'),
            u32le(12),
            ascii('WAVE'),
            ascii('fmt '),
            u32le(0),
          ]),
        ),
        depth: 2,
      );

      expect(result.root.children.single.children, isEmpty);
      expect(result.error, anyOf(isNull, isA<String>()));
    });
  });
}
