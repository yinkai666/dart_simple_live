import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simple_live_app/modules/multiview/multi_view_material_scope.dart';

void main() {
  testWidgets('page scope provides Flutter Material localization in a WidgetsApp', (tester) async {
    await tester.pumpWidget(WidgetsApp(
      color: Colors.black,
      locale: const Locale('zh', 'CN'),
      supportedLocales: const [Locale('zh', 'CN')],
      localizationsDelegates: const [DefaultWidgetsLocalizations.delegate],
      builder: (context, _) => MultiViewMaterialScope(
        child: Builder(builder: (context) => Text(MaterialLocalizations.of(context).closeButtonTooltip)),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('关闭'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('root navigator modal chrome receives Flutter localization', (tester) async {
    await tester.pumpWidget(WidgetsApp(
      color: Colors.black,
      locale: const Locale('zh', 'CN'),
      supportedLocales: const [Locale('zh', 'CN')],
      localizationsDelegates: multiViewFlutterLocalizations,
      pageRouteBuilder: <T>(settings, builder) => PageRouteBuilder<T>(
        settings: settings,
        pageBuilder: (context, animation, secondaryAnimation) => builder(context),
      ),
      home: MultiViewMaterialScope(
        child: Theme(
          data: ThemeData.dark(useMaterial3: true),
          child: Scaffold(
            body: Builder(
                builder: (pageContext) => Center(
                      child: TextButton(
                        onPressed: () => showModalBottomSheet<void>(
                          context: pageContext,
                          useRootNavigator: true,
                          showDragHandle: true,
                          builder: (sheetContext) => MultiViewMaterialScope(
                            child: SizedBox(
                              height: 180,
                              child: Column(children: [
                                const Text('此路声音'),
                                TextButton(
                                  onPressed: () => Navigator.pop(sheetContext),
                                  child: Text(MaterialLocalizations.of(sheetContext).closeButtonTooltip),
                                ),
                              ]),
                            ),
                          ),
                        ),
                        child: const Text('设置'),
                      ),
                    )),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('设置'));
    await tester.pumpAndSettle();
    expect(find.text('此路声音'), findsOneWidget);
    expect(find.text('关闭'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('关闭'));
    await tester.pumpAndSettle();
    expect(find.text('此路声音'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
