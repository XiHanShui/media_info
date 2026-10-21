import 'dart:typed_data';

import 'package:media_info/src/core/byte_source.dart';
import 'package:media_info/src/core/errors.dart';

/// 测试用的内存字节源：喂进去的字节就是文件内容。
class MemoryByteSource implements ByteSource {
  MemoryByteSource(this.bytes);

  /// 由字节列表构造。
  factory MemoryByteSource.of(List<int> values) =>
      MemoryByteSource(Uint8List.fromList(values));

  /// 文件内容。
  final Uint8List bytes;

  @override
  int get length => bytes.length;

  @override
  Uint8List read(int offset, int length) {
    if (offset < 0 || length < 0 || offset + length > bytes.length) {
      throw TruncatedFile(offset, offset + length - bytes.length);
    }
    return Uint8List.fromList(bytes.sublist(offset, offset + length));
  }
}
