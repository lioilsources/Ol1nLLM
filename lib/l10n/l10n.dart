import 'package:flutter/widgets.dart';

import 'app_localizations.dart';

export 'app_localizations.dart';

extension L10nContext on BuildContext {
  /// Localized strings for this context. Widget tests that pump a bare
  /// MaterialApp without the delegates get the Czech source strings.
  AppLocalizations get l10n =>
      AppLocalizations.of(this) ?? lookupAppLocalizations(const Locale('cs'));
}
