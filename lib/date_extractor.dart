import 'dart:io';

import 'date_extractors/exif_extractor.dart';
import 'date_extractors/guess_extractor.dart';
import 'date_extractors/json_extractor.dart';

export 'date_extractors/exif_extractor.dart';
export 'date_extractors/guess_extractor.dart';
export 'date_extractors/json_extractor.dart';

/// Function that can take a file and potentially extract DateTime of it
typedef DateTimeExtractor = Future<DateTime?> Function(File);

/// 全域可用的日期擷取器清單，按準確度由高到低
final List<DateTimeExtractor> dateExtractors = [
  jsonExtractor,
  exifExtractor,
  guessExtractor,
];
