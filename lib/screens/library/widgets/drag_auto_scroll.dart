import 'package:flutter/widgets.dart';

import '../../../core/theme/app_sizes.dart';

/// Scrolls the list in [child] (built with `primary: true`) while a dragged
/// card is held near its top or bottom edge, so one hand can carry a card up
/// to the collections. It follows the finger itself, because a card stops
/// reporting its drag once it scrolls out of view.
class DragAutoScroll extends StatefulWidget {
  const DragAutoScroll({super.key, required this.child});
  final Widget child;

  static DragAutoScrollState? of(BuildContext context) =>
      context.findAncestorStateOfType<DragAutoScrollState>();

  @override
  State<DragAutoScroll> createState() => DragAutoScrollState();
}

class DragAutoScrollState extends State<DragAutoScroll>
    with SingleTickerProviderStateMixin {
  final _list = ScrollController();
  late final _ticker = createTicker((_) => _step());
  int? _lastDown, _finger;
  double _downY = 0, _y = 0;

  /// A card drag began: follow the finger that last touched the list.
  void start() {
    _finger = _lastDown;
    _y = _downY;
    if (!_ticker.isActive) _ticker.start();
  }

  void _stop(PointerEvent e) {
    if (e.pointer != _finger) return;
    _finger = null;
    _ticker.stop();
  }

  void _step() {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null || !_list.hasClients) return;
    final top = box.localToGlobal(Offset.zero).dy;
    final bottom = top + box.size.height;
    const edge = AppSizes.dragScrollEdge;
    // 0 outside the edge bands, up to 1 at (or past) the list's edge.
    final up = ((top + edge - _y) / edge).clamp(0.0, 1.0);
    final down = ((_y - bottom + edge) / edge).clamp(0.0, 1.0);
    if (up == 0 && down == 0) return;
    final p = _list.position;
    _list.jumpTo(
      (p.pixels + (down - up) * AppSizes.dragScrollStep).clamp(
        p.minScrollExtent,
        p.maxScrollExtent,
      ),
    );
  }

  @override
  void dispose() {
    _ticker.dispose();
    _list.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Listener(
    onPointerDown: (e) {
      _lastDown = e.pointer;
      _downY = e.position.dy;
    },
    onPointerMove: (e) {
      if (e.pointer == _finger) _y = e.position.dy;
    },
    onPointerUp: _stop,
    onPointerCancel: _stop,
    child: PrimaryScrollController(controller: _list, child: widget.child),
  );
}
