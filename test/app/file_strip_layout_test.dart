/// 胶片条（FileStrip）的布局断言。
///
/// 覆盖 user story 55、56：
/// 顶层块按比例排开、位置按真实偏移算、媒体载荷与元数据的配色、
/// 选中段的高亮。
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_info/src/app/file_strip.dart';
import 'package:media_info/src/app/theme.dart';
import 'package:media_info/src/core/node.dart';

import '../support/document_builder.dart';

/// 胶片条的内边距是左右各 16 像素。
const double _stripPadding = 32;

/// 造一个宽度固定的窗口。
Widget appOf(Widget child, {double width = 1000}) => MaterialApp(
  home: Scaffold(
    body: SizedBox(width: width, child: child),
  ),
);

/// 把测试窗口设成指定宽度（默认 800，胶片条的比例断言需要固定宽度）。
Future<void> setSurfaceWidth(WidgetTester tester, double width) async {
  tester.view.physicalSize = Size(width, 600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

/// 取所有段（每个段是一个 Positioned）。
List<Positioned> segmentsOf(WidgetTester tester) =>
    tester.widgetList<Positioned>(find.byType(Positioned)).toList();

/// 取某一段的填充色。
Color fillOf(WidgetTester tester, Positioned segment) {
  final DecoratedBox box = tester.widget<DecoratedBox>(
    find
        .descendant(
          of: find.byWidget(segment),
          matching: find.byType(DecoratedBox),
        )
        .first,
  );
  return (box.decoration as BoxDecoration).color!;
}

/// 取某一段的描边色。
Color borderOf(WidgetTester tester, Positioned segment) {
  final DecoratedBox box = tester.widget<DecoratedBox>(
    find
        .descendant(
          of: find.byWidget(segment),
          matching: find.byType(DecoratedBox),
        )
        .first,
  );
  return (box.decoration as BoxDecoration).border!.top.color;
}

void main() {
  group('比例与位置', () {
    testWidgets('每个顶层块占的宽度与它的长度成正比', (WidgetTester tester) async {
      await setSurfaceWidth(tester, 1000);
      final ContainerNode root = buildNode(
        'MP4',
        0,
        100,
        children: <ContainerNode>[
          buildNode('ftyp', 0, 20),
          buildNode('mdat', 20, 80),
        ],
      );

      await tester.pumpWidget(appOf(FileStrip(root: root)));

      final List<Positioned> segments = segmentsOf(tester);
      expect(segments, hasLength(2));

      const double inner = 1000 - _stripPadding;
      expect(segments[0].left, 0);
      expect(segments[0].width, closeTo(inner * 0.2, 0.5));
      expect(segments[1].left, closeTo(inner * 0.2, 0.5));
      expect(segments[1].width, closeTo(inner * 0.8, 0.5));
    });

    testWidgets('段的位置按累计偏移算，不是等分', (WidgetTester tester) async {
      await setSurfaceWidth(tester, 1000);
      final ContainerNode root = buildNode(
        'MP4',
        0,
        100,
        children: <ContainerNode>[
          buildNode('a', 0, 10),
          buildNode('b', 10, 30),
          buildNode('c', 40, 60),
        ],
      );

      await tester.pumpWidget(appOf(FileStrip(root: root)));

      final List<Positioned> segments = segmentsOf(tester);
      const double inner = 1000 - _stripPadding;
      expect(segments[0].left, 0);
      expect(segments[1].left, closeTo(inner * 0.1, 0.5));
      expect(segments[2].left, closeTo(inner * 0.4, 0.5));
    });

    testWidgets('宽度至少是 1 像素（极小的块也看得见）', (WidgetTester tester) async {
      final ContainerNode root = buildNode(
        'MP4',
        0,
        100000,
        children: <ContainerNode>[
          buildNode('tiny', 0, 1),
          buildNode('rest', 1, 99999),
        ],
      );

      await tester.pumpWidget(appOf(FileStrip(root: root)));

      final List<Positioned> segments = segmentsOf(tester);
      expect(segments[0].width, greaterThanOrEqualTo(1.0));
    });

    testWidgets('顶层只有一个块时直接画它', (WidgetTester tester) async {
      final ContainerNode root = buildNode(
        'WAV',
        0,
        100,
        children: <ContainerNode>[buildNode('RIFF', 0, 100)],
      );

      await tester.pumpWidget(appOf(FileStrip(root: root)));

      expect(segmentsOf(tester), hasLength(1));
    });

    testWidgets('某个顶层块占九成以上且有子块时，改画它的子块', (WidgetTester tester) async {
      final ContainerNode root = buildNode(
        'Matroska',
        0,
        100,
        children: <ContainerNode>[
          buildNode('head', 0, 5),
          buildNode(
            'segment',
            5,
            95,
            children: <ContainerNode>[
              buildNode('info', 10, 20),
              buildNode('cluster', 30, 70),
            ],
          ),
        ],
      );

      await tester.pumpWidget(appOf(FileStrip(root: root)));

      final List<Positioned> segments = segmentsOf(tester);
      expect(segments, hasLength(3));
      expect(find.text('info'), findsOneWidget);
      expect(find.text('cluster'), findsOneWidget);
      expect(find.text('segment'), findsNothing);
    });
  });

  group('配色：颜色是编码不是装饰', () {
    testWidgets('媒体载荷（mdat）是琥珀色', (WidgetTester tester) async {
      final ContainerNode root = buildNode(
        'MP4',
        0,
        100,
        children: <ContainerNode>[buildNode('mdat', 0, 100)],
      );

      await tester.pumpWidget(appOf(FileStrip(root: root)));

      final Positioned segment = segmentsOf(tester).single;
      expect(fillOf(tester, segment), MediaColors.amberDeep);
      expect(borderOf(tester, segment), MediaColors.amber);
    });

    testWidgets('元数据（moov）是青色', (WidgetTester tester) async {
      final ContainerNode root = buildNode(
        'MP4',
        0,
        100,
        children: <ContainerNode>[buildNode('moov', 0, 100)],
      );

      await tester.pumpWidget(appOf(FileStrip(root: root)));

      final Positioned segment = segmentsOf(tester).single;
      expect(fillOf(tester, segment), MediaColors.tealDeep);
      expect(borderOf(tester, segment), MediaColors.teal);
    });

    testWidgets('填充与未知块是暗灰', (WidgetTester tester) async {
      final ContainerNode root = buildNode(
        'MP4',
        0,
        100,
        children: <ContainerNode>[buildNode('free', 0, 100)],
      );

      await tester.pumpWidget(appOf(FileStrip(root: root)));

      final Positioned segment = segmentsOf(tester).single;
      expect(fillOf(tester, segment), MediaColors.edge);
      expect(borderOf(tester, segment), MediaColors.chalkFaint);
    });

    testWidgets('Matroska 的段用规范名而不是十六进制 ID 配色', (WidgetTester tester) async {
      final ContainerNode root = buildNode(
        'Matroska',
        0,
        100,
        children: <ContainerNode>[buildNode('0x1549A966', 0, 100)],
      );

      await tester.pumpWidget(appOf(FileStrip(root: root)));

      final Positioned segment = segmentsOf(tester).single;
      expect(
        fillOf(tester, segment),
        MediaColors.tealDeep,
        reason: '0x1549A966 是 Info（规范名），属于元数据',
      );
    });
  });

  group('选中态', () {
    testWidgets('选中的段被琥珀色描边并提亮', (WidgetTester tester) async {
      final ContainerNode mdat = buildNode('mdat', 0, 100);
      final ContainerNode root = buildNode(
        'MP4',
        0,
        100,
        children: <ContainerNode>[mdat],
      );

      await tester.pumpWidget(appOf(FileStrip(root: root, selected: mdat)));

      final Positioned segment = segmentsOf(tester).single;
      expect(borderOf(tester, segment), MediaColors.amber);
      expect(
        fillOf(tester, segment),
        Color.alphaBlend(
          MediaColors.amberDeep.withValues(alpha: 0.85),
          MediaColors.amber,
        ),
      );
    });

    testWidgets('没选中时是原来的配色', (WidgetTester tester) async {
      final ContainerNode root = buildNode(
        'MP4',
        0,
        100,
        children: <ContainerNode>[buildNode('mdat', 0, 100)],
      );

      await tester.pumpWidget(appOf(FileStrip(root: root)));

      final Positioned segment = segmentsOf(tester).single;
      expect(fillOf(tester, segment), MediaColors.amberDeep);
    });

    testWidgets('选中的块在嵌套里时，所在的顶层段也高亮', (WidgetTester tester) async {
      final ContainerNode trak = buildNode('trak', 10, 10);
      final ContainerNode moov = buildNode(
        'moov',
        0,
        100,
        children: <ContainerNode>[trak],
      );
      final ContainerNode root = buildNode(
        'MP4',
        0,
        100,
        children: <ContainerNode>[moov],
      );

      await tester.pumpWidget(appOf(FileStrip(root: root, selected: trak)));

      final Positioned segment = segmentsOf(tester).single;
      expect(borderOf(tester, segment), MediaColors.amber);
    });

    testWidgets('选中的块不在树里时不高亮任何段', (WidgetTester tester) async {
      final ContainerNode root = buildNode(
        'MP4',
        0,
        100,
        children: <ContainerNode>[buildNode('mdat', 0, 100)],
      );

      await tester.pumpWidget(
        appOf(FileStrip(root: root, selected: buildNode('free', 500, 10))),
      );

      final Positioned segment = segmentsOf(tester).single;
      expect(fillOf(tester, segment), MediaColors.amberDeep);
    });
  });

  group('段内的文字与提示', () {
    testWidgets('段足够宽时在段内写块类型名', (WidgetTester tester) async {
      final ContainerNode root = buildNode(
        'MP4',
        0,
        100,
        children: <ContainerNode>[buildNode('mdat', 0, 100)],
      );

      await tester.pumpWidget(appOf(FileStrip(root: root)));

      expect(find.text('mdat'), findsOneWidget);
    });

    testWidgets('段太窄时不写块类型名', (WidgetTester tester) async {
      final ContainerNode root = buildNode(
        'MP4',
        0,
        100000,
        children: <ContainerNode>[
          buildNode('tiny', 0, 1),
          buildNode('big', 1, 99999),
        ],
      );

      await tester.pumpWidget(appOf(FileStrip(root: root)));

      expect(find.text('tiny'), findsNothing);
      expect(find.text('big'), findsOneWidget);
    });

    testWidgets('悬停提示是「类型 · 偏移 · 长度」', (WidgetTester tester) async {
      final ContainerNode root = buildNode(
        'MP4',
        0,
        100,
        children: <ContainerNode>[buildNode('mdat', 40, 60)],
      );

      await tester.pumpWidget(appOf(FileStrip(root: root)));

      final Tooltip tooltip = tester.widget<Tooltip>(
        find.byType(Tooltip).first,
      );
      expect(tooltip.message, 'mdat  ·  偏移 40  ·  长度 60');
    });
  });

  group('没有结构时', () {
    testWidgets('root 为 null 时不画任何段', (WidgetTester tester) async {
      await tester.pumpWidget(appOf(FileStrip(root: null)));

      expect(segmentsOf(tester), isEmpty);
    });

    testWidgets('root 没有任何子块时不画任何段', (WidgetTester tester) async {
      final ContainerNode root = buildNode('MP4', 0, 100);

      await tester.pumpWidget(appOf(FileStrip(root: root)));

      expect(segmentsOf(tester), isEmpty);
    });

    testWidgets('条子本身的高度是 34 像素', (WidgetTester tester) async {
      final ContainerNode root = buildNode(
        'MP4',
        0,
        100,
        children: <ContainerNode>[buildNode('mdat', 0, 100)],
      );

      await tester.pumpWidget(appOf(FileStrip(root: root)));

      expect(FileStrip.height, 34);
      expect(tester.getSize(find.byType(FileStrip)).height, 34);
    });
  });
}
