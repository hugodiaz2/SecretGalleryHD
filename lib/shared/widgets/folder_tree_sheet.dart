import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/database/db_helper.dart';

class FolderTreeSheet extends StatefulWidget {
  final List<int> excludeFolderIds; // carpetas que NO pueden ser destino
  final int? currentFolderId; // carpeta donde estás ahora (se muestra pero no seleccionable)

  const FolderTreeSheet({
    super.key,
    this.excludeFolderIds = const [],
    this.currentFolderId,
  });

  @override
  State<FolderTreeSheet> createState() => _FolderTreeSheetState();
}

class _FolderTreeSheetState extends State<FolderTreeSheet> {
  final _db = DBHelper.instance;
  List<Map<String, dynamic>> _allFolders = [];
  final Set<int> _expanded = {};
  String _search = '';
  final _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final folders = await _db.getAllFoldersFlat();

    // Auto-expandir la carpeta actual para que se vea en el árbol
    if (widget.currentFolderId != null) {
      _expanded.add(widget.currentFolderId!);
      // También expandir su padre si tiene
      final current = folders.firstWhere(
        (f) => f['id'] == widget.currentFolderId,
        orElse: () => <String, dynamic>{},
      );
      if (current.isNotEmpty && current['parent_id'] != null) {
        _expanded.add(current['parent_id'] as int);
      }
    }

    setState(() => _allFolders = folders);
  }

  // Solo excluir carpetas seleccionadas para mover, NO la carpeta actual
  bool _isBlockedDestination(int id) {
    // Si es la carpeta actual, se muestra pero no se selecciona
    if (id == widget.currentFolderId) return true;
    // Las carpetas seleccionadas para mover no pueden ser destino
    return widget.excludeFolderIds
        .where((e) => e != widget.currentFolderId)
        .contains(id);
  }

  List<Map<String, dynamic>> get _roots => _allFolders
      .where((f) =>
          f['parent_id'] == null &&
          (_search.isEmpty ||
              (f['name'] as String)
                  .toLowerCase()
                  .contains(_search.toLowerCase())))
      .toList()
    ..sort((a, b) =>
        (a['name'] as String).compareTo(b['name'] as String));

  List<Map<String, dynamic>> _childrenOf(int parentId) => _allFolders
      .where((f) =>
          f['parent_id'] == parentId &&
          (_search.isEmpty ||
              (f['name'] as String)
                  .toLowerCase()
                  .contains(_search.toLowerCase())))
      .toList()
    ..sort((a, b) =>
        (a['name'] as String).compareTo(b['name'] as String));

  Widget _buildNode(Map<String, dynamic> folder, int depth) {
    final id = folder['id'] as int;
    final name = folder['name'] as String;
    final children = _childrenOf(id);
    final hasChildren = children.isNotEmpty;
    final isExpanded = _expanded.contains(id);
    final isCurrent = id == widget.currentFolderId;
    final isBlocked = _isBlockedDestination(id);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: isBlocked
              ? null
              : () => Navigator.pop(context, folder),
          child: Container(
            color: isCurrent
                ? const Color(0xFF1565C0).withOpacity(0.12)
                : Colors.transparent,
            padding: EdgeInsets.only(
              left: 16.0 + depth * 20,
              right: 16,
              top: 10,
              bottom: 10,
            ),
            child: Row(
              children: [
                // Flecha expandir/colapsar
                GestureDetector(
                  onTap: hasChildren
                      ? () => setState(() {
                            isExpanded
                                ? _expanded.remove(id)
                                : _expanded.add(id);
                          })
                      : null,
                  child: SizedBox(
                    width: 20,
                    child: hasChildren
                        ? Icon(
                            isExpanded
                                ? Icons.keyboard_arrow_down
                                : Icons.keyboard_arrow_right,
                            color: Colors.white54,
                            size: 20,
                          )
                        : null,
                  ),
                ),
                const SizedBox(width: 6),

                // Ícono carpeta
                Icon(
                  isCurrent
                      ? Icons.folder_open
                      : depth == 0
                          ? Icons.folder
                          : Icons.folder_open,
                  color: isCurrent
                      ? const Color(0xFF1565C0)
                      : isBlocked
                          ? Colors.white24
                          : const Color(0xFF1565C0),
                  size: 20,
                ),
                const SizedBox(width: 10),

                // Nombre
                Expanded(
                  child: Text(
                    name,
                    style: GoogleFonts.poppins(
                      color: isCurrent
                          ? const Color(0xFF1565C0)
                          : isBlocked
                              ? Colors.white38
                              : Colors.white,
                      fontSize: 14,
                      fontWeight: isCurrent || depth == 0
                          ? FontWeight.w600
                          : FontWeight.normal,
                    ),
                  ),
                ),

                // Badge "Aquí"
                if (isCurrent)
                  Container(
                    margin: const EdgeInsets.only(right: 8),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1565C0).withOpacity(0.2),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(
                          color: const Color(0xFF1565C0), width: 1),
                    ),
                    child: Text(
                      'Aquí',
                      style: GoogleFonts.poppins(
                        color: const Color(0xFF1565C0),
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),

                // Conteo de fotos
                FutureBuilder<int>(
                  future: _db.getTotalPhotoCount(id),
                  builder: (_, snap) => Text(
                    '${snap.data ?? 0}',
                    style: GoogleFonts.poppins(
                        color: Colors.white38, fontSize: 11),
                  ),
                ),
              ],
            ),
          ),
        ),

        // Hijos
        if (hasChildren && isExpanded)
          ...children.map((c) => _buildNode(c, depth + 1)),
      ],
    );
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
            child: Text(
              'Mover a carpeta',
              style: GoogleFonts.poppins(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              controller: _searchCtrl,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'Buscar carpeta...',
                hintStyle: const TextStyle(color: Colors.white38),
                prefixIcon:
                    const Icon(Icons.search, color: Colors.white38),
                filled: true,
                fillColor: const Color(0xFF2A2A2A),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide.none,
                ),
              ),
              onChanged: (v) => setState(() => _search = v),
            ),
          ),
          const SizedBox(height: 8),
          const Divider(color: Colors.white12),
          Expanded(
            child: _allFolders.isEmpty
                ? Center(
                    child: Text('Sin carpetas',
                        style: GoogleFonts.poppins(
                            color: Colors.white38)))
                : ListView(
                    children: _roots
                        .map((f) => _buildNode(f, 0))
                        .toList(),
                  ),
          ),
        ],
      ),
    );
  }
}