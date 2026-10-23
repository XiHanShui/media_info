/// 结构树视图的行列断言。
///
/// 覆盖 user story 17–24、47、55：
/// 节点顺序、坐标列、占比列、惰性展开、不透明叶子、路径行 key、
/// 折叠、虚拟滚动。
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_info/src/core/node.dart';
import 'package:media_info/src/ui/structure_tree.dart';

import '../support/document_builder.dart';

/// 把结构树放进一个有边界的窗口里。
Widget appOf(Widget child, {double width = 1200, double height = 600}) =>
    MaterialApp(
      home: Scaffold(
        body: SizedBox(width: width, height: height, child: child),
      ),
    );

/// 数一下当前构建出来的行数。
int rowCount(WidgetTester tester) => tester
    .widgetList(
      find.byWidgetPredicate(
        (Widget widget) =>
            widget.key is ValueKey<String> &&
            (widget.key! as ValueKey<String>).value.startsWith(
              'structure-row-',
            ),
      ),
    )
    .length;

void main() {
  group('表头', () {
    testWidgets('四列表头：块 / 偏移 / 大小 / 占比', (WidgetTester tester) async {
      final ContainerNode root = buildNode(
        'MP4',
        0,
        100,
        children: <ContainerNode>[buildNode('mdat', 40, 60)],
      );

      await tester.pumpWidget(
        appOf(StructureTree(root: root, filePath: 'a.mp4', fileSize: 100)),
      );

      expect(find.text('块'), findsOneWidget);
      expect(find.text('偏移'), findsOneWidget);
      expect(find.text('大小'), findsOneWidget);
      expect(find.text('占比'), findsOneWidget);
    });
  });

  group('行顺序与坐标列', () {
    testWidgets('父块在它的子块之前', (WidgetTester tester) async {
      final ContainerNode root = buildNode(
        'MP4',
        0,
        100,
        children: <ContainerNode>[
          buildNode(
            'moov',
            10,
            90,
            children: <ContainerNode>[buildNode('trak', 20, 80)],
          ),
        ],
      );

      await tester.pumpWidget(
        appOf(StructureTree(root: root, filePath: 'a.mp4', fileSize: 100)),
      );

      await tester.tap(
        find.byKey(const ValueKey<String>('structure-toggle-0')),
      );
      await tester.pumpAndSettle();

      expect(
        tester.getTopLeft(find.text('moov')).dy,
        lessThan(tester.getTopLeft(find.text('trak')).dy),
      );
    });

    testWidgets('子块在展开前不出现', (WidgetTester tester) async {
      final ContainerNode root = buildNode(
        'MP4',
        0,
        100,
        children: <ContainerNode>[
          buildNode(
            'moov',
            10,
            90,
            children: <ContainerNode>[buildNode('trak', 20, 80)],
          ),
        ],
      );

      await tester.pumpWidget(
        appOf(StructureTree(root: root, filePath: 'a.mp4', fileSize: 100)),
      );

      expect(find.text('trak'), findsNothing);

      await tester.tap(
        find.byKey(const ValueKey<String>('structure-toggle-0')),
      );
      await tester.pumpAndSettle();

      expect(find.text('trak'), findsOneWidget);
    });

    testWidgets('每行给出精确的偏移量与长度', (WidgetTester tester) async {
      final ContainerNode root = buildNode(
        'MP4',
        0,
        100,
        children: <ContainerNode>[buildNode('mdat', 40, 60)],
      );

      await tester.pumpWidget(
        appOf(StructureTree(root: root, filePath: 'a.mp4', fileSize: 100)),
      );

      final Finder row = find.byKey(const ValueKey<String>('structure-row-0'));
      expect(
        find.descendant(of: row, matching: find.text('40')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: row, matching: find.text('60')),
        findsOneWidget,
      );
    });

    testWidgets('层级越深缩进越多', (WidgetTester tester) async {
      final ContainerNode root = buildNode(
        'MP4',
        0,
        100,
        children: <ContainerNode>[
          buildNode(
            'moov',
            10,
            90,
            children: <ContainerNode>[buildNode('trak', 20, 80)],
          ),
        ],
      );

      await tester.pumpWidget(
        appOf(StructureTree(root: root, filePath: 'a.mp4', fileSize: 100)),
      );

      final double parentX = tester.getTopLeft(find.text('moov')).dx;
      await tester.tap(
        find.byKey(const ValueKey<String>('structure-toggle-0')),
      );
      await tester.pumpAndSettle();
      final double childX = tester.getTopLeft(find.text('trak')).dx;

      expect(childX, greaterThan(parentX));
    });
  });

  group('路径行 key', () {
    testWidgets('根节点是 structure-row-root', (WidgetTester tester) async {
      final ContainerNode root = buildNode('MP4', 0, 100);

      await tester.pumpWidget(
        appOf(StructureTree(root: root, filePath: 'a.mp4', fileSize: 100)),
      );

      expect(
        find.byKey(const ValueKey<String>('structure-row-root')),
        findsOneWidget,
      );
    });

    testWidgets('子节点用子节点下标链做 key', (WidgetTester tester) async {
      final ContainerNode root = buildNode(
        'MP4',
        0,
        100,
        children: <ContainerNode>[
          buildNode(
            'moov',
            10,
            90,
            children: <ContainerNode>[buildNode('trak', 20, 80)],
          ),
        ],
      );

      await tester.pumpWidget(
        appOf(StructureTree(root: root, filePath: 'a.mp4', fileSize: 100)),
      );

      expect(
        find.byKey(const ValueKey<String>('structure-row-0')),
        findsOneWidget,
      );

      await tester.tap(
        find.byKey(const ValueKey<String>('structure-toggle-0')),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey<String>('structure-row-0.0')),
        findsOneWidget,
      );
    });

    testWidgets('同一个偏移不会产生重复的 key', (WidgetTester tester) async {
      // 根节点与第一个子块的偏移都是 0——key 必须不同，否则 Flutter 的元素树会错位。
      final ContainerNode root = buildNode(
        'MP4',
        0,
        100,
        children: <ContainerNode>[buildNode('ftyp', 0, 32)],
      );

      await tester.pumpWidget(
        appOf(StructureTree(root: root, filePath: 'a.mp4', fileSize: 100)),
      );

      expect(
        find.byKey(const ValueKey<String>('structure-row-root')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey<String>('structure-row-0')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('展开按钮', () {
    testWidgets('有子块的节点用箭头', (WidgetTester tester) async {
      final ContainerNode root = buildNode(
        'MP4',
        0,
        100,
        children: <ContainerNode>[
          buildNode(
            'moov',
            10,
            90,
            children: <ContainerNode>[buildNode('trak', 20, 80)],
          ),
        ],
      );

      await tester.pumpWidget(
        appOf(StructureTree(root: root, filePath: 'a.mp4', fileSize: 100)),
      );

      expect(find.byIcon(Icons.expand_more), findsOneWidget);
      expect(find.byIcon(Icons.add), findsNothing);
    });

    testWidgets('不透明叶子没有展开按钮', (WidgetTester tester) async {
      final ContainerNode root = buildNode(
        'MP4',
        0,
        100,
        children: <ContainerNode>[buildNode('mdat', 40, 60, isOpaque: true)],
      );

      await tester.pumpWidget(
        appOf(StructureTree(root: root, filePath: 'a.mp4', fileSize: 100)),
      );

      expect(
        find.byKey(const ValueKey<String>('structure-toggle-0')),
        findsNothing,
      );
      expect(find.byIcon(Icons.add), findsNothing);
    });

    testWidgets('还有更多可加载的节点显示「+」', (WidgetTester tester) async {
      final ContainerNode root = buildNode(
        'MP4',
        0,
        100,
        children: <ContainerNode>[buildNode('moov', 10, 90)],
      );

      await tester.pumpWidget(
        appOf(StructureTree(root: root, filePath: 'a.mp4', fileSize: 100)),
      );

      expect(find.byIcon(Icons.add), findsOneWidget);
      expect(
        find.byKey(const ValueKey<String>('structure-toggle-0')),
        findsOneWidget,
      );
    });

    testWidgets('重新解析后确实没有子块，就不再显示展开按钮', (WidgetTester tester) async {
      final ContainerNode root = buildNode(
        'MP4',
        0,
        100,
        children: <ContainerNode>[buildNode('moov', 10, 90)],
      );

      await tester.pumpWidget(
        appOf(
          StructureTree(
            root: root,
            filePath: 'a.mp4',
            fileSize: 100,
            loader: (String path, {required int depth}) async => root,
          ),
        ),
      );

      expect(find.byIcon(Icons.add), findsOneWidget);

      await tester.tap(
        find.byKey(const ValueKey<String>('structure-toggle-0')),
      );
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.add), findsNothing);
    });

    testWidgets('展开时按更大的深度重新解析，并接上新的子块', (WidgetTester tester) async {
      final ContainerNode shallow = buildNode(
        'MP4',
        0,
        100,
        children: <ContainerNode>[buildNode('moov', 10, 90)],
      );
      final ContainerNode deeper = buildNode(
        'MP4',
        0,
        100,
        children: <ContainerNode>[
          buildNode(
            'moov',
            10,
            90,
            children: <ContainerNode>[buildNode('trak', 20, 80)],
          ),
        ],
      );
      final List<int> depths = <int>[];

      await tester.pumpWidget(
        appOf(
          StructureTree(
            root: shallow,
            filePath: 'a.mp4',
            fileSize: 100,
            loader: (String path, {required int depth}) async {
              depths.add(depth);
              return deeper;
            },
          ),
        ),
      );

      await tester.tap(
        find.byKey(const ValueKey<String>('structure-toggle-0')),
      );
      await tester.pumpAndSettle();

      expect(depths, hasLength(1));
      expect(depths.single, greaterThan(kDefaultStructureDepth));
      expect(find.text('trak'), findsOneWidget);
    });

    testWidgets('不透明节点不触发惰性展开', (WidgetTester tester) async {
      final ContainerNode root = buildNode(
        'MP4',
        0,
        100,
        children: <ContainerNode>[buildNode('mdat', 40, 60, isOpaque: true)],
      );
      final List<int> depths = <int>[];

      await tester.pumpWidget(
        appOf(
          StructureTree(
            root: root,
            filePath: 'a.mp4',
            fileSize: 100,
            loader: (String path, {required int depth}) async {
              depths.add(depth);
              return root;
            },
          ),
        ),
      );

      expect(find.byIcon(Icons.add), findsNothing);
      expect(depths, isEmpty);
    });
  });

  group('折叠', () {
    testWidgets('折叠后子块一起收起来', (WidgetTester tester) async {
      final ContainerNode root = buildNode(
        'MP4',
        0,
        100,
        children: <ContainerNode>[
          buildNode(
            'moov',
            10,
            90,
            children: <ContainerNode>[buildNode('trak', 20, 80)],
          ),
        ],
      );

      await tester.pumpWidget(
        appOf(StructureTree(root: root, filePath: 'a.mp4', fileSize: 100)),
      );

      await tester.tap(
        find.byKey(const ValueKey<String>('structure-toggle-0')),
      );
      await tester.pumpAndSettle();
      expect(find.text('trak'), findsOneWidget);

      await tester.tap(
        find.byKey(const ValueKey<String>('structure-toggle-0')),
      );
      await tester.pumpAndSettle();
      expect(find.text('trak'), findsNothing);
    });

    testWidgets('resetToken 变化时展开状态被重置', (WidgetTester tester) async {
      final ContainerNode root = buildNode(
        'MP4',
        0,
        100,
        children: <ContainerNode>[
          buildNode(
            'moov',
            10,
            90,
            children: <ContainerNode>[buildNode('trak', 20, 80)],
          ),
        ],
      );

      await tester.pumpWidget(
        appOf(
          StructureTree(
            root: root,
            filePath: 'a.mp4',
            fileSize: 100,
            resetToken: 0,
          ),
        ),
      );
      await tester.tap(
        find.byKey(const ValueKey<String>('structure-toggle-0')),
      );
      await tester.pumpAndSettle();
      expect(find.text('trak'), findsOneWidget);

      await tester.pumpWidget(
        appOf(
          StructureTree(
            root: root,
            filePath: 'a.mp4',
            fileSize: 100,
            resetToken: 1,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('trak'), findsNothing);
    });
  });

  group('占比列', () {
    testWidgets('百分比文本按大小分级取整', (WidgetTester tester) async {
      final ContainerNode root = buildNode(
        'MP4',
        0,
        1000,
        children: <ContainerNode>[
          buildNode('tiny', 0, 5),
          buildNode('small', 5, 45),
          buildNode('big', 50, 680),
        ],
      );

      await tester.pumpWidget(
        appOf(StructureTree(root: root, filePath: 'a.mp4', fileSize: 1000)),
      );

      expect(find.text('0.5%'), findsOneWidget);
      expect(find.text('4.5%'), findsOneWidget);
      expect(find.text('68%'), findsOneWidget);
    });

    testWidgets('大小为 0 的块显示 0%', (WidgetTester tester) async {
      final ContainerNode root = buildNode(
        'MP4',
        0,
        1000,
        children: <ContainerNode>[buildNode('free', 0, 0)],
      );

      await tester.pumpWidget(
        appOf(StructureTree(root: root, filePath: 'a.mp4', fileSize: 1000)),
      );

      final Finder row = find.byKey(const ValueKey<String>('structure-row-0'));
      expect(
        find.descendant(of: row, matching: find.text('0%')),
        findsOneWidget,
      );
    });

    testWidgets('文件大小未知时不显示百分比', (WidgetTester tester) async {
      final ContainerNode root = buildNode(
        'MP4',
        0,
        100,
        children: <ContainerNode>[buildNode('mdat', 40, 60)],
      );

      await tester.pumpWidget(
        appOf(StructureTree(root: root, filePath: 'a.mp4', fileSize: 0)),
      );

      final Finder row = find.byKey(const ValueKey<String>('structure-row-0'));
      expect(
        find.descendant(of: row, matching: find.text('0%')),
        findsOneWidget,
      );
    });

    testWidgets('占比条的宽度与块的大小成正比', (WidgetTester tester) async {
      final ContainerNode root = buildNode(
        'MP4',
        0,
        100,
        children: <ContainerNode>[buildNode('mdat', 40, 68)],
      );

      await tester.pumpWidget(
        appOf(StructureTree(root: root, filePath: 'a.mp4', fileSize: 100)),
      );

      final Finder bar = find.byKey(const ValueKey<String>('structure-bar-0'));
      expect(bar, findsOneWidget);
      expect(
        tester.getSize(bar).width,
        closeTo(kProportionBarWidth * 0.68, 0.5),
      );
    });
  });

  group('选中态', () {
    testWidgets('选中的块在树里高亮', (WidgetTester tester) async {
      final ContainerNode mdat = buildNode('mdat', 40, 60);
      final ContainerNode root = buildNode(
        'MP4',
        0,
        100,
        children: <ContainerNode>[mdat],
      );

      await tester.pumpWidget(
        appOf(
          StructureTree(
            root: root,
            filePath: 'a.mp4',
            fileSize: 100,
            selectedNode: mdat,
          ),
        ),
      );

      final Finder row = find.byKey(const ValueKey<String>('structure-row-0'));
      final Container rowContainer = tester.widget<Container>(
        find.descendant(of: row, matching: find.byType(Container)).first,
      );
      expect(rowContainer.color, isNotNull);
      final BoxBorder border =
          (rowContainer.foregroundDecoration! as BoxDecoration).border!;
      expect(border, isA<Border>());
      expect((border as Border).left.color, isNotNull);
    });

    testWidgets('点击一行会回调选中的节点', (WidgetTester tester) async {
      final ContainerNode mdat = buildNode('mdat', 40, 60);
      final ContainerNode root = buildNode(
        'MP4',
        0,
        100,
        children: <ContainerNode>[mdat],
      );
      ContainerNode? selected;

      await tester.pumpWidget(
        appOf(
          StructureTree(
            root: root,
            filePath: 'a.mp4',
            fileSize: 100,
            onNodeSelected: (ContainerNode node) => selected = node,
          ),
        ),
      );

      await tester.tap(find.byKey(const ValueKey<String>('structure-row-0')));
      await tester.pumpAndSettle();

      expect(selected, isNotNull);
      expect(selected!.type, 'mdat');
    });
  });

  group('没有结构时', () {
    testWidgets('root 为 null 时显示「没有结构信息」', (WidgetTester tester) async {
      await tester.pumpWidget(
        appOf(StructureTree(root: null, filePath: 'a.mp4', fileSize: 0)),
      );

      expect(find.text('没有结构信息'), findsOneWidget);
    });
  });

  group('虚拟滚动', () {
    testWidgets('几千个子条目也只构建可见的行', (WidgetTester tester) async {
      final ContainerNode root = buildNode(
        'MP4',
        0,
        300000,
        children: <ContainerNode>[
          for (int index = 0; index < 3000; index++)
            buildNode('stts', index * 100, 100),
        ],
      );

      await tester.pumpWidget(
        appOf(StructureTree(root: root, filePath: 'a.mp4', fileSize: 300000)),
      );
      await tester.pumpAndSettle();

      expect(rowCount(tester), lessThan(200));
      expect(find.text('stts'), findsWidgets);
    });
  });

  group('显示名', () {
    testWidgets('普通块类型名原样显示，不翻译', (WidgetTester tester) async {
      final ContainerNode root = buildNode(
        'WAV',
        0,
        100,
        children: <ContainerNode>[buildNode('fmt ', 12, 24)],
      );

      await tester.pumpWidget(
        appOf(StructureTree(root: root, filePath: 'a.wav', fileSize: 100)),
      );

      expect(find.text('fmt '), findsOneWidget);
    });

    testWidgets('Matroska 的十六进制元素 ID 显示成元素名', (WidgetTester tester) async {
      final ContainerNode root = buildNode(
        'Matroska',
        0,
        100,
        children: <ContainerNode>[buildNode('0x18538067', 40, 60)],
      );

      await tester.pumpWidget(
        appOf(StructureTree(root: root, filePath: 'a.mkv', fileSize: 100)),
      );

      expect(find.text('Segment'), findsOneWidget);
      expect(find.text('0x18538067'), findsNothing);
    });
  });
}
