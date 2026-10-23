/// 解析层的错误类型。
library;

/// 读到的字节少于声明长度。
class TruncatedFile implements Exception {
  TruncatedFile(this.offset, this.missingBytes);

  /// 期望读到数据的位置（字节偏移）。
  final int offset;

  /// 还差多少字节。
  final int missingBytes;

  @override
  String toString() =>
      'TruncatedFile(offset: $offset, missingBytes: $missingBytes)';
}
