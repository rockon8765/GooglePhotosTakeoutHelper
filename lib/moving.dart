/// This file contains logic/utils for final act of moving actual files once
/// we have everything grouped, de-duplicated and sorted

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:collection/collection.dart';
import 'package:gpth/interactive.dart' as interactive;
import 'package:gpth/utils.dart';
import 'package:path/path.dart' as p;

import 'media.dart';

/// This will add (1) add end of file name over and over until file with such
/// name doesn't exist yet. Will leave without "(1)" if is free already
File findNotExistingName(File initialFile) {
  if (!initialFile.existsSync()) return initialFile;
  final dir = initialFile.parent;
  final base = p.basenameWithoutExtension(initialFile.path);
  final ext = p.extension(initialFile.path);
  var counter = 1;
  File candidate;
  do {
    candidate = File(p.join(dir.path, '$base($counter)$ext'));
    counter++;
  } while (candidate.existsSync());
  return candidate;
}

/// This will create symlink on unix and shortcut on windoza
///
/// Uses [findNotExistingName] for safety
Future<File> createShortcut(Directory location, File target) async {
  final name = '${p.basename(target.path)}${Platform.isWindows ? '.lnk' : ''}';
  final link = findNotExistingName(File(p.join(location.path, name)));
  // this must be relative to not break when user moves whole folder around:
  // https://github.com/TheLastGimbus/GooglePhotosTakeoutHelper/issues/232
  final targetRelativePath = p.relative(target.path, from: link.parent.path);

  if (Platform.isWindows) {
    // Escape single quotes in paths for PowerShell
    final escapedLinkPath = link.path.replaceAll("'", "''");
    final escapedTargetPath = targetRelativePath.replaceAll("'", "''");

    // Construct the PowerShell command
    final psCommand = """
\\\$ws = New-Object -ComObject WScript.Shell;
\\\$s = \\\$ws.CreateShortcut('$escapedLinkPath');
\\\$s.TargetPath = '$escapedTargetPath';
\\\$s.Save()
"""; // Use triple quotes for multi-line string and escape $
    // Encode the command in UTF-8 and then Base64
    final encodedCommand = base64.encode(utf8.encode(psCommand));

    // Run PowerShell with the encoded command
    final res = await Process.run(
      'powershell.exe',
      [
        '-NoProfile',
        '-NonInteractive',
        '-ExecutionPolicy',
        'Bypass', // Attempt to bypass execution policy restrictions
        '-EncodedCommand',
        encodedCommand,
      ],
    );

    if (res.exitCode != 0) {
      // Provide more detailed error information
      throw '建立捷徑失敗: PowerShell 執行錯誤 (Exit Code: ${res.exitCode}).\\n'
          '請檢查您的權限或系統設定。\\n'
          '錯誤輸出 (stderr):\\n${res.stderr}\\n'
          '標準輸出 (stdout):\\n${res.stdout}\\n\\n'
          '您可以嘗試回報此問題至:\\n'
          'https://github.com/TheLastGimbus/GooglePhotosTakeoutHelper/issues\\n\\n'
          '或嘗試使用其他相簿處理方式 (例如 "duplicate-copy")。';
    }
    return File(link.path);
  } else {
    // Unix-like systems: Create a symbolic link
    try {
      await Link(link.path).create(targetRelativePath);
      return File(link.path);
    } catch (e) {
      // Provide error context for symlink creation failure
      throw '建立符號連結失敗: $e\\n'
          '目標: $targetRelativePath\\n'
          '連結位置: ${link.path}';
    }
  }
}

/// 移動或複製檔案的功能
Stream<void> moveFiles(
  List<Media> mediaList,
  Directory output, {
  bool copy = false,
  bool divideToDates = false,
  String albumBehavior = 'shortcut',
}) async* {
  for (final m in mediaList) {
    final date = m.dateTaken;
    // 決定輸出目錄
    Directory destDir;
    if (date != null && divideToDates) {
      final y = date.year.toString();
      final mth = date.month.toString().padLeft(2, '0');
      destDir = Directory(p.join(output.path, y, mth));
    } else if (date == null) {
      destDir = Directory(p.join(output.path, 'date-unknown'));
    } else {
      destDir = output;
    }
    if (!destDir.existsSync()) destDir.createSync(recursive: true);
    final src = m.files[null] ?? m.firstFile;
    final destFile = File(p.join(destDir.path, p.basename(src.path)));
    final target = findNotExistingName(destFile);
    if (copy) {
      src.copySync(target.path);
    } else {
      src.renameSync(target.path);
    }
    yield null;
    if (['shortcut', 'duplicate-copy'].contains(albumBehavior)) {
      for (final entry in m.files.entries) {
        final alb = entry.key;
        final file = entry.value;
        if (alb == null) continue;
        final albDir = Directory(p.join(output.path, 'albums', alb));
        if (!albDir.existsSync()) albDir.createSync(recursive: true);
        if (albumBehavior == 'duplicate-copy') {
          file.copySync(p.join(albDir.path, p.basename(file.path)));
        } else {
          // shortcut
          await createShortcut(albDir, file);
        }
      }
    }
  }
}
