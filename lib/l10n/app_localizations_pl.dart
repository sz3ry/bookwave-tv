// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Polish (`pl`).
class AppLocalizationsPl extends AppLocalizations {
  AppLocalizationsPl([String locale = 'pl']) : super(locale);

  @override
  String get appTitle => 'Bookwave TV';

  @override
  String get loginTitle => 'Zaloguj się do Storytel';

  @override
  String get email => 'E-mail';

  @override
  String get password => 'Hasło';

  @override
  String get loginButton => 'Zaloguj';

  @override
  String get loginRejected => 'Nieprawidłowy e-mail lub hasło';

  @override
  String get loginFailed => 'Nie udało się zalogować. Spróbuj ponownie.';

  @override
  String get library => 'Biblioteka';

  @override
  String get libraryEmpty =>
      'Na półce nie ma audiobooków. Dodaj książkę w Bookwave albo w aplikacji Storytel.';

  @override
  String get noConnection => 'Brak połączenia. Ponawiam…';

  @override
  String get play => 'Odtwórz';

  @override
  String get pause => 'Pauza';

  @override
  String get finished => 'Koniec książki';
}
