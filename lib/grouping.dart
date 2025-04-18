/// This files contains functions for removing duplicates and detecting albums
///
/// That's because their logic looks very similar and they share code

import 'dart:io';

import 'package:collection/collection.dart';
import 'package:gpth/media.dart';
import 'package:path/path.dart' as p;

extension Group on Iterable<Media> {
  /// This groups your media into map where key is something that they share
  /// and value is the List of those media are the same
  ///
  /// Key may be "245820998bytes", where there was no other file same size
  /// (no need to calculate hash), or hash.toSting'ed where hash was calculated
  ///
  /// Groups may be 1-lenght, where element was unique, or n-lenght where there
  /// were duplicates
  Map<String, List<Media>> groupIdentical() {
    final output = <String, List<Media>>{};
    // group files by size - can't have same hash with diff size
    // ignore: unnecessary_this
    for (final sameSize in this.groupListsBy((e) => e.size).entries) {
      // just add with "...bytes" key if just one
      if (sameSize.value.length <= 1) {
        output['${sameSize.key}bytes'] = sameSize.value;
      } else {
        // ...calculate their full hashes and group by them
        output.addAll(sameSize.value.groupListsBy((e) => e.hash.toString()));
      }
    }
    return output;
  }
}

/// Removes duplicate media from list of media
///
/// This is meant to be used *early*, and it's aware of un-merged albums.
/// Meaning, it will leave duplicated files if they have different
/// [Media.albums] value
///
/// Uses file size, then sha256 hash to distinct
///
/// Returns count of removed
int removeDuplicates(List<Media> media) {
  var count = 0;
  final byAlbum = media
      .groupListsBy((e) => e.files.keys.first)
      .values
      .map((albumGroup) => albumGroup.groupIdentical().values);
  final Iterable<List<Media>> hashGroups = byAlbum.flattened;
  for (final group in hashGroups) {
    // sort by best date extraction, then file name length
    // using strings to sort by two values is a sneaky trick i learned at
    // https://stackoverflow.com/questions/55920677/how-to-sort-a-list-based-on-two-values

    // note: we are comparing accuracy here tho we do know that *all*
    // of them have it null - i'm leaving this just for sake
    group.sort((a, b) {
      final diff = (a.dateTakenAccuracy ?? 999) - (b.dateTakenAccuracy ?? 999);
      if (diff != 0) return diff;
      return p.basename(a.firstFile.path).length - p.basename(b.firstFile.path).length;
    });
    // get list of all except first
    for (final e in group.sublist(1)) {
      // remove them from media
      media.remove(e);
      count++;
    }
  }

  return count;
}

String albumName(Directory albumDir) => p.basename(albumDir.path);

/// This will analyze [allMedia], find which files are hash-same, and merge
/// all of them into single [Media] object with all album names they had
void findAlbums(List<Media> allMedia) {
  // 先收集要移除與新增的 media
  final toRemove = <Media>[];
  final toAdd = <Media>[];
  for (final group in allMedia.groupIdentical().values) {
    if (group.length <= 1) continue;
    // 合併所有檔案路徑
    final mergedFiles = group.fold<Map<String?, File>>(
      <String?, File>{},
      (map, m) => map..addAll(m.files),
    );
    // 依準確度與檔名長度排序，選最好的代表
    group.sort((a, b) {
      final diff = (a.dateTakenAccuracy ?? 999) - (b.dateTakenAccuracy ?? 999);
      if (diff != 0) return diff;
      return p.basename(a.firstFile.path).length - p.basename(b.firstFile.path).length;
    });
    final best = group.first;
    best.files = mergedFiles;
    toRemove.addAll(group);
    toAdd.add(best);
  }
  // 一次性更新列表，避免迴圈內 mutate
  allMedia.removeWhere((m) => toRemove.contains(m));
  allMedia.addAll(toAdd);
}
