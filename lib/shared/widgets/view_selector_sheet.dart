import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/services/prefs_service.dart';

class ViewSelectorSheet extends StatelessWidget {
  final GridViewType current;
  final void Function(GridViewType) onSelected;

  const ViewSelectorSheet({
    super.key,
    required this.current,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final options = [
      _ViewOption(type: GridViewType.grid3, label: '3 × 3', cols: 3),
      _ViewOption(type: GridViewType.grid4, label: '4 × 4', cols: 4),
      _ViewOption(type: GridViewType.grid5, label: '5 × 5', cols: 5),
      _ViewOption(type: GridViewType.grid6, label: '6 × 6', cols: 6),
      _ViewOption(type: GridViewType.list, label: 'Lista', cols: 0),
    ];

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20),
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF1E1E1E),
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.5),
              blurRadius: 20,
              spreadRadius: 2,
            ),
          ],
        ),
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Tipo de vista',
              style: GoogleFonts.poppins(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 20),

            // Fila de opciones
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: options.map((opt) {
                final isSelected = opt.type == current;
                return GestureDetector(
                  onTap: () {
                    onSelected(opt.type);
                    Navigator.pop(context);
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    width: 56,
                    height: 72,
                    decoration: BoxDecoration(
                      color: isSelected
                          ? const Color(0xFF1565C0).withOpacity(0.2)
                          : const Color(0xFF2A2A2A),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isSelected
                            ? const Color(0xFF1565C0)
                            : Colors.white12,
                        width: 2,
                      ),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        // Preview visual
                        SizedBox(
                          width: 36,
                          height: 36,
                          child: opt.cols == 0
                              ? _buildListPreview()
                              : _buildGridPreview(opt.cols),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          opt.label,
                          style: GoogleFonts.poppins(
                            color: isSelected
                                ? const Color(0xFF1565C0)
                                : Colors.white54,
                            fontSize: 9,
                            fontWeight: isSelected
                                ? FontWeight.w600
                                : FontWeight.normal,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),

            const SizedBox(height: 16),
            const Divider(color: Colors.white12),
            const SizedBox(height: 4),

            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(
                'Cancelar',
                style: GoogleFonts.poppins(
                    color: Colors.white38, fontSize: 13),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGridPreview(int cols) {
    final rows = cols <= 4 ? 3 : 4;
    final cellSize = (34 - (cols - 1) * 2) / cols;
    final rowHeight = (34 - (rows - 1) * 2) / rows;

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: List.generate(rows, (r) {
        return Padding(
          padding: EdgeInsets.only(bottom: r < rows - 1 ? 2 : 0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: List.generate(cols, (c) {
              return Container(
                width: cellSize,
                height: rowHeight,
                margin: EdgeInsets.only(right: c < cols - 1 ? 2 : 0),
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(1),
                ),
              );
            }),
          ),
        );
      }),
    );
  }

  Widget _buildListPreview() {
  return Column(
    mainAxisAlignment: MainAxisAlignment.center,
    mainAxisSize: MainAxisSize.min,
    children: List.generate(4, (i) {
      return Padding(
        padding: EdgeInsets.only(bottom: i < 3 ? 2 : 0),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(
                color: Colors.white38,
                borderRadius: BorderRadius.circular(1),
              ),
            ),
            const SizedBox(width: 2),
            Container(
              width: 20,
              height: 7,
              decoration: BoxDecoration(
                color: Colors.white12,
                borderRadius: BorderRadius.circular(1),
              ),
            ),
          ],
        ),
      );
    }),
  );
}
}

class _ViewOption {
  final GridViewType type;
  final String label;
  final int cols;
  const _ViewOption(
      {required this.type, required this.label, required this.cols});
}