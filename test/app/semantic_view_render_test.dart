/// 语义字段视图（左栏）的渲染断言。
///
/// 覆盖 user story 8–16、46、47：
/// 三个区段的顺序、中文显示名 + 英文技术名、单位、推算标记、
/// 空区段的提示、值的格式化、长值截断与 tooltip、非 ASCII 文本。
library;

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_info/src/app/parse_service.dart';
import 'package:media_info/src/app/semantic_view.dart';
import 'package:media_info/src/app/theme.dart';
import 'package:media_info/src/core/node.dart';
import 'package:media_info/src/core/tag.dart';

import '../support/document_builder.dart';

/// 把语义视图放进一个有边界的窗口里。
Widget appOf(ParsedDocument document) => MaterialApp(
  home: Scaffold(
    body: SizedBox(
      width: 480,
      height: 900,
      child: SemanticView(document: document),
    ),
  ),
);

void main() {
  group('三个区段的顺序', () {
    testWidgets('文件级 → 轨道级 → 标签，顺序固定', (WidgetTester tester) async {
      await tester.pumpWidget(
        appOf(
          buildDocument(
            fileFields: <SemanticField>[
              buildField('file_name', value: 'a.mp4'),
            ],
            tracks: <TrackFields>[
              buildTrack(0, <SemanticField>[
                buildField('codec', value: 'avc1'),
              ]),
            ],
            tags: <Tag>[buildTag('©nam', 'Song')],
          ),
        ),
      );

      final double fileY = tester.getTopLeft(find.text('文件级')).dy;
      final double trackY = tester.getTopLeft(find.text('轨道级')).dy;
      final double tagY = tester.getTopLeft(find.text('标签')).dy;

      expect(fileY, lessThan(trackY));
      expect(trackY, lessThan(tagY));
    });

    testWidgets('每个区段只有一个眉标', (WidgetTester tester) async {
      await tester.pumpWidget(appOf(buildDocument()));

      expect(find.text('文件级'), findsOneWidget);
      expect(find.text('轨道级'), findsOneWidget);
      expect(find.text('标签'), findsOneWidget);
    });
  });

  group('空区段的提示', () {
    testWidgets('没有文件级字段时显示提示文字', (WidgetTester tester) async {
      await tester.pumpWidget(appOf(buildDocument()));

      expect(find.text('没有文件级字段'), findsOneWidget);
    });

    testWidgets('没有轨道级字段时显示提示文字', (WidgetTester tester) async {
      await tester.pumpWidget(appOf(buildDocument()));

      expect(find.text('没有轨道级字段'), findsOneWidget);
    });

    testWidgets('没有标签时显示提示文字', (WidgetTester tester) async {
      await tester.pumpWidget(appOf(buildDocument()));

      expect(find.text('没有标签'), findsOneWidget);
    });

    testWidgets('有内容时不显示空态提示', (WidgetTester tester) async {
      await tester.pumpWidget(
        appOf(
          buildDocument(
            fileFields: <SemanticField>[
              buildField('file_name', value: 'a.mp4'),
            ],
          ),
        ),
      );

      expect(find.text('没有文件级字段'), findsNothing);
      expect(find.text('没有轨道级字段'), findsOneWidget);
      expect(find.text('没有标签'), findsOneWidget);
    });
  });

  group('字段行：中文显示名 + 英文技术名 + 单位', () {
    testWidgets('显示名与英文技术名同时出现', (WidgetTester tester) async {
      await tester.pumpWidget(
        appOf(
          buildDocument(
            fileFields: <SemanticField>[
              buildField('sample_rate', label: '采样率', value: 44100),
            ],
          ),
        ),
      );

      expect(find.text('采样率'), findsOneWidget);
      expect(find.text('sample_rate'), findsOneWidget);
    });

    testWidgets('单位单独显示在值后面', (WidgetTester tester) async {
      await tester.pumpWidget(
        appOf(
          buildDocument(
            fileFields: <SemanticField>[
              buildField('sample_rate', label: '采样率', value: 44100, unit: 'Hz'),
            ],
          ),
        ),
      );

      expect(find.text('44100'), findsOneWidget);
      expect(find.text('Hz'), findsOneWidget);
    });

    testWidgets('没有单位时不渲染单位文本', (WidgetTester tester) async {
      await tester.pumpWidget(
        appOf(
          buildDocument(
            fileFields: <SemanticField>[
              buildField('file_name', label: '文件名', value: 'a.mp4'),
            ],
          ),
        ),
      );

      expect(find.text('a.mp4'), findsOneWidget);
      expect(find.text('byte'), findsNothing);
    });

    testWidgets('英文技术名不翻译（保持规范原词）', (WidgetTester tester) async {
      await tester.pumpWidget(
        appOf(
          buildDocument(
            fileFields: <SemanticField>[
              buildField('container_format', label: '容器格式', value: 'isom'),
              buildField('overall_bitrate', label: '平均码率', value: 93264),
            ],
          ),
        ),
      );

      expect(find.text('container_format'), findsOneWidget);
      expect(find.text('overall_bitrate'), findsOneWidget);
      expect(find.text('Container Format'), findsNothing);
    });
  });

  group('推算值的标记', () {
    testWidgets('推算值带「（推算）」标记', (WidgetTester tester) async {
      await tester.pumpWidget(
        appOf(
          buildDocument(
            fileFields: <SemanticField>[
              buildField(
                'overall_bitrate',
                label: '平均码率',
                value: 93264,
                origin: FieldOrigin.derived,
              ),
            ],
          ),
        ),
      );

      expect(find.text(kDerivedSuffix), findsOneWidget);
      expect(find.text(kDerivedSuffix), findsExactly(1));
    });

    testWidgets('文件里直接写的值不带推算标记', (WidgetTester tester) async {
      await tester.pumpWidget(
        appOf(
          buildDocument(
            fileFields: <SemanticField>[
              buildField('duration', label: '时长', value: 1.0),
            ],
          ),
        ),
      );

      expect(find.text(kDerivedSuffix), findsNothing);
    });

    testWidgets('推算标记用紫色（推算色）', (WidgetTester tester) async {
      await tester.pumpWidget(
        appOf(
          buildDocument(
            fileFields: <SemanticField>[
              buildField(
                'overall_bitrate',
                label: '平均码率',
                value: 93264,
                origin: FieldOrigin.derived,
              ),
            ],
          ),
        ),
      );

      final Text chip = tester.widget<Text>(find.text(kDerivedSuffix));
      expect(chip.style?.color, MediaColors.violet);
    });

    testWidgets('推算值与普通值混排时，只给推算的那一个加标记', (WidgetTester tester) async {
      await tester.pumpWidget(
        appOf(
          buildDocument(
            fileFields: <SemanticField>[
              buildField('duration', label: '时长', value: 1.0),
              buildField(
                'overall_bitrate',
                label: '平均码率',
                value: 93264,
                origin: FieldOrigin.derived,
              ),
            ],
          ),
        ),
      );

      expect(find.text(kDerivedSuffix), findsOneWidget);
    });
  });

  group('轨道分组', () {
    testWidgets('每条轨道一个标题，序号从 0 起', (WidgetTester tester) async {
      await tester.pumpWidget(
        appOf(
          buildDocument(
            tracks: <TrackFields>[
              buildTrack(0, <SemanticField>[
                buildField('codec', value: 'avc1'),
              ]),
              buildTrack(1, <SemanticField>[
                buildField('codec', value: 'mp4a'),
              ]),
            ],
          ),
        ),
      );

      expect(find.text('轨道 0'), findsOneWidget);
      expect(find.text('轨道 1'), findsOneWidget);
      expect(find.text('avc1'), findsOneWidget);
      expect(find.text('mp4a'), findsOneWidget);
    });

    testWidgets('轨道标题在它的字段之前', (WidgetTester tester) async {
      await tester.pumpWidget(
        appOf(
          buildDocument(
            tracks: <TrackFields>[
              buildTrack(0, <SemanticField>[
                buildField('codec', value: 'avc1'),
              ]),
            ],
          ),
        ),
      );

      expect(
        tester.getTopLeft(find.text('轨道 0')).dy,
        lessThan(tester.getTopLeft(find.text('avc1')).dy),
      );
    });
  });

  group('标签区', () {
    testWidgets('标签的 key 原样显示（不翻译、不美化）', (WidgetTester tester) async {
      await tester.pumpWidget(
        appOf(
          buildDocument(
            tags: <Tag>[
              buildTag('©nam', 'Song Title'),
              buildTag('TITLE', 'Another'),
            ],
          ),
        ),
      );

      expect(find.text('©nam'), findsOneWidget);
      expect(find.text('TITLE'), findsOneWidget);
      expect(find.text('名称'), findsNothing);
    });

    testWidgets('标签的值与 key 分列显示', (WidgetTester tester) async {
      await tester.pumpWidget(
        appOf(buildDocument(tags: <Tag>[buildTag('©nam', 'Song Title')])),
      );

      expect(find.text('Song Title'), findsOneWidget);
    });

    testWidgets('标签与语义字段是两个区段，互不混排', (WidgetTester tester) async {
      await tester.pumpWidget(
        appOf(
          buildDocument(
            fileFields: <SemanticField>[
              buildField('file_name', label: '文件名', value: 'a.mp4'),
            ],
            tags: <Tag>[buildTag('file_name', 'not-a-field')],
          ),
        ),
      );

      expect(find.text('标签'), findsOneWidget);
      expect(find.text('文件名'), findsOneWidget);
      expect(find.text('not-a-field'), findsOneWidget);
    });

    testWidgets('二进制标签值显示成「（N 字节）」', (WidgetTester tester) async {
      await tester.pumpWidget(
        appOf(
          buildDocument(
            tags: <Tag>[
              buildTag('covr', Uint8List.fromList(<int>[1, 2, 3, 4, 5])),
            ],
          ),
        ),
      );

      expect(find.text('（5 字节）'), findsOneWidget);
    });
  });

  group('值的格式化（formatFieldValue）', () {
    test('null 显示成破折号', () {
      expect(formatFieldValue(null), '—');
    });

    test('布尔值显示成「是」/「否」', () {
      expect(formatFieldValue(true), '是');
      expect(formatFieldValue(false), '否');
    });

    test('整数按整数显示，不带小数尾巴', () {
      expect(formatFieldValue(44100), '44100');
      expect(formatFieldValue(0), '0');
    });

    test('整数值的小数显示成整数', () {
      expect(formatFieldValue(1.0), '1');
      expect(formatFieldValue(0.0), '0');
    });

    test('非整数值保留三位小数', () {
      expect(formatFieldValue(1.25), '1.250');
    });

    test('非有限数原样显示，不被静默改成 0', () {
      expect(formatFieldValue(double.infinity), 'Infinity');
      expect(formatFieldValue(double.negativeInfinity), '-Infinity');
      expect(formatFieldValue(double.nan), 'NaN');
    });

    test('短列表展开显示', () {
      expect(formatFieldValue(<String>['isom', 'iso2']), 'isom, iso2');
      expect(formatFieldValue(<int>[1, 2, 3, 4, 5, 6]), '1, 2, 3, 4, 5, 6');
    });

    test('长列表折叠成「（N 项）」', () {
      expect(formatFieldValue(<int>[1, 2, 3, 4, 5, 6, 7]), '（7 项）');
    });

    test('空列表显示成「（空）」', () {
      expect(formatFieldValue(<int>[]), '（空）');
    });

    test('字节串显示成「（N 字节）」', () {
      expect(formatFieldValue(Uint8List.fromList(<int>[1, 2, 3])), '（3 字节）');
    });

    test('Map 显示成「（N 项）」', () {
      expect(formatFieldValue(<String, int>{'a': 1, 'b': 2}), '（2 项）');
    });

    test('列表里的 null 显示成破折号', () {
      expect(formatFieldValue(<Object?>[null, 1]), '—, 1');
    });
  });

  group('长值：省略号 + tooltip', () {
    testWidgets('超过 28 个字符的值挂 tooltip，tooltip 里是完整值', (
      WidgetTester tester,
    ) async {
      const String long = '这是一个非常非常长的编码器厂商字符串用来测试省略号与 tooltip 的行为';
      await tester.pumpWidget(
        appOf(
          buildDocument(
            fileFields: <SemanticField>[
              buildField('compressorname', label: '编码器', value: long),
            ],
          ),
        ),
      );

      expect(find.byType(Tooltip), findsOneWidget);
      final Tooltip tooltip = tester.widget<Tooltip>(find.byType(Tooltip));
      expect(tooltip.message, long);
    });

    testWidgets('短值不挂 tooltip', (WidgetTester tester) async {
      await tester.pumpWidget(
        appOf(
          buildDocument(
            fileFields: <SemanticField>[
              buildField('file_name', label: '文件名', value: 'a.mp4'),
            ],
          ),
        ),
      );

      expect(find.byType(Tooltip), findsNothing);
    });

    testWidgets('值文本单行显示并允许省略', (WidgetTester tester) async {
      await tester.pumpWidget(
        appOf(
          buildDocument(
            fileFields: <SemanticField>[
              buildField('compressorname', label: '编码器', value: 'x' * 200),
            ],
          ),
        ),
      );

      final Text text = tester.widget<Text>(find.text('x' * 200));
      expect(text.maxLines, 1);
      expect(text.overflow, TextOverflow.ellipsis);
    });
  });

  group('非 ASCII 文本', () {
    testWidgets('中文值原样渲染', (WidgetTester tester) async {
      await tester.pumpWidget(
        appOf(
          buildDocument(
            fileFields: <SemanticField>[
              buildField('title', label: '标题', value: '歌曲名'),
            ],
          ),
        ),
      );

      expect(find.text('歌曲名'), findsOneWidget);
    });

    testWidgets('emoji 值原样渲染', (WidgetTester tester) async {
      await tester.pumpWidget(
        appOf(buildDocument(tags: <Tag>[buildTag('mood', '🎬🎧')])),
      );

      expect(find.text('🎬🎧'), findsOneWidget);
    });

    testWidgets('非 ASCII 的显示名与英文技术名一起显示', (WidgetTester tester) async {
      await tester.pumpWidget(
        appOf(
          buildDocument(
            fileFields: <SemanticField>[
              buildField('movie_name', label: '文件名', value: '电影.mkv'),
            ],
          ),
        ),
      );

      expect(find.text('文件名'), findsOneWidget);
      expect(find.text('电影.mkv'), findsOneWidget);
    });
  });
}
