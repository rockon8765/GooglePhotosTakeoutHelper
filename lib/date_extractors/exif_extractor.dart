import 'dart:io';

import 'package:exif/exif.dart';
import 'package:gpth/utils.dart';
import 'package:mime/mime.dart';

/// DateTime from exif data *potentially* hidden within a [file]
///
/// You can try this with *any* file, it either works or not 🤷
Future<DateTime?> exifExtractor(File file) async {
  if (!(lookupMimeType(file.path)?.startsWith('image/') ?? false) ||
      await file.length() > maxFileSize) {
    return null;
  }
  try {
    final bytes = await file.readAsBytes();
    final tags = await readExifFromBytes(bytes);
    String? datetime;
    datetime ??= tags['Image DateTime']?.printable;
    datetime ??= tags['EXIF DateTimeOriginal']?.printable;
    datetime ??= tags['EXIF DateTimeDigitized']?.printable;
    if (datetime == null) return null;
    final match = RegExp(r'^(\d{4}):(\d{2}):(\d{2})\s+(\d{2}):(\d{2}):(\d{2})')
        .firstMatch(datetime);
    if (match != null) {
      try {
        final year = int.parse(match.group(1)!);
        final month = int.parse(match.group(2)!);
        final day = int.parse(match.group(3)!);
        final hour = int.parse(match.group(4)!);
        final minute = int.parse(match.group(5)!);
        final second = int.parse(match.group(6)!);
        
        // 驗證日期值是否在合理範圍內
        if (year < 1800 || year > 2100 || 
            month < 1 || month > 12 || 
            day < 1 || day > 31 || 
            hour < 0 || hour > 23 || 
            minute < 0 || minute > 59 || 
            second < 0 || second > 59) {
          print('檔案 ${file.path} 的 EXIF 日期數值超出範圍: $datetime');
          return null;
        }
        
        // 額外檢查特定月份的天數
        if ((month == 4 || month == 6 || month == 9 || month == 11) && day > 30) {
          print('檔案 ${file.path} 的 EXIF 日期不正確: $month 月不可能有 $day 天');
          return null;
        }
        // 處理二月特殊情況
        if (month == 2) {
          final isLeapYear = (year % 4 == 0 && year % 100 != 0) || (year % 400 == 0);
          if ((isLeapYear && day > 29) || (!isLeapYear && day > 28)) {
            print('檔案 ${file.path} 的 EXIF 日期不正確: ${isLeapYear ? "閏" : "平"}年二月不可能有 $day 天');
            return null;
          }
        }
        
        return DateTime(year, month, day, hour, minute, second);
      } catch (e) {
        print('解析 EXIF 日期時出錯: $e');
        return null;
      }
    }
    return null;
  } catch (e) {
    // 跳過無效或壞掉的 EXIF 資訊
    return null;
  }
}
