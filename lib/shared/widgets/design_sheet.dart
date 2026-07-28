import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/services/prefs_service.dart';

class DesignSheet extends StatefulWidget {
  final GridViewType currentViewType;
  final String currentSort;
  final bool currentNarrowBorders;
  final bool currentShowPhotoPreview;
  final bool currentShowFolderPreview;
  final void Function(GridViewType) onViewChanged;
  final void Function(String) onSortChanged;
  final void Function(bool) onNarrowBordersChanged;
  final void Function(bool) onPhotoPreviewChanged;
  final void Function(bool) onFolderPreviewChanged;

  const DesignSheet({
    super.key,
    required this.currentViewType,
    required this.currentSort,
    required this.currentNarrowBorders,
    required this.currentShowPhotoPreview,
    required this.currentShowFolderPreview,
    required this.onViewChanged,
    required this.onSortChanged,
    required this.onNarrowBordersChanged,
    required this.onPhotoPreviewChanged,
    required this.onFolderPreviewChanged,
  });

  @override
  State<DesignSheet> createState() => _DesignSheetState();
}

class _DesignSheetState extends State<DesignSheet> {
  late GridViewType _viewType;
  late String _sort;
  late bool _narrowBorders;
  late bool _showPhotoPreview;
  late bool _showFolderPreview;

  @override
  void initState() {
    super.initState();
     _viewType = widget.currentViewType;
    _sort = widget.currentSort;
    _narrowBorders = widget.currentNarrowBorders;
    _showPhotoPreview = widget.currentShowPhotoPreview;
    _showFolderPreview = widget.currentShowFolderPreview;
  }

  Future<void> _loadPrefs() async {
  final narrow = await PrefsService.instance.getNarrowBorders();
  final photo = await PrefsService.instance.getShowPhotoPreview();
  final folder = await PrefsService.instance.getShowFolderPreview();
  setState(() {
    _narrowBorders = narrow;
    _showPhotoPreview = photo;
    _showFolderPreview = folder;
  });
}

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.85,
      decoration: const BoxDecoration(
        color: Color(0xFF1A1A1A),
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          Container(
            width: 40, height: 4,
            margin: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
              color: Colors.white24,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                const Icon(Icons.tune, color: Colors.white54, size: 20),
                const SizedBox(width: 8),
                Text('Diseño y vista',
                    style: GoogleFonts.poppins(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w600)),
              ],
            ),
          ),
          const SizedBox(height: 8),
          const Divider(color: Colors.white12),

          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: [

                // ── Estilo de vista ──
                _sectionTitle('Estilo de vista'),
                const SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _viewBtn(GridViewType.grid3, '3×3'),
                    _viewBtn(GridViewType.grid4, '4×4'),
                    _viewBtn(GridViewType.grid5, '5×5'),
                    _viewBtn(GridViewType.grid6, '6×6'),
                    _viewBtn(GridViewType.list, 'Lista'),
                  ],
                ),

                const SizedBox(height: 20),

                // ── Opciones de visualización ──
                _sectionTitle('Opciones de visualización'),
                _switchTile(
  icon: Icons.border_style,
  title: 'Bordes estrechos',
  subtitle: 'Reduce el espacio entre elementos',
  value: _narrowBorders,
  onChanged: (v) => setState(() => _narrowBorders = v),
),
_switchTile(
  icon: Icons.image_outlined,
  title: 'Vista previa de imágenes',
  subtitle: 'Muestra miniatura de las fotos',
  value: _showPhotoPreview,
  onChanged: (v) => setState(() => _showPhotoPreview = v),
),
_switchTile(
  icon: Icons.folder_outlined,
  title: 'Vista previa de carpetas',
  subtitle: 'Muestra portada en carpetas',
  value: _showFolderPreview,
  onChanged: (v) => setState(() => _showFolderPreview = v),
),

                const SizedBox(height: 20),

                // ── Orden ──
                _sectionTitle('Ordenar por'),
                _sortTile('newest', Icons.schedule, 'Más reciente primero'),
                _sortTile('oldest', Icons.history, 'Más antiguo primero'),
                _sortTile('az', Icons.sort_by_alpha, 'Nombre ascendente (A→Z)'),
                _sortTile('za', Icons.sort_by_alpha, 'Nombre descendente (Z→A)'),
                _sortTile('size_desc', Icons.data_usage, 'Tamaño descendente'),

                const SizedBox(height: 20),
              ],
            ),
          ),

          // Botón aplicar
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1565C0),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                onPressed: () async {
                  await PrefsService.instance.saveGridType(_viewType);
                  await PrefsService.instance.saveSort(_sort);
                  await PrefsService.instance.saveNarrowBorders(_narrowBorders);
                  await PrefsService.instance.saveShowPhotoPreview(_showPhotoPreview);
                  await PrefsService.instance.saveShowFolderPreview(_showFolderPreview);

                  widget.onViewChanged(_viewType);
                  widget.onSortChanged(_sort);
                  widget.onNarrowBordersChanged(_narrowBorders);
                  widget.onPhotoPreviewChanged(_showPhotoPreview);
                  widget.onFolderPreviewChanged(_showFolderPreview);
                  Navigator.pop(context);
                },
                child: Text('Aplicar',
                    style: GoogleFonts.poppins(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                        fontSize: 15)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4, top: 8),
      child: Text(title,
          style: GoogleFonts.poppins(
              color: Colors.white54,
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 1)),
    );
  }

  Widget _viewBtn(GridViewType type, String label) {
    final isSelected = _viewType == type;
    return GestureDetector(
      onTap: () => setState(() => _viewType = type),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 58,
        height: 64,
        decoration: BoxDecoration(
          color: isSelected
              ? const Color(0xFF1565C0).withOpacity(0.2)
              : const Color(0xFF2A2A2A),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected ? const Color(0xFF1565C0) : Colors.white12,
            width: 2,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              type == GridViewType.list ? Icons.view_list : Icons.grid_view,
              color: isSelected
                  ? const Color(0xFF1565C0)
                  : Colors.white38,
              size: 22,
            ),
            const SizedBox(height: 4),
            Text(label,
                style: GoogleFonts.poppins(
                    color: isSelected
                        ? const Color(0xFF1565C0)
                        : Colors.white38,
                    fontSize: 9,
                    fontWeight: isSelected
                        ? FontWeight.w600
                        : FontWeight.normal)),
          ],
        ),
      ),
    );
  }

  Widget _switchTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool value,
    required void Function(bool) onChanged,
  }) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Container(
        width: 36, height: 36,
        decoration: BoxDecoration(
          color: const Color(0xFF2A2A2A),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon, color: Colors.white54, size: 18),
      ),
      title: Text(title,
          style: GoogleFonts.poppins(color: Colors.white, fontSize: 13)),
      subtitle: Text(subtitle,
          style: GoogleFonts.poppins(color: Colors.white38, fontSize: 11)),
      trailing: Switch(
        value: value,
        onChanged: onChanged,
        activeColor: const Color(0xFF1565C0),
      ),
    );
  }

  Widget _sortTile(String value, IconData icon, String label) {
    final isSelected = _sort == value;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Container(
        width: 36, height: 36,
        decoration: BoxDecoration(
          color: isSelected
              ? const Color(0xFF1565C0).withOpacity(0.15)
              : const Color(0xFF2A2A2A),
          borderRadius: BorderRadius.circular(8),
          border: isSelected
              ? Border.all(color: const Color(0xFF1565C0), width: 1)
              : null,
        ),
        child: Icon(icon,
            color: isSelected ? const Color(0xFF1565C0) : Colors.white54,
            size: 18),
      ),
      title: Text(label,
          style: GoogleFonts.poppins(
              color: isSelected ? const Color(0xFF1565C0) : Colors.white,
              fontSize: 13,
              fontWeight:
                  isSelected ? FontWeight.w600 : FontWeight.normal)),
      trailing: isSelected
          ? const Icon(Icons.check_circle,
              color: Color(0xFF1565C0), size: 18)
          : null,
      onTap: () => setState(() => _sort = value),
    );
  }
}