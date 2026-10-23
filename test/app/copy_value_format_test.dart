/// 右键复制字段值时的**文本格式**断言。
///
/// 覆盖 user story 16 与 `docs/design/visual-language.md`「交互约定」：
/// - 值复制时**不含单位**；
/// - 时长格式化成 `HH:MM:SS.mmm`；
/// - 二进制值复制成十六进制串。
library;

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:media_info/src/app/export.dart';
import 'package:media_info/src/core/node.dart';
import 'package:media_info/src/core/tag.dart';

void main() {
  group('时长：HH:MM:SS.mmm', () {
    test('整秒', () {
      expect(formatCopiedValue(1.0, key: kDurationFieldKey), '00:00:01.000');
    });

    test('毫秒', () {
      expect(formatCopiedValue(0.25, key: kDurationFieldKey), '00:00:00.250');
    });

    test('小时以上', () {
      expect(formatCopiedValue(3661.5, key: kDurationFieldKey), '01:01:01.500');
    });

    test('不足一秒', () {
      expect(formatCopiedValue(0.001, key: kDurationFieldKey), '00:00:00.001');
    });

    test('不是 duration 键时按普通数字处理', () {
      expect(formatCopiedValue(1.0, key: 'timescale'), '1');
    });

    test('负数退回普通格式（不给出负的时长）', () {
      expect(formatCopiedValue(-1.0, key: kDurationFieldKey), '-1');
    });

    test('非有限数退回普通格式', () {
      expect(
        formatCopiedValue(double.infinity, key: kDurationFieldKey),
        'Infinity',
      );
      expect(formatCopiedValue(double.nan, key: kDurationFieldKey), 'NaN');
    });

    test('时长字段的 key 就是 duration', () {
      expect(kDurationFieldKey, 'duration');
    });
  });

  group('数字', () {
    test('整数按整数复制', () {
      expect(formatCopiedValue(44100), '44100');
      expect(formatCopiedValue(0), '0');
    });

    test('负整数带负号', () {
      expect(formatCopiedValue(-3), '-3');
    });

    test('整数值的小数不显示小数尾巴', () {
      expect(formatCopiedValue(1.0), '1');
    });

    test('非整数值保留原来的小数', () {
      expect(formatCopiedValue(1.25), '1.25');
    });

    test('非有限数原样复制，不被静默改成 0', () {
      expect(formatCopiedValue(double.infinity), 'Infinity');
      expect(formatCopiedValue(double.negativeInfinity), '-Infinity');
      expect(formatCopiedValue(double.nan), 'NaN');
    });
  });

  group('布尔与 null', () {
    test('布尔复制成 true / false', () {
      expect(formatCopiedValue(true), 'true');
      expect(formatCopiedValue(false), 'false');
    });

    test('null 复制成空字符串', () {
      expect(formatCopiedValue(null), '');
    });
  });

  group('文本与单位', () {
    test('结尾带「空格 + 单位」的文本去掉单位', () {
      expect(formatCopiedValue('44100 Hz', unit: 'Hz'), '44100');
      expect(formatCopiedValue('16 bit', unit: 'bit'), '16');
    });

    test('不匹配的结尾保持原样', () {
      expect(formatCopiedValue('44100 Hz', unit: 'bit'), '44100 Hz');
    });

    test('没有单位时原样复制', () {
      expect(formatCopiedValue('Lavf61.3.104'), 'Lavf61.3.104');
    });

    test('空单位不被当成要剥离的后缀', () {
      expect(formatCopiedValue('abc', unit: ''), 'abc');
      expect(formatCopiedValue('abc', unit: null), 'abc');
    });

    test('整个字符串就是单位时保持原样（不剥成空串）', () {
      expect(formatCopiedValue('Hz', unit: 'Hz'), 'Hz');
    });

    test('非 ASCII 文本原样复制', () {
      expect(formatCopiedValue('歌曲名'), '歌曲名');
    });
  });

  group('二进制与集合', () {
    test('字节串复制成小写十六进制串', () {
      expect(
        formatCopiedValue(Uint8List.fromList(<int>[0x0A, 0xFF, 0x10])),
        '0aff10',
      );
    });

    test('空字节串复制成空串', () {
      expect(formatCopiedValue(Uint8List(0)), '');
    });

    test('列表按逗号连接', () {
      expect(formatCopiedValue(<String>['isom', 'iso2']), 'isom, iso2');
    });

    test('空列表复制成空串', () {
      expect(formatCopiedValue(<int>[]), '');
    });

    test('Map 复制成「键: 值」的连接', () {
      expect(formatCopiedValue(<String, int>{'a': 1, 'b': 2}), 'a: 1, b: 2');
    });
  });

  group('语义字段与标签的复制文本', () {
    test('语义字段带上自己的 key 与 unit', () {
      const SemanticField field = SemanticField(
        key: 'sample_rate',
        label: '采样率',
        value: '44100 Hz',
        unit: 'Hz',
      );

      expect(formatCopiedFieldValue(field), '44100');
    });

    test('duration 字段被格式化成 HH:MM:SS.mmm', () {
      const SemanticField field = SemanticField(
        key: 'duration',
        label: '时长',
        value: 1.0,
        unit: 's',
      );

      expect(formatCopiedFieldValue(field), '00:00:01.000');
    });

    test('标签值按同样的规则复制', () {
      const Tag tag = Tag(key: '©nam', value: 'Song');

      expect(formatCopiedTagValue(tag), 'Song');
    });

    test('标签的 key 不参与复制（复制的是值）', () {
      const Tag tag = Tag(key: '©nam', value: null);

      expect(formatCopiedTagValue(tag), '');
    });
  });
}
