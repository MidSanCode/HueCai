import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:hue_cai/providers/tool_provider.dart';
import 'package:hue_cai/widgets/panels/color_panel.dart';
import 'package:hue_cai/widgets/panels/brush_panel.dart';

void main() {
  testWidgets('right panel widgets render without exceptions', (tester) async {
    tester.view.physicalSize = const Size(1280, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final tp = ToolProvider();
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: tp,
        child: MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 180,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ColorPanel(toolProvider: tp),
                    const BrushPanel(),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(tester.takeException(), isNull,
        reason: 'ColorPanel or BrushPanel threw during build/paint');
    expect(find.byType(ColorPanel), findsOneWidget);
    expect(find.byType(BrushPanel), findsOneWidget);
  });
}