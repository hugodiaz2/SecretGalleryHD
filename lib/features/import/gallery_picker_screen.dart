import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:photo_manager/photo_manager.dart';
import '../../core/services/media_service.dart';

class GalleryPickerScreen extends StatefulWidget {
  final int folderId;
  const GalleryPickerScreen({super.key, required this.folderId});

  @override
  State<GalleryPickerScreen> createState() => _GalleryPickerScreenState();
}

class _GalleryPickerScreenState extends State<GalleryPickerScreen>
    with SingleTickerProviderStateMixin {
  final _media = MediaService.instance;

  // Pestaña activa: 0 = fotos, 1 = videos
  late TabController _tabController;
  int _activeTab = 0;

  List<AssetPathEntity> _albums = [];
  bool _loadingAlbums = true;

  AssetPathEntity? _currentAlbum;
  List<AssetEntity> _assets = [];
  bool _loadingAssets = false;

  final Set<String> _selectedIds = {};
  final Map<String, AssetEntity> _assetMap = {};
  final Map<String, Future<Widget>> _thumbCache = {};
  final Map<String, Future<Widget>> _albumThumbCache = {};

  bool _importing = false;
  int _importCurrent = 0;
  int _importTotal = 0;
  int _loadGeneration = 0;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      if (_tabController.indexIsChanging ||
          _activeTab == _tabController.index ||
          _importing) return;
      setState(() {
        _activeTab = _tabController.index;
        _currentAlbum = null;
        _assets = [];
        _selectedIds.clear();
        _assetMap.clear();
        _loadingAlbums = true;
      });
      _loadAlbums();
    });
    _loadAlbums();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _showError(Object error) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo completar la operación: $error')));
  }

  Future<void> _loadAlbums() async {
    final generation = ++_loadGeneration;
    try {
      final ok = await _media.requestPermission();
      if (!mounted || generation != _loadGeneration) return;
      if (!ok) {
        setState(() => _loadingAlbums = false);
        _showError(
            'Se necesita acceso a la galería. Puedes habilitarlo en Ajustes.');
        return;
      }
      final type = _activeTab == 0 ? RequestType.image : RequestType.video;
      final albums = await _media.getGalleryAlbums(type: type);
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _albums = albums;
        _albumThumbCache.clear();
        _loadingAlbums = false;
      });
    } catch (e) {
      if (!mounted || generation != _loadGeneration) return;
      setState(() => _loadingAlbums = false);
      _showError(e);
    }
  }

  Future<void> _openAlbum(AssetPathEntity album) async {
    final generation = ++_loadGeneration;
    setState(() {
      _currentAlbum = album;
      _loadingAssets = true;
      _assets = [];
      _selectedIds.clear();
      _assetMap.clear();
      _thumbCache.clear();
    });
    try {
      final assets = await _media.getAlbumAssets(album);
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _assets = assets;
        _assetMap.addEntries(assets.map((a) => MapEntry(a.id, a)));
        _loadingAssets = false;
      });
    } catch (e) {
      if (!mounted || generation != _loadGeneration) return;
      setState(() => _loadingAssets = false);
      _showError(e);
    }
  }

  void _toggleSelectAll() {
    if (_currentAlbum == null || _assets.isEmpty) return;
    setState(() {
      final allSelected = _selectedIds.length == _assets.length;
      if (allSelected) {
        _selectedIds.clear();
      } else {
        _selectedIds
          ..clear()
          ..addAll(_assets.map((a) => a.id));
      }
    });
  }

  Future<void> _import() async {
    if (_importing || _selectedIds.isEmpty) return;
    final selected = _selectedIds
        .map((id) => _assetMap[id])
        .whereType<AssetEntity>()
        .toList();
    setState(() {
      _importing = true;
      _importTotal = selected.length;
      _importCurrent = 0;
    });
    try {
      final result = await _media.importAssets(
          assets: selected,
          folderId: widget.folderId,
          onProgress: (current, total) {
            if (mounted) {
              setState(() {
                _importCurrent = current;
                _importTotal = total;
              });
            }
          });
      if (!mounted) return;
      // Successful imports close this route. The caller reloads the private
      // gallery; reloading the public album here just delays that navigation.
      if (result.completed.isEmpty) {
        final album = _currentAlbum;
        if (album != null) await _openAlbum(album);
        if (!mounted) return;
      }
      setState(() => _importing = false);
      if (result.failed.isNotEmpty || result.publicRetained.isNotEmpty) {
        final messages = <String>[
          if (result.failed.isNotEmpty)
            'No se pudieron ocultar algunos archivos.',
          if (result.publicRetained.isNotEmpty)
            'Algunos originales siguen en la galería pública. Puedes volver a intentar eliminarlos.',
        ];
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(messages.join(' '))),
        );
      }
      if (mounted && result.completed.isNotEmpty) Navigator.pop(context, true);
    } catch (e) {
      _showError(e);
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  Future<Widget> _buildThumb(AssetEntity asset) {
    return _thumbCache.putIfAbsent(asset.id, () async {
      try {
        final data =
            await asset.thumbnailDataWithSize(const ThumbnailSize(180, 180));
        if (data == null) {
          return const ColoredBox(
              color: Color(0xFF2A2A2A),
              child: Icon(Icons.image, color: Colors.white24));
        }
        return RepaintBoundary(
          child: Image.memory(
            data,
            fit: BoxFit.cover,
            filterQuality: FilterQuality.low,
            gaplessPlayback: true,
          ),
        );
      } catch (_) {
        return const ColoredBox(
            color: Color(0xFF2A2A2A),
            child: Icon(Icons.broken_image, color: Colors.white24));
      }
    });
  }

  Future<Widget> _buildAlbumThumb(AssetPathEntity album) {
    return _albumThumbCache.putIfAbsent(album.id, () async {
      try {
        final assets = await album.getAssetListRange(start: 0, end: 1);
        if (assets.isEmpty) {
          return const ColoredBox(
              color: Color(0xFF2A2A2A),
              child: Icon(Icons.photo_album, color: Colors.white24, size: 40));
        }
        final data = await assets.first
            .thumbnailDataWithSize(const ThumbnailSize(180, 180));
        if (data == null) {
          return const ColoredBox(color: Color(0xFF2A2A2A));
        }
        return RepaintBoundary(
          child: Image.memory(
            data,
            fit: BoxFit.cover,
            filterQuality: FilterQuality.low,
            gaplessPlayback: true,
          ),
        );
      } catch (_) {
        return const ColoredBox(color: Color(0xFF2A2A2A));
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_importing) {
      return PopScope(
          canPop: false,
          child:
              _ImportingOverlay(current: _importCurrent, total: _importTotal));
    }

    return WillPopScope(
      onWillPop: () async {
        if (_currentAlbum != null) {
          setState(() {
            ++_loadGeneration;
            _currentAlbum = null;
            _assets = [];
            _selectedIds.clear();
            _assetMap.clear();
          });
          return false;
        }
        return true;
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF121212),
        appBar: AppBar(
          backgroundColor: const Color(0xFF1A1A1A),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.white),
            onPressed: () {
              if (_currentAlbum != null) {
                setState(() {
                  ++_loadGeneration;
                  _currentAlbum = null;
                  _assets = [];
                  _selectedIds.clear();
                  _assetMap.clear();
                });
              } else {
                Navigator.pop(context);
              }
            },
          ),
          title: Text(
            _currentAlbum != null
                ? (_selectedIds.isEmpty
                    ? _currentAlbum!.name
                    : '${_selectedIds.length} seleccionado${_selectedIds.length == 1 ? '' : 's'}')
                : (_activeTab == 0
                    ? 'Selecciona álbum de fotos'
                    : 'Selecciona álbum de videos'),
            style: GoogleFonts.poppins(color: Colors.white, fontSize: 15),
          ),
          actions: [
            if (_currentAlbum != null)
              IconButton(
                tooltip: _selectedIds.length == _assets.length
                    ? 'Deseleccionar todo'
                    : 'Seleccionar todo',
                onPressed: _assets.isEmpty ? null : _toggleSelectAll,
                icon: const Icon(Icons.select_all, color: Colors.white),
              ),
            if (_selectedIds.isNotEmpty)
              TextButton(
                onPressed: _import,
                child: Text(
                  'Ocultar (${_selectedIds.length})',
                  style: GoogleFonts.poppins(
                    color: Colors.blue,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
          ],
          // Pestañas Fotos / Videos
          bottom: _currentAlbum == null
              ? TabBar(
                  controller: _tabController,
                  indicatorColor: Colors.blue,
                  labelColor: Colors.white,
                  unselectedLabelColor: Colors.white38,
                  labelStyle: GoogleFonts.poppins(
                      fontWeight: FontWeight.w600, fontSize: 13),
                  tabs: const [
                    Tab(
                      height: 44,
                      text: 'FOTOS',
                    ),
                    Tab(
                      height: 44,
                      text: 'VIDEOS',
                    ),
                  ],
                )
              : null,
        ),
        body: _currentAlbum == null ? _buildAlbumsGrid() : _buildAssetsGrid(),
      ),
    );
  }

  // ── Grid de álbumes ──────────────────────────────────────
  Widget _buildAlbumsGrid() {
    if (_loadingAlbums) {
      return const Center(child: CircularProgressIndicator(color: Colors.blue));
    }
    if (_albums.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              _activeTab == 0
                  ? Icons.photo_library_outlined
                  : Icons.video_library_outlined,
              size: 64,
              color: Colors.white12,
            ),
            const SizedBox(height: 16),
            Text(
              _activeTab == 0
                  ? 'No se encontraron álbumes de fotos'
                  : 'No se encontraron álbumes de videos',
              style: GoogleFonts.poppins(color: Colors.white38),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    return GridView.builder(
      padding: const EdgeInsets.all(10),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisSpacing: 6,
        crossAxisSpacing: 6,
        childAspectRatio: 0.90,
      ),
      itemCount: _albums.length,
      itemBuilder: (_, i) {
        final album = _albums[i];
        return GestureDetector(
          onTap: () => _openAlbum(album),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: Stack(
              fit: StackFit.expand,
              children: [
                FutureBuilder<Widget>(
                  future: _buildAlbumThumb(album),
                  builder: (ctx, snap) {
                    if (snap.connectionState != ConnectionState.done) {
                      return const ColoredBox(color: Color(0xFF2A2A2A));
                    }
                    return snap.data ??
                        const ColoredBox(color: Color(0xFF2A2A2A));
                  },
                ),
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(5, 16, 5, 5),
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.bottomCenter,
                        end: Alignment.topCenter,
                        colors: [Colors.black87, Colors.transparent],
                      ),
                    ),
                    child: FutureBuilder<int>(
                      future: album.assetCountAsync,
                      builder: (ctx, snap) {
                        final count = snap.data ?? 0;
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              album.name,
                              style: GoogleFonts.poppins(
                                color: Colors.white,
                                fontWeight: FontWeight.w600,
                                fontSize: 11,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            Text(
                              '$count ${_activeTab == 0 ? 'foto${count == 1 ? '' : 's'}' : 'video${count == 1 ? '' : 's'}'}',
                              style: GoogleFonts.poppins(
                                  color: Colors.white60, fontSize: 9),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                ),
                // Ícono de video en esquina
                if (_activeTab == 1)
                  Positioned(
                    top: 8,
                    right: 8,
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: Colors.black54,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Icon(Icons.videocam,
                          color: Colors.white, size: 16),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ── Grid de assets (fotos/videos) ────────────────────────
  Widget _buildAssetsGrid() {
    if (_loadingAssets) {
      return const Center(child: CircularProgressIndicator(color: Colors.blue));
    }
    if (_assets.isEmpty) {
      return Center(
        child: Text(
          _activeTab == 0
              ? 'Sin fotos en este álbum'
              : 'Sin videos en este álbum',
          style: GoogleFonts.poppins(color: Colors.white38),
        ),
      );
    }

    return GridView.builder(
      padding: const EdgeInsets.all(2),
      cacheExtent: 400,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 5,
        mainAxisSpacing: 2,
        crossAxisSpacing: 2,
      ),
      itemCount: _assets.length,
      itemBuilder: (_, i) {
        final asset = _assets[i];
        final isSelected = _selectedIds.contains(asset.id);
        final isVideo = asset.type == AssetType.video;

        return GestureDetector(
          onTap: () {
            setState(() {
              if (isSelected) {
                _selectedIds.remove(asset.id);
              } else {
                _selectedIds.add(asset.id);
              }
            });
          },
          child: Stack(
            fit: StackFit.expand,
            children: [
              FutureBuilder<Widget>(
                future: _buildThumb(asset),
                builder: (ctx, snap) {
                  if (snap.connectionState != ConnectionState.done) {
                    return const ColoredBox(color: Color(0xFF2A2A2A));
                  }
                  return snap.data ??
                      const ColoredBox(color: Color(0xFF2A2A2A));
                },
              ),

              // Overlay selección
              if (isSelected) Container(color: Colors.blue.withOpacity(0.4)),

              // Duración del video
              if (isVideo)
                Positioned(
                  bottom: 4,
                  left: 4,
                  child: Row(
                    children: [
                      const Icon(Icons.play_circle_fill,
                          color: Colors.white, size: 14),
                      const SizedBox(width: 3),
                      Text(
                        _formatDuration(asset.videoDuration),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          shadows: [Shadow(color: Colors.black, blurRadius: 4)],
                        ),
                      ),
                    ],
                  ),
                ),

              // Check selección
              Positioned(
                top: 6,
                right: 6,
                child: Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isSelected ? Colors.blue : Colors.black45,
                    border: Border.all(color: Colors.white, width: 1.5),
                  ),
                  child: isSelected
                      ? const Icon(Icons.check, color: Colors.white, size: 15)
                      : null,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  String _formatDuration(Duration duration) {
    final m = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    if (duration.inHours > 0) {
      return '${duration.inHours}:$m:$s';
    }
    return '$m:$s';
  }
}

// ── Vista de carga al importar ───────────────────────────────
class _ImportingOverlay extends StatefulWidget {
  final int current;
  final int total;

  const _ImportingOverlay({required this.current, required this.total});

  @override
  State<_ImportingOverlay> createState() => _ImportingOverlayState();
}

class _ImportingOverlayState extends State<_ImportingOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulseController;

  static const _phrases = [
    'Protegiendo foto...',
    'Ocultando foto...',
    'Encriptando...',
    'Guardando en la bóveda...',
  ];

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final phrase = _phrases[widget.current % _phrases.length];
    final progress = widget.total == 0 ? null : widget.current / widget.total;

    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AnimatedBuilder(
              animation: _pulseController,
              builder: (_, child) {
                final v = _pulseController.value;
                return Container(
                  width: 90,
                  height: 90,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: const Color(0xFF12122A),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.blue.withOpacity(0.25 + 0.15 * v),
                        blurRadius: 20 + 20 * v,
                        spreadRadius: 2 + 4 * v,
                      ),
                    ],
                    border: Border.all(
                      color: Colors.blue.withOpacity(0.4),
                      width: 1.5,
                    ),
                  ),
                  child: child,
                );
              },
              child: const Icon(Icons.shield_outlined,
                  color: Colors.white, size: 40),
            ),
            const SizedBox(height: 28),
            Text(
              'Ocultando ${widget.current} de ${widget.total}',
              style: GoogleFonts.poppins(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: 200,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: LinearProgressIndicator(
                  value: progress,
                  minHeight: 6,
                  backgroundColor: Colors.white12,
                  valueColor: const AlwaysStoppedAnimation(Colors.blue),
                ),
              ),
            ),
            const SizedBox(height: 16),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 180),
              child: Text(
                phrase,
                key: ValueKey(phrase),
                style: GoogleFonts.poppins(color: Colors.white38, fontSize: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
