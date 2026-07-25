import 'package:flutter_secure_storage/flutter_secure_storage.dart';

enum GridViewType { grid3, grid4, grid5, grid6, list }

class PrefsService {
  static final PrefsService instance = PrefsService._();
  PrefsService._();

  final _storage = const FlutterSecureStorage();
  static const _keyGrid = 'grid_view_type';

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
}