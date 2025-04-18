import 'dart:convert';
import 'dart:io';

import 'package:collection/collection.dart';
import 'package:gpth/interactive.dart' as interactive;
import 'package:mime/mime.dart';
import 'package:path/path.dart' as p;
import 'package:proper_filesize/proper_filesize.dart';

import 'media.dart';

// remember to bump this
const version = '3.4.3';

/// max file size to read for exif/hash/anything
const maxFileSize = 64 * 1024 * 1024;

/// convenient print for errors
void error(Object? object) => stderr.write('$object\n');

Never quit([int code = 1]) {
  if (interactive.indeed) {
    print('[gpth ${code != 0 ? 'quitted :(' : 'finished :)'} (code $code) - '
        'press enter to close]');
    stdin.readLineSync();
  }
  exit(code);
}

extension X on Iterable<FileSystemEntity> {
  /// Easy extension allowing you to filter for files that are photo or video
  Iterable<File> wherePhotoVideo() => whereType<File>().where((e) {
        final mime = lookupMimeType(e.path) ?? "";
        return mime.startsWith('image/') ||
            mime.startsWith('video/') ||
            // https://github.com/TheLastGimbus/GooglePhotosTakeoutHelper/issues/223
            // https://github.com/dart-lang/mime/issues/102
            // 🙃🙃
            mime == 'model/vnd.mts';
      });
}

extension Y on Stream<FileSystemEntity> {
  /// Easy extension allowing you to filter for files that are photo or video
  Stream<File> wherePhotoVideo() => whereType<File>().where((e) {
        final mime = lookupMimeType(e.path) ?? "";
        return mime.startsWith('image/') ||
            mime.startsWith('video/') ||
            // https://github.com/TheLastGimbus/GooglePhotosTakeoutHelper/issues/223
            // https://github.com/dart-lang/mime/issues/102
            // 🙃🙃
            mime == 'model/vnd.mts';
      });
}

extension Util on Stream {
  Stream<T> whereType<T>() => where((e) => e is T).cast<T>();
}

Future<int?> getDiskFree([String? path]) async {
  path ??= Directory.current.path;
  if (Platform.isLinux) {
    return _dfLinux(path);
  } else if (Platform.isWindows) {
    return _dfWindoza(path);
  } else if (Platform.isMacOS) {
    return _dfMcOS(path);
  } else {
    return null;
  }
}

Future<int?> _dfLinux(String path) async {
  final res = await Process.run('df', ['-B1', '--output=avail', path]);
  return res.exitCode != 0
      ? null
      : int.tryParse(
          res.stdout.toString().split('\n').elementAtOrNull(1) ?? '',
          radix: 10, // to be sure
        );
}

Future<int?> _dfWindoza(String path) async {
  // 使用 wmic 取得指定磁碟的 FreeSpace 值
  final drive = p.rootPrefix(p.absolute(path)).replaceAll('\\', '');
  final res = await Process.run('wmic', [
    'logicaldisk',
    'where',
    "DeviceID='${drive}'",
    'get',
    'FreeSpace',
    '/value',
  ]);
  if (res.exitCode != 0) return null;
  // stdout 例如 "FreeSpace=123456789"
  final line = res.stdout
      .toString()
      .split('\n')
      .firstWhere((l) => l.startsWith('FreeSpace='), orElse: () => '');
  final val = line.split('=') .elementAtOrNull(1) ?? '';
  return int.tryParse(val.trim());
}

Future<int?> _dfMcOS(String path) async {
  final res = await Process.run('df', ['-k', path]);
  if (res.exitCode != 0) return null;
  final line2 = res.stdout.toString().split('\n').elementAtOrNull(1);
  if (line2 == null) return null;
  final elements = line2.split(' ')..removeWhere((e) => e.isEmpty);
  final macSays = int.tryParse(
    elements.elementAtOrNull(3) ?? '',
    radix: 10, // to be sure
  );
  return macSays != null ? macSays * 1024 : null;
}

String filesize(int bytes) => ProperFilesize.generateHumanReadableFilesize(
      bytes,
      base: Bases.Binary,
      decimals: 2,
    );

int outputFileCount(List<Media> media, String albumOption) {
  if (['shortcut', 'duplicate-copy'].contains(albumOption)) {
    return media.fold(0, (prev, e) => prev + e.files.length);
  } else if (albumOption == 'json') {
    return media.length;
  } else if (albumOption == 'nothing') {
    return media.where((e) => e.files.containsKey(null)).length;
  } else {
    throw ArgumentError.value(albumOption, 'albumOption');
  }
}

extension Z on String {
  /// Returns same string if pattern not found
  String replaceLast(String from, String to) {
    final lastIndex = lastIndexOf(from);
    if (lastIndex == -1) return this;
    return replaceRange(lastIndex, lastIndex + from.length, to);
  }
}

/// 同步讀取檔案前 N 個位元組
List<int> readFirstNBytesSync(File file, int count) {
  final raf = file.openSync();
  final bytes = raf.readSync(count);
  raf.closeSync();
  return bytes;
}

/// 混合檔案大小與前 N 位元組進行 SHA256，區分大檔案
Digest hashPartialSync(File file) {
  const sampleSize = 1024 * 1024; // 1 MiB
  final firstBytes = readFirstNBytesSync(file, sampleSize);
  final sizeSeed = utf8.encode(file.lengthSync().toString());
  return sha256.convert([...sizeSeed, ...firstBytes]);
}
