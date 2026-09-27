import 'package:flutter/material.dart';
import '../../core/database/db_helper.dart';
import '../../core/services/gallery_order.dart';
import 'folder_thumbnail.dart';
import 'photo_thumbnail.dart';

class CoverPickerSheet extends StatefulWidget {
  final int folderId;
  const CoverPickerSheet({super.key, required this.folderId});

  @override
  State<CoverPickerSheet> createState() => _CoverPickerSheetState();
}

class _CoverPickerSheetState extends State<CoverPickerSheet> {
  final _db = DBHelper.instance;
  List<Map<String, dynamic>> _folders = [];
  List<Map<String, dynamic>> _photos = [];
  List<Map<String, dynamic>> _trail = [];
  String? _currentCover;
  String _targetName = 'carpeta';
  bool _loading = true;
  bool _failed = false;
  bool _saving = false;
  int _request = 0;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    try {
      final target = await _db.getFolder(widget.folderId);
      if (!mounted) return;
      if (target == null) throw StateError('La carpeta ya no existe.');
      _targetName = target['name'] as String;
      _currentCover = target['cover_photo_path'] as String?;
      await _navigate([target]);
    } catch (_) {
      if (mounted) setState(() { _loading = false; _failed = true; });
    }
  }

  Future<void> _navigate(List<Map<String, dynamic>> trail) async {
    if (_saving) return;
    final request = ++_request;
    setState(() {
      _trail = List.of(trail);
      _loading = true;
      _failed = false;
    });
    try {
      final id = trail.isEmpty ? 0 : trail.last['id'] as int;
      // Query only this level. Do not collect all descendant media into memory.
      final results = await Future.wait([
        id == 0 ? _db.getRootFolders() : _db.getSubFolders(id),
        _db.getPhotosByFolder(id),
      ]);
      final folders = List<Map<String, dynamic>>.from(results[0]);
      folders.sort((a, b) => compareGalleryNames(a['name'] as String, b['name'] as String));
      if (!mounted || request != _request) return;
      setState(() {
        _folders = folders;
        _photos = results[1];
        _loading = false;
      });
    } catch (_) {
      if (!mounted || request != _request) return;
      setState(() { _loading = false; _failed = true; });
    }
  }

  Future<void> _saveCover(String path) async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      // The destination is always the original folder, never the browsed folder.
      if (await _db.getFolder(widget.folderId) == null) {
        throw StateError('La carpeta ya no existe.');
      }
      await _db.setCoverPhoto(widget.folderId, path);
      if (!mounted) return;
      setState(() => _saving = false);
      Navigator.pop(context, true);
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se pudo guardar la portada. Intenta de nuevo.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return PopScope(
      canPop: !_saving,
      child: SafeArea(
        top: false,
        child: Container(
          height: MediaQuery.sizeOf(context).height * 0.8,
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20))),
          child: Column(children: [
            Container(width: 40, height: 4,
              margin: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(color: theme.dividerColor,
                borderRadius: BorderRadius.circular(2))),
            Padding(padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(children: [
                Expanded(child: Text('Elegir portada', style: theme.textTheme.titleLarge)),
                if (_currentCover != null && _currentCover!.isNotEmpty)
                  TextButton(onPressed: _saving ? null : () => _saveCover(''),
                    child: const Text('Quitar portada')),
                IconButton(tooltip: 'Cerrar', onPressed: _saving ? null : () => Navigator.pop(context),
                  icon: const Icon(Icons.close)),
              ])),
            Padding(padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Align(alignment: Alignment.centerLeft,
                child: Text('Para: $_targetName', maxLines: 1, overflow: TextOverflow.ellipsis))),
            const SizedBox(height: 8),
            Row(children: [
              IconButton(tooltip: 'Regresar',
                onPressed: _saving || _trail.isEmpty ? null
                    : () => _navigate(_trail.take(_trail.length - 1).toList()),
                icon: const Icon(Icons.arrow_back)),
              IconButton(tooltip: 'Ver todas las carpetas',
                onPressed: _saving ? null : () => _navigate([]),
                icon: const Icon(Icons.home_outlined)),
              Expanded(child: Text(_trail.isEmpty ? 'Home'
                : _trail.map((folder) => folder['name']).join(' / '),
                maxLines: 2, overflow: TextOverflow.ellipsis)),
              const SizedBox(width: 12),
            ]),
            if (_saving) const LinearProgressIndicator(),
            const Divider(height: 1),
            Expanded(child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _failed
                ? Center(child: TextButton.icon(
                    onPressed: _saving ? null : () => _trail.isEmpty && _targetName == 'carpeta'
                      ? _initialize() : _navigate(_trail),
                    icon: const Icon(Icons.refresh), label: const Text('No se pudo cargar. Reintentar')))
                : _folders.isEmpty && _photos.isEmpty
                  ? const Center(child: Padding(padding: EdgeInsets.all(24),
                      child: Text('Esta carpeta está vacía. Regresa o toca Home para elegir otra.',
                        textAlign: TextAlign.center)))
                  : AbsorbPointer(absorbing: _saving,
                      child: GridView.builder(
                        key: ValueKey(_trail.isEmpty ? 0 : _trail.last['id']),
                        padding: const EdgeInsets.all(8),
                        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 4, mainAxisSpacing: 6, crossAxisSpacing: 6,
                          childAspectRatio: 0.85),
                        itemCount: _folders.length + _photos.length,
                        itemBuilder: (_, index) {
                          if (index < _folders.length) {
                            final folder = _folders[index];
                            void open() => _navigate([..._trail, folder]);
                            return FolderThumbnail(key: ValueKey('folder_${folder['id']}'),
                              folder: folder, isSelected: false, showCount: false,
                              onTap: open, onLongPress: null, onMenuTap: (_) => open());
                          }
                          final photo = _photos[index - _folders.length];
                          return PhotoThumbnail(key: ValueKey('photo_${photo['id']}'),
                            photo: photo, isSelected: _currentCover == photo['encrypted_path'],
                            onTap: () => _saveCover(photo['encrypted_path'] as String));
                        },
                      ),
                    ),
            ),
          ]),
        ),
      ),
    );
  }
}