import 'package:flutter_test/flutter_test.dart';
import '../lib/core/services/gallery_order.dart';

void main() {
  test(
      'Manual order interleaves folders and media, survives reload and appends new files',
      () {
    final folders = [
      {'id': 1, 'manual_order': 1}
    ];
    final photos = [
      {'id': 1, 'manual_order': 0},
      {'id': 2, 'manual_order': 2},
      {'id': 3}
    ];
    expect(galleryItems(folders, photos, manual: true).map(galleryItemKey),
        ['photo:1', 'folder:1', 'photo:2', 'photo:3']);
    expect(galleryItems(folders, photos, manual: false).map(galleryItemKey),
        ['folder:1', 'photo:1', 'photo:2', 'photo:3']);
  });
  test(
      'Moving a group preserves its visible order and distinguishes folder IDs',
      () {
    final items = galleryItems([
      {'id': 1}
    ], [
      {'id': 1},
      {'id': 2},
      {'id': 3}
    ], manual: false);
    final result =
        reorderGalleryItems(items, {3, 1}, false, 'folder:1', after: false);
    expect(result.map(galleryItemKey),
        ['photo:1', 'photo:3', 'folder:1', 'photo:2']);
    expect(items.map(galleryItemKey),
        ['folder:1', 'photo:1', 'photo:2', 'photo:3']);
    expect(
        reorderGalleryItems(items, {1}, true, 'photo:3', after: true)
            .map(galleryItemKey),
        ['photo:1', 'photo:2', 'photo:3', 'folder:1']);
  });
  test('Dropping on own selection or a stale target leaves ordering unchanged',
      () {
    final items = galleryItems([], [
      {'id': 1},
      {'id': 2}
    ], manual: false);
    for (final target in ['photo:1', 'photo:999']) {
      expect(
          reorderGalleryItems(items, {1}, false, target, after: true), items);
    }
  });
  test('Reordering 10000 records keeps every item exactly once', () {
    final items = galleryItems([], List.generate(10000, (id) => {'id': id}),
        manual: false);
    final result = reorderGalleryItems(items, {9998, 9999}, false, 'photo:0',
        after: false);
    expect(result.length, 10000);
    expect(result.map(galleryItemKey).toSet().length, 10000);
    expect(result.take(3).map(galleryItemKey),
        ['photo:9998', 'photo:9999', 'photo:0']);
  });
  test(
      'Folder moves reject self, descendants, missing targets and corrupt cycles',
      () async {
    final parents = <int, int?>{1: null, 2: 1, 3: 2, 4: null, 5: 6, 6: 5};
    Future<int?> parentOf(int id) async {
      if (!parents.containsKey(id)) throw StateError('Missing folder');
      return parents[id];
    }

    for (final destination in [1, 2, 3, 5, 99]) {
      await expectLater(validateFolderDestination({1}, destination, parentOf),
          throwsStateError);
    }
    await validateFolderDestination({1}, 4, parentOf);
    await validateFolderDestination({2, 3}, null, parentOf);
    await expectLater(
        validateFolderDestination({1, 4}, 3, parentOf), throwsStateError);
  });
}
