/// Lightweight ordering metadata only; no media files are opened.
List<Map<String, dynamic>> galleryItems(
    List<Map<String, dynamic>> folders, List<Map<String, dynamic>> photos,
    {required bool manual}) {
  final items = <Map<String, dynamic>>[
    ...folders.map((data) => <String, dynamic>{'type': 'folder', 'data': data}),
    ...photos.map((data) => <String, dynamic>{'type': 'photo', 'data': data}),
  ];
  if (manual) {
    // Stable fallback for new or restored items without a saved position.
    final original = {
      for (var i = 0; i < items.length; i++) galleryItemKey(items[i]): i
    };
    items.sort((a, b) {
      final ar = a['data']['manual_order'] as num?;
      final br = b['data']['manual_order'] as num?;
      if (ar != null && br != null && ar != br) return ar.compareTo(br);
      if (ar != null && br == null) return -1;
      if (ar == null && br != null) return 1;
      return original[galleryItemKey(a)]!
          .compareTo(original[galleryItemKey(b)]!);
    });
  }
  return items;
}

String galleryItemKey(Map<String, dynamic> item) =>
    '${item['type']}:${item['data']['id']}';

List<Map<String, dynamic>> reorderGalleryItems(List<Map<String, dynamic>> items,
    Set<int> ids, bool folders, String targetKey,
    {required bool after}) {
  final type = folders ? 'folder' : 'photo';
  bool selected(Map<String, dynamic> item) =>
      item['type'] == type && ids.contains(item['data']['id']);
  final target = items.indexWhere((item) => galleryItemKey(item) == targetKey);
  if (target < 0 || selected(items[target])) return List.of(items);
  final moving = items.where(selected).toList();
  final result = items.where((item) => !selected(item)).toList();
  final index = result.indexWhere((item) => galleryItemKey(item) == targetKey);
  result.insertAll(index + (after ? 1 : 0), moving);
  return result;
}

/// Validate ancestors before any write, including corrupt pre-existing cycles.
Future<void> validateFolderDestination(Set<int> movingIds, int? destination,
    Future<int?> Function(int id) parentOf) async {
  var ancestor = destination;
  final visited = <int>{};
  while (ancestor != null) {
    if (movingIds.contains(ancestor) || !visited.add(ancestor)) {
      throw StateError('Una carpeta no puede contenerse a sí misma.');
    }
    ancestor = await parentOf(ancestor);
  }
}

/// Spanish-friendly ascending names: letters, then digits, then symbols.
int compareGalleryNames(String left, String right) {
  final a = left.trim().toLowerCase();
  final b = right.trim().toLowerCase();
  int group(String name) {
    if (RegExp(r'^[a-z\u00c0-\u02af]').hasMatch(name)) return 0;
    if (RegExp(r'^[0-9]').hasMatch(name)) return 1;
    return 2;
  }
  String normalized(String name) {
    const accents = {'á': 'a', 'à': 'a', 'ä': 'a', 'â': 'a',
      'é': 'e', 'è': 'e', 'ë': 'e', 'ê': 'e',
      'í': 'i', 'ì': 'i', 'ï': 'i', 'î': 'i',
      'ó': 'o', 'ò': 'o', 'ö': 'o', 'ô': 'o',
      'ú': 'u', 'ù': 'u', 'ü': 'u', 'û': 'u', 'ñ': 'n~'};
    return name.split('').map((letter) => accents[letter] ?? letter).join();
  }
  final category = group(a).compareTo(group(b));
  if (category != 0) return category;
  final name = normalized(a).compareTo(normalized(b));
  return name != 0 ? name : a.compareTo(b);
}
/// Insert into the target's old position; intervening items shift, never swap.
List<Map<String, dynamic>> placeGalleryItemsAtTarget(
    List<Map<String, dynamic>> items, Set<int> ids, bool folders, String targetKey) {
  final type = folders ? 'folder' : 'photo';
  bool selected(Map<String, dynamic> item) =>
      item['type'] == type && ids.contains(item['data']['id']);
  final target = items.indexWhere((item) => galleryItemKey(item) == targetKey);
  if (target < 0 || selected(items[target])) return List.of(items);
  final moving = items.where(selected).toList();
  if (moving.isEmpty) return List.of(items);
  final remaining = items.where((item) => !selected(item)).toList();
  final destination = target > remaining.length ? remaining.length : target;
  remaining.insertAll(destination, moving);
  return remaining;
}