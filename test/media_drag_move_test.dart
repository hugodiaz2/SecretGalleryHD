import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import '../lib/shared/widgets/media_drag_move.dart';

void main() {
  Future<void> showDrag(
      WidgetTester tester, ValueChanged<MediaDragSelection> onDrop,
      {bool targetEnabled = true}) async {
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SelectedMediaDrag(
            enabled: true,
            ids: const [7, 9, 12],
            photo: const {
              'id': 7,
              'original_name': 'photo.jpg',
              'encrypted_path': 'fake.enc'
            },
            showPreview: false,
            child: const SizedBox(
                key: Key('source'),
                width: 100,
                height: 100,
                child: ColoredBox(color: Colors.blue))),
        const SizedBox(width: 120),
        MediaFolderDrop(
            enabled: targetEnabled,
            onDrop: onDrop,
            child: const SizedBox(
                key: Key('folder'),
                width: 100,
                height: 100,
                child: ColoredBox(color: Colors.green))),
      ],
    ))));
  }

  testWidgets('Holding a selection shows its count and drops all IDs once',
      (tester) async {
    final drops = <List<int>>[];
    await showDrag(tester, (selection) => drops.add(selection.ids));
    final gesture = await tester
        .startGesture(tester.getCenter(find.byKey(const Key('source'))));
    await tester.pump(const Duration(milliseconds: 350));
    expect(find.text('3 archivos'), findsOneWidget);
    await gesture.moveTo(tester.getCenter(find.byKey(const Key('folder'))));
    await tester.pump(const Duration(milliseconds: 180));
    expect(find.text('Soltar aquí'), findsOneWidget);
    await gesture.up();
    await tester.pumpAndSettle();
    expect(drops, [
      [7, 9, 12]
    ]);
    expect(find.text('3 archivos'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Dropping outside a folder leaves the selection untouched',
      (tester) async {
    var dropped = false;
    await showDrag(tester, (_) => dropped = true);
    final gesture = await tester
        .startGesture(tester.getCenter(find.byKey(const Key('source'))));
    await tester.pump(const Duration(milliseconds: 350));
    await gesture.moveTo(const Offset(500, 400));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(dropped, isFalse);
    expect(find.text('3 archivos'), findsNothing);
  });

  testWidgets('Disabled folder does not accept another move', (tester) async {
    var dropped = false;
    await showDrag(tester, (_) => dropped = true, targetEnabled: false);
    final gesture = await tester
        .startGesture(tester.getCenter(find.byKey(const Key('source'))));
    await tester.pump(const Duration(milliseconds: 350));
    await gesture.moveTo(tester.getCenter(find.byKey(const Key('folder'))));
    await tester.pump();
    expect(find.text('Soltar aquí'), findsNothing);
    await gesture.up();
    await tester.pumpAndSettle();
    expect(dropped, isFalse);
  });
  testWidgets('Holding near an edge scrolls and keeps the dragged item alive',
      (tester) async {
    final controller = ScrollController();
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: ListView.builder(
      controller: controller,
      itemCount: 60,
      itemBuilder: (_, index) => index == 0
          ? SelectedMediaDrag(
              enabled: true,
              ids: const [7],
              photo: const {
                'id': 7,
                'original_name': 'photo.jpg',
                'encrypted_path': 'fake.enc'
              },
              showPreview: false,
              child: const SizedBox(
                  key: Key('source'),
                  height: 100,
                  child: ColoredBox(color: Colors.blue)))
          : SizedBox(height: 100, child: Text('Item $index')),
    ))));
    final gesture = await tester
        .startGesture(tester.getCenter(find.byKey(const Key('source'))));
    await tester.pump(const Duration(milliseconds: 350));
    await gesture.moveTo(const Offset(100, 580));
    for (var frame = 0; frame < 60; frame++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(controller.offset, greaterThan(400));
    expect(find.text('1 archivo'), findsOneWidget);
    await gesture.up();
    await tester.pumpAndSettle();
    final stoppedAt = controller.offset;
    await tester.pump(const Duration(milliseconds: 100));
    expect(controller.offset, stoppedAt);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });
}
