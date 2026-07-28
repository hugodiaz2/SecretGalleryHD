import 'package:flutter_secure_storage/flutter_secure_storage.dart';

enum GridViewType { grid3, grid4, grid5, grid6, list }

class PrefsService {
  static final PrefsService instance = PrefsService._();
  PrefsService._();

  final _storage = const FlutterSecureStorage();

  // Keys
  static const _keyGrid = 'grid_view_type';
  static const _keySort = 'sort_type';
  static const _keyNarrowBorders = 'narrow_borders';
  static const _keyShowPhotoPreview = 'show_photo_preview';
  static const _keyShowFolderPreview = 'show_folder_preview';
  static const _keyCloseOnMinimize = 'close_on_minimize';
  static const _keyShakeToClose = 'shake_to_close';
  static const _keyIntruderSelfie = 'intruder_selfie';
  static const _keyPreventScreenshot = 'prevent_screenshot';
  static const _keyKeepScreenOn = 'keep_screen_on';
  static const _keyMaxBrightness = 'max_brightness';
  static const _keyMaximizeImages = 'maximize_images';
  static const _keyNoTrash = 'no_trash';
  static const _keyDarkMode = 'dark_mode';

  // ── Grid ────────────────────────────────────────────────
  Future<GridViewType> getGridType() async {
    final val = await _storage.read(key: _keyGrid);
    return GridViewType.values.firstWhere(
      (e) => e.name == val,
      orElse: () => GridViewType.grid3,
    );
  }

  Future<void> saveGridType(GridViewType type) async {
    await _storage.write(key: _keyGrid, value: type.name);
  }

  // ── Sort ────────────────────────────────────────────────
  Future<String> getSort() async {
    return await _storage.read(key: _keySort) ?? 'newest';
  }

  Future<void> saveSort(String sort) async {
    await _storage.write(key: _keySort, value: sort);
  }

  // ── Booleans ────────────────────────────────────────────
  Future<bool> _getBool(String key, {bool defaultValue = false}) async {
    final val = await _storage.read(key: key);
    if (val == null) return defaultValue;
    return val == 'true';
  }

  Future<void> _setBool(String key, bool value) async {
    await _storage.write(key: key, value: value.toString());
  }

  Future<bool> getNarrowBorders() => _getBool(_keyNarrowBorders);
  Future<void> saveNarrowBorders(bool v) => _setBool(_keyNarrowBorders, v);

  Future<bool> getShowPhotoPreview() =>
      _getBool(_keyShowPhotoPreview, defaultValue: true);
  Future<void> saveShowPhotoPreview(bool v) =>
      _setBool(_keyShowPhotoPreview, v);

  Future<bool> getShowFolderPreview() =>
      _getBool(_keyShowFolderPreview, defaultValue: true);
  Future<void> saveShowFolderPreview(bool v) =>
      _setBool(_keyShowFolderPreview, v);

  Future<bool> getCloseOnMinimize() => _getBool(_keyCloseOnMinimize);
  Future<void> saveCloseOnMinimize(bool v) =>
      _setBool(_keyCloseOnMinimize, v);

  Future<bool> getShakeToClose() => _getBool(_keyShakeToClose);
  Future<void> saveShakeToClose(bool v) => _setBool(_keyShakeToClose, v);

  Future<bool> getIntruderSelfie() => _getBool(_keyIntruderSelfie);
  Future<void> saveIntruderSelfie(bool v) =>
      _setBool(_keyIntruderSelfie, v);

  Future<bool> getPreventScreenshot() =>
      _getBool(_keyPreventScreenshot, defaultValue: true);
  Future<void> savePreventScreenshot(bool v) =>
      _setBool(_keyPreventScreenshot, v);

  Future<bool> getKeepScreenOn() => _getBool(_keyKeepScreenOn);
  Future<void> saveKeepScreenOn(bool v) => _setBool(_keyKeepScreenOn, v);

  Future<bool> getMaxBrightness() => _getBool(_keyMaxBrightness);
  Future<void> saveMaxBrightness(bool v) => _setBool(_keyMaxBrightness, v);

  Future<bool> getMaximizeImages() => _getBool(_keyMaximizeImages);
  Future<void> saveMaximizeImages(bool v) =>
      _setBool(_keyMaximizeImages, v);

  Future<bool> getNoTrash() => _getBool(_keyNoTrash);
  Future<void> saveNoTrash(bool v) => _setBool(_keyNoTrash, v);

  Future<bool> getDarkMode() =>
      _getBool(_keyDarkMode, defaultValue: true);
  Future<void> saveDarkMode(bool v) => _setBool(_keyDarkMode, v);

  // ── Cargar todos de una vez ──────────────────────────────
  Future<Map<String, dynamic>> loadAll() async {
    return {
      'gridType': await getGridType(),
      'sort': await getSort(),
      'narrowBorders': await getNarrowBorders(),
      'showPhotoPreview': await getShowPhotoPreview(),
      'showFolderPreview': await getShowFolderPreview(),
      'closeOnMinimize': await getCloseOnMinimize(),
      'shakeToClose': await getShakeToClose(),
      'intruderSelfie': await getIntruderSelfie(),
      'preventScreenshot': await getPreventScreenshot(),
      'keepScreenOn': await getKeepScreenOn(),
      'maxBrightness': await getMaxBrightness(),
      'maximizeImages': await getMaximizeImages(),
      'noTrash': await getNoTrash(),
      'darkMode': await getDarkMode(),
    };
  }
}