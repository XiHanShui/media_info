import 'dart:io';
import 'dart:typed_data';

import 'errors.dart';

/// 随机访问的字节源。大文件不整体读入内存。
abstract interface class ByteSource {
  /// 文件总长度（字节）。
  int get length;

  /// 从 [offset] 起读 [length] 个字节；超出文件末尾则抛 [TruncatedFile]。
  Uint8List read(int offset, int length);
}

/// 文件实现。基于 [RandomAccessFile] 随机访问，绝不整体读入内存。
class FileByteSource implements ByteSource {
  /// 打开 [file] 并按随机访问方式读取。
  FileByteSource(this.file) : _handle = file.openSync();

  /// 按路径打开文件。
  factory FileByteSource.fromPath(String path) => FileByteSource(File(path));

  /// 底层文件。
  final File file;

  final RandomAccessFile _handle;

  @override
  int get length => _handle.lengthSync();

  @override
  Uint8List read(int offset, int length) {
    if (offset < 0 || length < 0) {
      throw ArgumentError('offset 与 length 必须非负：offset=$offset length=$length');
    }
    if (length == 0) return Uint8List(0);
    final total = _handle.lengthSync();
    if (offset + length > total) {
      throw TruncatedFile(offset, offset + length - total);
    }
    _handle.setPositionSync(offset);
    return _handle.readSync(length);
  }

  /// 关闭底层文件句柄。
  void close() => _handle.closeSync();
}
