import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_info/src/core/node.dart';
import 'package:media_info/src/ui/structure_pane.dart';

ContainerNode testNode(
  String type,
  int offset,
  int size, {
  List<ContainerNode> children = const <ContainerNode>[],
}) => ContainerNode(
  type: type,
  offset: offset,
  size: size,
  dataOffset: offset,
  dataSize: size,
  children: children,
);

Widget appOf(Widget child) => MaterialApp(
  home: Scaffold(body: SizedBox(width: 900, child: child)),
);

String tempFile(String name, List<int> bytes) {
  final dir = Directory.systemTemp.createTempSync('media_info_pane');
  addTearDown(() => dir.deleteSync(recursive: true));
  final file = File('${dir.path}/$name');
  file.writeAsBytesSync(bytes);
  return file.path;
}

void main() {
  testWidgets('没有选中块时不显示 hex 面板', (WidgetTester tester) async {
    final path = tempFile('a.bin', List<int>.filled(64, 0x41));

    await tester.pumpWidget(
      appOf(
        StructurePane(
          filePath: path,
          root: testNode(
            'MP4',
            0,
            64,
            children: <ContainerNode>[testNode('mdat', 16, 48)],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('偏移 16'), findsNothing);
    expect(find.text('大小 48'), findsNothing);
  });

  testWidgets('选中块后下方出现 hex 面板', (WidgetTester tester) async {
    final path = tempFile('b.bin', List<int>.filled(64, 0x41));

    await tester.pumpWidget(
      appOf(
        StructurePane(
          filePath: path,
          root: testNode(
            'MP4',
            0,
            64,
            children: <ContainerNode>[testNode('mdat', 16, 48)],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey<String>('structure-row-0')));
    await tester.pumpAndSettle();

    expect(find.text('偏移 16'), findsOneWidget);
    expect(find.text('大小 48'), findsOneWidget);
  });

  testWidgets('切换标签时重置展开状态', (WidgetTester tester) async {
    final path = tempFile('c.bin', List<int>.filled(64, 0x41));
    final root = testNode(
      'MP4',
      0,
      64,
      children: <ContainerNode>[
        testNode(
          'moov',
          16,
          48,
          children: <ContainerNode>[testNode('trak', 24, 40)],
        ),
      ],
    );

    await tester.pumpWidget(
      appOf(StructurePane(filePath: path, root: root, resetToken: 0)),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey<String>('structure-toggle-0')));
    await tester.pumpAndSettle();
    expect(find.text('trak'), findsOneWidget);

    // 切到别的标签页：展开状态重置。
    await tester.pumpWidget(
      appOf(StructurePane(filePath: path, root: root, resetToken: 1)),
    );
    await tester.pumpAndSettle();

    expect(find.text('trak'), findsNothing);
  });
}
