import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:hue_cai/app.dart';

void main() {
  testWidgets('App loads workspace screen', (WidgetTester tester) async {
    await tester.pumpWidget(
      EasyLocalization(
        supportedLocales: const [Locale('en', 'US')],
        path: 'assets/l10n',
        fallbackLocale: Locale('en', 'US'),
        child: const HueCaiApp(),
      ),
    );
    await tester.pump();
    expect(find.text('HueCai'), findsOneWidget);
  });
}
