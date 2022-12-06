import 'package:automated_testing_framework/automated_testing_framework.dart';
import 'package:automated_testing_framework_plugin_firebase/automated_testing_framework_plugin_firebase.dart';
import 'package:flutter/material.dart';
import 'package:form_validation/form_validation.dart';
import 'package:static_translations/static_translations.dart';

class SetFirebaseValueForm extends TestStepForm {
  const SetFirebaseValueForm();

  @override
  bool get supportsMinified => true;

  @override
  TranslationEntry get title =>
      TestFirebaseTranslations.atf_firebase_title_set_firebase_value;

  @override
  Widget buildForm(
    BuildContext context,
    Map<String, dynamic>? values, {
    bool minify = false,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        if (minify != true)
          buildHelpSection(
            context,
            TestFirebaseTranslations.atf_firebase_help_set_firebase_value,
            minify: minify,
          ),
        buildValuesSection(
          context,
          [
            buildEditText(
              context: context,
              id: 'path',
              label: TestFirebaseTranslations.atf_firebase_form_path,
              validators: [
                RequiredValidator(),
              ],
              values: values!,
            ),
            const SizedBox(height: 16.0),
            TestFirebaseHelper.buildJsonEditText(
              context: context,
              id: 'value',
              label: TestStepTranslations.atf_form_value,
              validators: [RequiredValidator()],
              values: values,
            ),
          ],
          minify: minify,
        ),
      ],
    );
  }
}
