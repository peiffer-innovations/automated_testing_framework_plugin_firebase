import 'package:automated_testing_framework/automated_testing_framework.dart';
import 'package:automated_testing_framework_plugin_firebase/automated_testing_framework_plugin_firebase.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('assert_firebase_value', () {
    TestFirebaseHelper.registerTestSteps();
    var availStep = TestStepRegistry.instance.getAvailableTestStep(
      'assert_firebase_value',
    )!;

    expect(availStep.form.runtimeType, AssertFirebaseValueForm);
    expect(availStep.help,
        TestFirebaseTranslations.atf_firebase_help_assert_firebase_value);
    expect(availStep.id, 'assert_firebase_value');
    expect(
      availStep.title,
      TestFirebaseTranslations.atf_firebase_title_assert_firebase_value,
    );
    expect(availStep.type, null);
    expect(availStep.widgetless, true);
  });

  test('set_firebase_value', () {
    TestFirebaseHelper.registerTestSteps();
    var availStep = TestStepRegistry.instance.getAvailableTestStep(
      'set_firebase_value',
    )!;

    expect(availStep.form.runtimeType, SetFirebaseValueForm);
    expect(availStep.help,
        TestFirebaseTranslations.atf_firebase_help_set_firebase_value);
    expect(availStep.id, 'set_firebase_value');
    expect(
      availStep.title,
      TestFirebaseTranslations.atf_firebase_title_set_firebase_value,
    );
    expect(availStep.type, null);
    expect(availStep.widgetless, true);
  });
}
