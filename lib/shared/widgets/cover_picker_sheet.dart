import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/database/db_helper.dart';
import '../../core/services/media_service.dart';

class CoverPickerSheet extends StatefulWidget {
  final int folderId;

  const CoverPickerSheet({super.key, required this.folderId});

  @override
  State<CoverPickerSheet> createState() => _CoverPickerSheetState();
}

class _CoverPickerSheetState extends State<CoverPickerSheet> {
  List<Map<String, dynamic>> _photos = [];
  String? _currentCover;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    // Fotos de esta carpeta y subcarpetas
    final photos = await _getAllPhotos(widget.folderId);
    final cover = await DBHelper.instance.getCoverPhoto(widget.folderId);
    setState(() {
      _photos = photos;
      _currentCover = cover;
      _loading = false;
    });
  }

  Future<List<Map<String, dynamic>>> _getAllPhotos(int folderId) async {
    final db = DBHelper.instance;
    final photos = await db.getPhotosByFolder(folderId);
    final subs = await db.getSubFolders(folderId);
    for (final sub in subs) {
      photos.addAll(await _getAllPhotos(sub['id'] as int));
    }
    return photos;
  }

  Future<void> _selectCover(Map<String, dynamic> photo) async {
    await DBHelper.instance.setCoverPhoto(
        widget.folderId, photo['encrypted_path'] as String);
    if (mounted) Navigator.pop(context, true);
  }

  Future<void> _removeCover() async {
    await DBHelper.instance.setCoverPhoto(widget.folderId, '');
    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.75,
      decoration: const BoxDecoration(
        color: Color(0xFF1A1A1A),
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          Container(
            width: 40,
            height: 4,
            margin: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2)),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Elegir portada',
                    style: GoogleFonts.poppins(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w600)),
                if (_currentCover != null && _currentCover!.isNotEmpty)
                  TextButton(
                    onPressed: _removeCover,
                    child: Text('Quitar portada',
                        style: GoogleFonts.poppins(
                            color: Colors.redAccent, fontSize: 12)),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          const Divider(color: Colors.white12),
          _loading
              ? const Expanded(
                  child: Center(
                      child: CircularProgressIndicator(color: Colors.blue)))
              : _photos.isEmpty
                  ? Expanded(
                      child: Center(
                        child: Text('Sin fotos disponibles',
                            style: GoogleFonts.poppins(
                                color: Colors.white38)),
                      ),
                    )
                  : Expanded(
                      child: GridView.builder(
                        padding: const EdgeInsets.all(8),
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 3,
                          mainAxisSpacing: 4,
                          crossAxisSpacing: 4,
                        ),
                        itemCount: _photos.length,
                        itemBuilder: (_, i) {
                          final photo = _photos[i];
                          final isCurrentCover = _currentCover ==
                              photo['encrypted_path'];

                          return GestureDetector(
                            onTap: () => _selectCover(photo),
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                _PhotoThumb(photo: photo),
                                if (isCurrentCover)
                                  Container(
                                    color: Colors.blue.withOpacity(0.4),
                                    child: const Center(
                                      child: Icon(Icons.check_circle,
                                          color: Colors.white, size: 32),
                                    ),
                                  ),
                                Positioned(
                                  top: 4,
                                  right: 4,
                                  child: Container(
                                    width: 22,
                                    height: 22,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: isCurrentCover
                                          ? Colors.blue
                                          : Colors.black45,
                                      border: Border.all(
                                          color: Colors.white,
                                          width: 1.5),
                                    ),
                                    child: isCurrentCover
                                        ? const Icon(Icons.check,
                                            color: Colors.white, size: 14)
                                        : null,
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
        ],
      ),
    );
  }
}

class _PhotoThumb extends StatefulWidget {
  final Map<String, dynamic> photo;
  const _PhotoThumb({required this.photo});

  @override
  State<_PhotoThumb> createState() => _PhotoThumbState();
}

class _PhotoThumbState extends State<_PhotoThumb> {
  Uint8List? _bytes;

  @override
  void initState() {
    super.initState();
    MediaService.instance
        .getPhotoBytes(widget.photo['encrypted_path'])
        .then((b) {
      if (mounted) setState(() => _bytes = b);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF2A2A2A),
      child: _bytes != null
          ? Image.memory(_bytes!, fit: BoxFit.cover)
          : const Center(
              child: Icon(Icons.photo, color: Colors.white24, size: 24)),
    );
  }
}