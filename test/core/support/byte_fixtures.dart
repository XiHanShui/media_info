/// 构造最小字节序列的辅助函数（核心层测试不依赖任何格式表）。
library;

import 'dart:convert' as convert;

/// 字节列表。
List<int> bytes(List<int> values) => List<int>.from(values);

/// ASCII 字符串的字节。
List<int> ascii(String text) => text.codeUnits;

/// UTF-8 字符串的字节。
List<int> utf8(String text) => convert.utf8.encode(text);

/// 1 字节。
List<int> u8(int value) => [value & 0xFF];

/// 大端 16 位。
List<int> u16be(int value) => [(value >> 8) & 0xFF, value & 0xFF];

/// 大端 24 位。
List<int> u24be(int value) => [
  (value >> 16) & 0xFF,
  (value >> 8) & 0xFF,
  value & 0xFF,
];

/// 大端 32 位。
List<int> u32be(int value) => [
  (value >> 24) & 0xFF,
  (value >> 16) & 0xFF,
  (value >> 8) & 0xFF,
  value & 0xFF,
];

/// 大端 64 位。
List<int> u64be(int value) => [
  (value >> 56) & 0xFF,
  (value >> 48) & 0xFF,
  (value >> 40) & 0xFF,
  (value >> 32) & 0xFF,
  (value >> 24) & 0xFF,
  (value >> 16) & 0xFF,
  (value >> 8) & 0xFF,
  value & 0xFF,
];

/// 小端 16 位。
List<int> u16le(int value) => [value & 0xFF, (value >> 8) & 0xFF];

/// 小端 32 位。
List<int> u32le(int value) => [
  value & 0xFF,
  (value >> 8) & 0xFF,
  (value >> 16) & 0xFF,
  (value >> 24) & 0xFF,
];

/// 小端 64 位。
List<int> u64le(int value) => [
  value & 0xFF,
  (value >> 8) & 0xFF,
  (value >> 16) & 0xFF,
  (value >> 24) & 0xFF,
  (value >> 32) & 0xFF,
  (value >> 40) & 0xFF,
  (value >> 48) & 0xFF,
  (value >> 56) & 0xFF,
];

/// 拼接多段字节。
List<int> concat(List<List<int>> parts) => [for (final part in parts) ...part];
