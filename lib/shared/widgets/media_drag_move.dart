import 'dart:async';
import 'package:flutter/material.dart';
import 'photo_thumbnail.dart';

class MediaDragSelection {
  final List<int> ids;
  MediaDragSelection(Iterable<int> ids) : ids = List.unmodifiable(ids);
}

/// Hold an already selected item to lift the whole selection.
class SelectedMediaDrag extends StatefulWidget {
  final bool enabled;
  final Iterable<int> ids;
  final Map<String, dynamic> photo;
  final bool showPreview;
  final Widget child;
  const SelectedMediaDrag(
      {super.key,
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
    final selection = MediaDragSelection(widget.ids);
    return LongPressDraggable<MediaDragSelection>(
      data: selection,
      maxSimultaneousDrags: 1,
      delay: const Duration(milliseconds: 300),
      dragAnchorStrategy: pointerDragAnchorStrategy,
      onDragStarted: () {
        _dragging = true;
        updateKeepAlive();
        _startScroll();
      },
      onDragUpdate: (details) => _pointer = details.globalPosition,
      onDragEnd: (_) {
        _stopScroll();
        if (mounted) {
          _dragging = false;
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
                                  '${selection.ids.length} archivo${selection.ids.length == 1 ? '' : 's'}',
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

class MediaFolderDrop extends StatelessWidget {
  final bool enabled;
  final ValueChanged<MediaDragSelection> onDrop;
  final Widget child;
  const MediaFolderDrop(
      {super.key,
      required this.enabled,
      required this.onDrop,
      required this.child});

  @override
  Widget build(BuildContext context) => DragTarget<MediaDragSelection>(
        onWillAcceptWithDetails: (details) =>
            enabled && details.data.ids.isNotEmpty,
        onAcceptWithDetails: (details) => onDrop(details.data),
        builder: (context, candidates, rejected) {
          final hovering = candidates.isNotEmpty && enabled;
          final color = Theme.of(context).colorScheme.primary;
          return AnimatedScale(
            scale: hovering ? 0.94 : 1,
            duration: const Duration(milliseconds: 160),
            child: Stack(fit: StackFit.passthrough, children: [
              child,
              Positioned.fill(
                  child: IgnorePointer(
                      child: AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                decoration: BoxDecoration(
                    color: hovering
                        ? color.withValues(alpha: 0.25)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                        color: hovering ? color : Colors.transparent,
                        width: 3)),
                child: hovering
                    ? const Center(
                        child: DecoratedBox(
                            decoration: BoxDecoration(
                                color: Colors.black87,
                                borderRadius:
                                    BorderRadius.all(Radius.circular(8))),
                            child: Padding(
                                padding: EdgeInsets.all(8),
                                child: Text('Soltar aquí',
                                    style: TextStyle(
                                        color: Colors.white, fontSize: 12)))))
                    : null,
              ))),
            ]),
          );
        },
      );
}
