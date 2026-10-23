import 'package:flutter_test/flutter_test.dart';
import 'package:media_info/src/core/registry.dart';
import 'package:media_info/src/core/spec.dart';

import 'support/memory_byte_source.dart';

ContainerSpec _emptySpec(String name) =>
    ContainerSpec(name: name, header: HeaderRule(), children: const {});

void main() {
  group('格式注册表', () {
    setUp(clearFormats);
    tearDown(clearFormats);

    test('注册表初始为空', () {
      expect(allFormats(), isEmpty);
      expect(detectFormat(MemoryByteSource.of([1, 2, 3])), isNull);
    });

    test('按内容嗅探选出格式，注册顺序即嗅探顺序', () {
      registerFormat(
        FormatSpec(
          name: 'AAA',
          container: _emptySpec('AAA'),
          detect: (source) => source.read(0, 4).first == 0xAA,
        ),
      );
      registerFormat(
        FormatSpec(
          name: 'BBB',
          container: _emptySpec('BBB'),
          detect: (source) => source.read(0, 4).first == 0xBB,
        ),
      );

      expect(allFormats().map((f) => f.name), ['AAA', 'BBB']);
      expect(detectFormat(MemoryByteSource.of([0xAA, 0, 0, 0]))?.name, 'AAA');
      expect(detectFormat(MemoryByteSource.of([0xBB, 0, 0, 0]))?.name, 'BBB');
      expect(detectFormat(MemoryByteSource.of([0xCC, 0, 0, 0])), isNull);
    });

    test('同名格式被替换而不是重复登记', () {
      registerFormat(FormatSpec(name: 'AAA', container: _emptySpec('AAA')));
      registerFormat(FormatSpec(name: 'AAA', container: _emptySpec('AAA2')));

      expect(allFormats(), hasLength(1));
      expect(allFormats().single.container.name, 'AAA2');
    });

    test('文件短到读不出魔数时不崩溃', () {
      registerFormat(
        FormatSpec(
          name: 'AAA',
          container: _emptySpec('AAA'),
          detect: (source) => source.read(0, 4).first == 0xAA,
        ),
      );

      expect(detectFormat(MemoryByteSource.of([0xAA])), isNull);
    });

    test('注册表登记的是规格表而不是解析器对象', () {
      final spec = ContainerSpec(
        name: 'WAV',
        header: HeaderRule(),
        children: const {},
      );
      registerFormat(FormatSpec(name: 'WAV', container: spec));

      final format = allFormats().single;
      expect(format.container, same(spec));
      expect(format.extractor, isNull);
      expect(format.detect, isNull);
    });
  });
}
