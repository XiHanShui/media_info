import 'node.dart';

/// 从已解析的树里取语义字段。不重复解析字节。
typedef LeafExtractor = List<SemanticField> Function(ContainerNode root);
