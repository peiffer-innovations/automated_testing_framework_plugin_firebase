import 'dart:convert';

import 'package:automated_testing_framework/automated_testing_framework.dart';
import 'package:automated_testing_framework_plugin_firebase/automated_testing_framework_plugin_firebase.dart';
// ignore: import_of_legacy_library_into_null_safe
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:form_validation/form_validation.dart';
import 'package:static_translations/static_translations.dart';

/// Helper for the Firebase reference that the automated testing framework will
/// use when running the tests.  Set the static [firebase] value to the one to
/// use within the test steps.
///
/// This also provides a simple way to ensure all the test steps are registered
/// on the [TestStepRegistry] via the [registerTestSteps] function.
class TestFirebaseHelper {
  /// A config variable that instructs the JSON value to autoformat the JSON as
  /// it is being entered or not.  Set to [true] to enable the autoformatter.
  /// Set to `null` or [false] to disable it.
  static bool autoformatJson = false;
  static FirebaseDatabase? _firebase;

  static Widget buildJsonEditText({
    required BuildContext context,
    required String id,
    String? defaultValue,
    required TranslationEntry label,
    List<ValueValidator>? validators,
    required Map<String, dynamic> values,
  }) {
    assert(id.isNotEmpty == true);

    if (values[id] == null && defaultValue != null) {
      values[id] = defaultValue;
    }

    final translator = Translator.of(context);
    final encoder = const JsonEncoder.withIndent('  ');
    var initialValue = values[id]?.toString();
    if (initialValue?.isNotEmpty == true) {
      try {
        initialValue = encoder.convert(json.decode(initialValue!));
      } catch (e) {
        // no-op
      }
    }

    return TextFormField(
      autovalidateMode: validators?.isNotEmpty == true
          ? AutovalidateMode.always
          : AutovalidateMode.disabled,
      decoration: InputDecoration(
        labelText: translator.translate(label),
      ),
      initialValue: initialValue,
      inputFormatters:
          autoformatJson == true ? [_JsonTextInputFormatter()] : null,
      maxLines: 5,
      onChanged: (value) {
        var encoded = '';

        try {
          encoded = json.encode(json.decode(value));
        } catch (e) {
          encoded = '';
        }
        values[id] = encoded;
      },
      onEditingComplete: () {},
      smartQuotesType: SmartQuotesType.disabled,
      validator: (value) => validators?.isNotEmpty == true
          ? Validator(validators: validators!).validate(
              context: context,
              label: translator.translate(label),
              value: value,
            )
          : null,
    );
  }

  /// Returns either the custom set [FirebaseDatabase] reference, or the
  /// default instance if one has not been set.
  static FirebaseDatabase get firebase =>
      _firebase ?? FirebaseDatabase.instance;

  /// Sets the custom [FirebaseDatabase] reference for the test steps to use.
  /// Set to `null` to use the default reference.
  static set firebase(FirebaseDatabase firebase) => _firebase = firebase;

  /// Registers the test steps to the optional [registry].  If not set, the
  /// default [TestStepRegistry] will be used.
  static void registerTestSteps([TestStepRegistry? registry]) {
    (registry ?? TestStepRegistry.instance).registerCustomSteps([
      TestStepBuilder(
        availableTestStep: const AvailableTestStep(
          form: AssertFirebaseValueForm(),
          help:
              TestFirebaseTranslations.atf_firebase_help_assert_firebase_value,
          id: AssertFirebaseValueStep.id,
          keys: {'equals', 'path', 'value'},
          quickAddValues: null,
          title:
              TestFirebaseTranslations.atf_firebase_title_assert_firebase_value,
          widgetless: true,
          type: null,
        ),
        testRunnerStepBuilder: AssertFirebaseValueStep.fromDynamic,
      ),
      TestStepBuilder(
        availableTestStep: const AvailableTestStep(
          form: SetFirebaseValueForm(),
          help: TestFirebaseTranslations.atf_firebase_help_set_firebase_value,
          id: SetFirebaseValueStep.id,
          keys: {'path', 'value'},
          quickAddValues: null,
          title: TestFirebaseTranslations.atf_firebase_title_set_firebase_value,
          widgetless: true,
          type: null,
        ),
        testRunnerStepBuilder: SetFirebaseValueStep.fromDynamic,
      ),
    ]);
  }
}

class _JsonTextInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final encoder = const JsonEncoder.withIndent('  ');
    var encoded = newValue.text;

    try {
      encoded = encoder.convert(json.decode(encoded));
    } catch (e) {
      // no-op
    }

    return encoded == newValue.text
        ? newValue
        : TextEditingValue(text: encoded);
  }
}
