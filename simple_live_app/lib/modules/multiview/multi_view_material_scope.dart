import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

/// Register at the app root as well: modal-route chrome lives above page scopes.
const multiViewFlutterLocalizations = <LocalizationsDelegate<dynamic>>[
  GlobalMaterialLocalizations.delegate,
  GlobalWidgetsLocalizations.delegate,
  GlobalCupertinoLocalizations.delegate,
];

/// material_ui and Flutter Material expose different localization types.
/// This boundary supplies Flutter's types for the multi-view workspace.
class MultiViewMaterialScope extends StatelessWidget {
  const MultiViewMaterialScope({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Localizations.override(
        context: context,
        delegates: multiViewFlutterLocalizations,
        child: child,
      );
}
