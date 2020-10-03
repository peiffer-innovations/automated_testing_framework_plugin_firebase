import 'package:static_translations/static_translations.dart';

class TestFirebaseTranslations {
  static const atf_firebase_error_not_valid_json = TranslationEntry(
    key: 'atf_firebase_error_not_valid_json',
    value: 'Not valid JSON',
  );

  static const atf_firebase_error_exporting_test = TranslationEntry(
    key: 'atf_firebase_error_exporting_test',
    value: 'An error occurred while exporting the test.',
  );

  static const atf_firebase_form_path = TranslationEntry(
    key: 'atf_firebase_form_path',
    value: 'Path',
  );

  static const atf_firebase_help_assert_firebase_value = TranslationEntry(
    key: 'atf_firebase_help_assert_firebase_value',
    value:
        'Attempts to read a document from the path and compares it to a set value.',
  );

  static const atf_firebase_help_set_firebase_value = TranslationEntry(
    key: 'atf_firebase_help_set_firebase_value',
    value:
        'Attempts to create or update a document on the path with the given value.',
  );

  static const atf_firebase_title_assert_firebase_value = TranslationEntry(
    key: 'atf_firebase_title_assert_firebase_value',
    value: 'Assert Firebase Value',
  );

  static const atf_firebase_title_set_firebase_value = TranslationEntry(
    key: 'atf_firebase_title_set_firebase_value',
    value: 'Set Firebase Value',
  );
}
