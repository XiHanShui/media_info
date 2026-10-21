import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_info/src/core/node.dart';
import 'package:media_info/src/ui/structure_tree.dart';

/// 造一个测试用的结构树节点。
ContainerNode testNode(
  String type,
  int offset,
  int size, {
  List<ContainerNode> children = const <ContainerNode>[],
  bool isOpaque = false,
  List<SemanticField> fields = const <SemanticField>[],
}) => ContainerNode(
  type: type,
  offset: offset,
  size: size,
  dataOffset: offset,
  dataSize: size,
  children: children,
  isOpaque: isOpaque,
  fields: fields,
);

Widget appOf(Widget child) =>
    MaterialApp(home: Scaffold(body: SizedBox(width: 800, child: child)));

void main() {
  testWidgets('结构树列出根节点与它的子块', (WidgetTester tester) async {
    final root = testNode(
      'MP4',
      0,
      100,
      children: <ContainerNode>[
        testNode('ftyp', 0, 32),
        testNode('mdat', 32, 68),
      ],
    );

    await tester.pumpWidget(
      appOf(StructureTree(root: root, filePath: 'a.mp4', fileSize: 100)),
    );

    expect(find.text('MP4'), findsOneWidget);
    expect(find.text('ftyp'), findsOneWidget);
    expect(find.text('mdat'), findsOneWidget);

    // 每一行带 type + offset + size。
    final row = find.byKey(const ValueKey<String>('structure-row-1'));
    expect(row, findsOneWidget);
    expect(
      find.descendant(of: row, matching: find.text('32')),
      findsOneWidget,
      reason: 'mdat 的偏移是 32',
    );
    expect(
      find.descendant(of: row, matching: find.text('68')),
      findsOneWidget,
      reason: 'mdat 的大小是 68',
    );
  });

  testWidgets('展开节点才显示它的子块', (WidgetTester tester) async {
    final root = testNode(
      'MP4',
      0,
      100,
      children: <ContainerNode>[
        testNode('moov', 32, 68, children: <ContainerNode>[
          testNode('trak', 40, 60),
        ]),
      ],
    );

    await tester.pumpWidget(
      appOf(StructureTree(root: root, filePath: 'a.mp4', fileSize: 100)),
    );

    // moov 的子块一开始是收起来的。
    expect(find.text('trak'), findsNothing);

    await tester.tap(find.byKey(const ValueKey<String>('structure-toggle-0')));
    await tester.pumpAndSettle();

    expect(find.text('trak'), findsOneWidget);

    // 再点一次收起来。
    await tester.tap(find.byKey(const ValueKey<String>('structure-toggle-0')));
    await tester.pumpAndSettle();
    expect(find.text('trak'), findsNothing);
  });

  testWidgets('不透明的叶子块没有展开按钮', (WidgetTester tester) async {
    final root = testNode(
      'MP4',
      0,
      100,
      children: <ContainerNode>[
        testNode('mdat', 32, 68, isOpaque: true),
      ],
    );

    await tester.pumpWidget(
      appOf(StructureTree(root: root, filePath: 'a.mp4', fileSize: 100)),
    );

    expect(
      find.byKey(const ValueKey<String>('structure-toggle-0')),
      findsNothing,
    );
  });

  testWidgets('点击一行选中该块并回调', (WidgetTester tester) async {
    final root = testNode(
      'MP4',
      0,
      100,
      children: <ContainerNode>[testNode('mdat', 32, 68)],
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
    expect(selected!.offset, 32);
  });

  testWidgets('展开没有子块的节点时按更大深度重新解析', (
    WidgetTester tester,
  ) async {
    final root = testNode(
      'MP4',
      0,
      100,
      children: <ContainerNode>[testNode('moov', 32, 68)],
    );
    final deeper = testNode(
      'MP4',
      0,
      100,
      children: <ContainerNode>[
        testNode('moov', 32, 68, children: <ContainerNode>[
          testNode('trak', 40, 60),
        ]),
      ],
    );
    final depths = <int>[];

    await tester.pumpWidget(
      appOf(
        StructureTree(
          root: root,
          filePath: 'a.mp4',
          fileSize: 100,
          loader: (String path, {required int depth}) async {
            depths.add(depth);
            return deeper;
          },
        ),
      ),
    );

    // moov 没有子块，但也不是不透明叶子 → 可以惰性展开。
    await tester.tap(find.byKey(const ValueKey<String>('structure-toggle-0')));
    await tester.pumpAndSettle();

    expect(depths, hasLength(1));
    expect(depths.single, greaterThan(kDefaultStructureDepth));
    expect(find.text('trak'), findsOneWidget);
  });

  testWidgets('重新解析期间显示忙碌状态', (WidgetTester tester) async {
    final root = testNode(
      'MP4',
      0,
      100,
      children: <ContainerNode>[testNode('moov', 32, 68)],
    );
    final completer = Completer<ContainerNode?>();

    await tester.pumpWidget(
      appOf(
        StructureTree(
          root: root,
          filePath: 'a.mp4',
          fileSize: 100,
          loader: (String path, {required int depth}) => completer.future,
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey<String>('structure-toggle-0')));
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    completer.complete(null);
    await tester.pumpAndSettle();
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('占比条按块大小占文件大小的比例画', (WidgetTester tester) async {
    final root = testNode(
      'MP4',
      0,
      100,
      children: <ContainerNode>[testNode('mdat', 32, 68)],
    );

    await tester.pumpWidget(
      appOf(StructureTree(root: root, filePath: 'a.mp4', fileSize: 100)),
    );

    final bar = find.byKey(const ValueKey<String>('structure-bar-0'));
    expect(bar, findsOneWidget);
    final width = tester.getSize(bar).width;
    expect(width, closeTo(kProportionBarWidth * 0.68, 0.5));
    expect(find.text('68%'), findsOneWidget);
  });

  test('Matroska 的十六进制元素 ID 显示成元素名', () {
    expect(structureNodeLabel('0x18538067'), 'Segment');
    expect(structureNodeLabel('0x1549A966'), 'Info');
  });

  test('普通块类型名原样显示，不翻译', () {
    expect(structureNodeLabel('moov'), 'moov');
    expect(structureNodeLabel('fmt '), 'fmt ');
  });
}
