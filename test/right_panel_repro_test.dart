import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:hue_cai/providers/app_settings.dart';
import 'package:hue_cai/providers/tool_provider.dart';
import 'package:hue_cai/widgets/panels/color_panel.dart';
import 'package:hue_cai/widgets/panels/brush_panel.dart';
import 'package:hue_cai/widgets/panels/pattern_panel.dart';

void main() {
  for (final height in [1600.0, 800.0, 600.0, 480.0]) {
    testWidgets('right panel renders at height $height without overflow',
        (tester) async {
      tester.view.physicalSize = Size(1280, height);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final tp = ToolProvider();
      final settings = AppSettings();
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider.value(value: tp),
            ChangeNotifierProvider.value(value: settings),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: 180,
                child: Column(
                  children: [
                    const SizedBox(height: 32), // header row
                    Expanded(
                      child: SingleChildScrollView(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            ColorPanel(toolProvider: tp),
                            const BrushPanel(),
                            const PatternPanel(),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull,
          reason: 'Right panel overflowed at height $height');
      expect(find.byType(ColorPanel), findsOneWidget);
      expect(find.byType(BrushPanel), findsOneWidget);
      expect(find.byType(PatternPanel), findsOneWidget);
    });
  }
}