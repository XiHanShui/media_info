/// 胶片条（`FileStrip`）的行为测试。
///
/// 胶片条是本工具的签名元素：一条横带上，顶层块按各自长度**按比例**排开，
/// 段的位置就是块在文件里的真实位置，媒体载荷与元数据用不同的颜色区分，
/// 当前选中的块被高亮。
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_info/src/app/file_strip.dart';
import 'package:media_info/src/app/theme.dart';
import 'package:media_info/src/core/node.dart';

/// 顶层块 `ftyp`（100 字节）。
const ContainerNode kFtyp = ContainerNode(
  type: 'ftyp',
  offset: 0,
  size: 100,
  dataOffset: 8,
  dataSize: 92,
);

/// 顶层块 `moov`（200 字节）。
const ContainerNode kMoov = ContainerNode(
  type: 'moov',
  offset: 100,
  size: 200,
  dataOffset: 108,
  dataSize: 192,
);

/// 顶层块 `mdat`（700 字节）——媒体载荷。
const ContainerNode kMdat = ContainerNode(
  type: 'mdat',
  offset: 300,
  size: 700,
  dataOffset: 308,
  dataSize: 692,
);

/// `moov` 里的一块（用来验证"选中嵌套块"）。
const ContainerNode kTrak = ContainerNode(
  type: 'trak',
  offset: 108,
  size: 180,
  dataOffset: 116,
  dataSize: 172,
);

/// 整棵树：ftyp(100) + moov(200) + mdat(700) = 1000 字节。
const ContainerNode kRoot = ContainerNode(
  type: 'MP4',
  offset: 0,
  size: 1000,
  dataOffset: 0,
  dataSize: 1000,
  children: <ContainerNode>[kFtyp, kMoov, kMdat],
);

/// 启动胶片条。
Future<void> _pumpStrip(
  WidgetTester tester, {
  ContainerNode? selected,
  ContainerNode root = kRoot,
}) async {
  tester.view.physicalSize = const Size(1200, 800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 1200,
            child: FileStrip(root: root, selected: selected),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// 某一段（用悬停提示定位：提示里有类型、偏移与长度）。
Finder _segment(String type) => find.descendant(
  of: find.byTooltip(RegExp('^$type\\s')),
  matching: find.byType(DecoratedBox),
);

/// 某一段的填充色。
Color _fillOf(WidgetTester tester, Finder segment) {
  final decoration =
      tester.widget<DecoratedBox>(segment).decoration as BoxDecoration;
  return decoration.color!;
}

/// 某一段的描边色。
Color? _borderOf(WidgetTester tester, Finder segment) {
  final decoration =
      tester.widget<DecoratedBox>(segment).decoration as BoxDecoration;
  final border = decoration.border as Border;
  return border.top.color;
}

void main() {
  testWidgets('顶层块按各自长度在横带上按比例排开', (WidgetTester tester) async {
    await _pumpStrip(tester);

    final ftyp = tester.getSize(_segment('ftyp')).width;
    final moov = tester.getSize(_segment('moov')).width;
    final mdat = tester.getSize(_segment('mdat')).width;

    // 宽度比 = 长度比（100 : 200 : 700）。
    expect(moov / ftyp, closeTo(2.0, 0.05));
    expect(mdat / moov, closeTo(3.5, 0.05));
  });

  testWidgets('段的位置按块在文件里的真实位置排开', (WidgetTester tester) async {
    await _pumpStrip(tester);

    final leftFtyp = tester.getTopLeft(_segment('ftyp')).dx;
    final leftMoov = tester.getTopLeft(_segment('moov')).dx;
    final leftMdat = tester.getTopLeft(_segment('mdat')).dx;

    // 从左到右按文件里的先后顺序。
    expect(leftFtyp, lessThan(leftMoov));
    expect(leftMoov, lessThan(leftMdat));

    // 位置按**累计偏移**算：moov 前面有 100 字节，mdat 前面有 300 字节。
    expect(
      (leftMoov - leftFtyp) / (leftMdat - leftMoov),
      closeTo(100 / 200, 0.05),
    );
  });

  testWidgets('媒体载荷段与元数据段配色不同', (WidgetTester tester) async {
    await _pumpStrip(tester);

    // 琥珀 = 媒体载荷，青 = 元数据与结构。
    expect(_fillOf(tester, _segment('mdat')), MediaColors.amberDeep);
    expect(_fillOf(tester, _segment('moov')), MediaColors.tealDeep);
    expect(_fillOf(tester, _segment('ftyp')), MediaColors.tealDeep);
  });

  testWidgets('选中的段被高亮，其它段不受影响', (WidgetTester tester) async {
    await _pumpStrip(tester, selected: kMoov);

    // 选中的那一段被提亮、并改成琥珀描边。
    final selected = _fillOf(tester, _segment('moov'));
    expect(selected, isNot(MediaColors.tealDeep));
    expect(selected.r, greaterThan(MediaColors.tealDeep.r));
    expect(_borderOf(tester, _segment('moov')), MediaColors.amber);

    // 其它段不动。
    expect(_fillOf(tester, _segment('mdat')), MediaColors.amberDeep);
    expect(_fillOf(tester, _segment('ftyp')), MediaColors.tealDeep);
  });

  testWidgets('悬停提示里有类型、偏移与长度', (WidgetTester tester) async {
    await _pumpStrip(tester);

    expect(find.byTooltip(RegExp('偏移 300')), findsOneWidget);
    expect(find.byTooltip(RegExp('长度 700')), findsOneWidget);
    expect(find.byTooltip(RegExp('^mdat\\s')), findsOneWidget);
  });

  // 已知缺陷：`FileStrip._parentOf` 从目标节点**往下**找父节点，永远找不到
  // 真正的父节点，所以选中嵌套块时，所在的顶层段不会高亮。
  // 缺陷修好前先跳过这条——它描述的是应有行为。
  testWidgets('选中嵌套在某个顶层块里的块时，所在的顶层段也该被高亮', (WidgetTester tester) async {
    await _pumpStrip(
      tester,
      selected: kTrak,
      root: ContainerNode(
        type: 'MP4',
        offset: 0,
        size: 1000,
        dataOffset: 0,
        dataSize: 1000,
        children: <ContainerNode>[
          kFtyp,
          ContainerNode(
            type: 'moov',
            offset: 100,
            size: 200,
            dataOffset: 108,
            dataSize: 192,
            children: <ContainerNode>[kTrak],
          ),
          kMdat,
        ],
      ),
    );

    // 选了 `moov` 里的 `trak` → `moov` 那一段应该被高亮。
    expect(_fillOf(tester, _segment('moov')), isNot(MediaColors.tealDeep));
  });
}
