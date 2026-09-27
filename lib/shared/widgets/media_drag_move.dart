import 'dart:async';
import 'package:flutter/material.dart';
import 'photo_thumbnail.dart';
import 'folder_thumbnail.dart';

class MediaDragSelection {
  final List<int> ids;
  final bool folders;
  MediaDragSelection(Iterable<int> ids, {this.folders = false})
      : ids = List.unmodifiable(ids);
}

/// Hold an already selected item to lift the whole selection.
class SelectedMediaDrag extends StatefulWidget {
  final bool enabled;
  final Iterable<int> ids;
  final Map<String, dynamic> photo;
  final bool showPreview;
  final bool isFolder;
  final VoidCallback? onSelect;
  final Widget child;
  const SelectedMediaDrag(
      {super.key,
      this.isFolder = false,
      this.onSelect,
      required this.enabled,
      required this.ids,
      required this.photo,
      required this.showPreview,
      required this.child});

  @override
  State<SelectedMediaDrag> createState() => _SelectedMediaDragState();
}

class _SelectedMediaDragState extends State<SelectedMediaDrag>
    with AutomaticKeepAliveClientMixin {
  bool _dragging = false;
  double _dragDistance = 0;
  @override
  bool get wantKeepAlive => _dragging;
  Timer? _scrollTimer;
  Offset? _pointer;
  ScrollableState? _scrollable;

  void _stopScroll() {
    _scrollTimer?.cancel();
    _scrollTimer = null;
    _pointer = null;
    _scrollable = null;
  }

  void _startScroll() {
    _scrollable = Scrollable.maybeOf(context);
    _scrollTimer = Timer.periodic(const Duration(milliseconds: 16), (_) {
      final scrollable = _scrollable;
      final pointer = _pointer;
      if (!mounted ||
          scrollable == null ||
          !scrollable.mounted ||
          pointer == null) return;
      final box = scrollable.context.findRenderObject();
      if (box is! RenderBox || !box.attached || !box.hasSize) return;
      final y = box.globalToLocal(pointer).dy;
      const edge = 72.0;
      final speed =
          y < edge ? -10.0 : (y > box.size.height - edge ? 10.0 : 0.0);
      final position = scrollable.position;
      if (speed == 0 || !position.hasContentDimensions) return;
      final next = (position.pixels + speed)
          .clamp(position.minScrollExtent, position.maxScrollExtent);
      if (next != position.pixels) position.jumpTo(next);
    });
  }

  @override
  void dispose() {
    _stopScroll();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (!widget.enabled) return widget.child;
    final selection = MediaDragSelection(widget.ids, folders: widget.isFolder);
    return LongPressDraggable<MediaDragSelection>(
      data: selection,
      maxSimultaneousDrags: 1,
      delay: const Duration(milliseconds: 300),
      dragAnchorStrategy: pointerDragAnchorStrategy,
      onDragStarted: () {
        _dragDistance = 0;
        _dragging = true;
        updateKeepAlive();
        _startScroll();
      },
      onDragUpdate: (details) {
        _pointer = details.globalPosition;
        _dragDistance += details.delta.distance;
      },
      onDragEnd: (details) {
        _stopScroll();
        if (mounted) {
          _dragging = false;
          if (!details.wasAccepted && _dragDistance < 10) {
            widget.onSelect?.call();
          }
          updateKeepAlive();
        }
      },
      childWhenDragging: Opacity(opacity: 0.3, child: widget.child),
      feedback: Transform.translate(
        offset: const Offset(-48, -112),
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: 0.8, end: 1),
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutBack,
          builder: (_, scale, child) =>
              Transform.scale(scale: scale, child: child),
          child: Material(
            elevation: 12,
            borderRadius: BorderRadius.circular(14),
            clipBehavior: Clip.antiAlias,
            child: SizedBox(
                width: 96,
                height: 112,
                child: Stack(fit: StackFit.expand, children: [
                  if (widget.isFolder && !widget.showPreview)
                    const ColoredBox(
                        color: Color(0xFF2A2A2A),
                        child: Center(
                            child: Icon(Icons.folder, color: Colors.white54)))
                  else if (widget.isFolder)
                    FolderThumbnail(
                        folder: widget.photo,
                      showCount: widget.photo['parent_id'] != null,
                        isSelected: false,
                        showPreview: widget.showPreview,
                        onTap: () {},
                        onLongPress: () {},
                        onMenuTap: (_) {})
                  else
                    PhotoThumbnail(
                        key: ValueKey(widget.photo['encrypted_path']),
                        photo: widget.photo,
                        showPreview: widget.showPreview),
                  Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: ColoredBox(
                          color: Colors.black87,
                          child: Padding(
                              padding: const EdgeInsets.all(6),
                              child: Text(
                                  '${selection.ids.length} ${widget.isFolder ? 'carpeta' : 'archivo'}${selection.ids.length == 1 ? '' : 's'}',
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                      color: Colors.white, fontSize: 12))))),
                ])),
          ),
        ),
      ),
      child: widget.child,
    );
  }
}

class MediaFolderDrop extends StatefulWidget {
  final bool enabled;
  final bool Function(MediaDragSelection)? canAccept;
  final bool moveIntoCenter;
  final ValueChanged<MediaDragSelection> onDrop;
  final void Function(MediaDragSelection, bool after)? onReorder;
  final Widget child;
  const MediaFolderDrop(
      {super.key,
      required this.enabled,
      this.canAccept,
      this.moveIntoCenter = false,
      required this.onDrop,
      this.onReorder,
      required this.child});

  @override
  State<MediaFolderDrop> createState() => _MediaFolderDropState();
}

class _MediaFolderDropState extends State<MediaFolderDrop> {
  bool _after = false;
  bool _inCenter = false;
  void _position(Offset offset) {
    if (widget.onReorder == null) return;
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return;
    final y = box.globalToLocal(offset).dy;
    final after = y >= box.size.height / 2;
    final center = widget.moveIntoCenter &&
        y >= box.size.height * 0.25 && y <= box.size.height * 0.75;
    if (after != _after || center != _inCenter) {
      setState(() { _after = after; _inCenter = center; });
    }
  }

  @override
  Widget build(BuildContext context) => DragTarget<MediaDragSelection>(
        onWillAcceptWithDetails: (details) {
          _position(details.offset);
          return widget.enabled &&
              details.data.ids.isNotEmpty &&
              (widget.canAccept?.call(details.data) ?? true);
        },
        onMove: (details) => _position(details.offset),
        onAcceptWithDetails: (details) {
          if (widget.onReorder != null && !_inCenter) {
            widget.onReorder!(details.data, _after);
          } else {
            widget.onDrop(details.data);
          }
        },
        builder: (context, candidates, rejected) {
          final hovering = candidates.isNotEmpty && widget.enabled;
          final color = Theme.of(context).colorScheme.primary;
          final reorder = widget.onReorder != null && !_inCenter;
          return AnimatedScale(
            scale: hovering && !reorder ? 0.94 : 1,
            duration: const Duration(milliseconds: 160),
            child: Stack(fit: StackFit.passthrough, children: [
              widget.child,
              Positioned.fill(
                  child: IgnorePointer(
                      child: AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                decoration: BoxDecoration(
                    color: hovering && !reorder ? color.withValues(alpha: 0.25)
                        : Colors.transparent,
                    borderRadius: reorder ? null : BorderRadius.circular(10),
                    border: Border.all(color: hovering && !reorder ? color : Colors.transparent, width: 3)),

              ))),
            ]),
          );
        },
      );
}
