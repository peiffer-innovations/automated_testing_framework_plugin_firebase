import 'package:automated_testing_framework/automated_testing_framework.dart';
import 'package:automated_testing_framework_plugin_firebase/automated_testing_framework_plugin_firebase.dart';
import 'package:json_class/json_class.dart';

/// Test step that asserts that the value equals (or does not equal) a specific
/// value.
class AssertFirebaseValueStep extends TestRunnerStep {
  AssertFirebaseValueStep({
    required this.equals,
    required this.path,
    required this.value,
  }) : assert(path.isNotEmpty == true);

  static const id = 'assert_firebase_value';

  static List<String> get behaviorDrivenDescriptions => List.unmodifiable([
        "assert that the value in firebase's `{{path}}` path is `{{equals}}` to `{{value}}`.",
      ]);

  /// Set to [true] if the value from the [Testable] must equal the set [value].
  /// Set to [false] if the value from the [Testable] must not equal the
  /// [value].
  final bool equals;

  /// The path to look for the Document in.
  final String path;

  /// The [value] to test againt when comparing the [Testable]'s value.
  final String? value;

  @override
  String get stepId => id;

  /// Creates an instance from a JSON-like map structure.  This expects the
  /// following format:
  ///
  /// ```json
  /// {
  ///   "equals": <bool>,
  ///   "path": <String>,
  ///   "value": <String>
  /// }
  /// ```
  ///
  /// See also:
  /// * [JsonClass.parseBool]
  static AssertFirebaseValueStep? fromDynamic(dynamic map) {
    AssertFirebaseValueStep? result;

    if (map != null) {
      result = AssertFirebaseValueStep(
        equals:
            map['equals'] == null ? true : JsonClass.parseBool(map['equals']),
        path: map['path']!,
        value: map['value']?.toString(),
      );
    }

    return result;
  }

  /// Executes the step.  This will first look for the Document then compare the
  /// value form the document to the [value].
  @override
  Future<void> execute({
    required CancelToken cancelToken,
    required TestReport report,
    required TestController tester,
  }) async {
    final path = tester.resolveVariable(this.path);
    final value = tester.resolveVariable(this.value);
    assert(path.isNotEmpty == true);

    final name = "assert_firebase_value('$path', '$value', '$equals')";
    log(
      name,
      tester: tester,
    );

    final firebase = TestFirebaseHelper.firebase;

    final doc = firebase.ref().child(path);
    final data = (await doc.once()).snapshot.value?.toString();

    if ((data == value) != equals) {
      throw Exception(
        'document: [$path] -- actualValue: [$data] ${equals == true ? '!=' : '=='} [$value].',
      );
    }
  }

  @override
  String getBehaviorDrivenDescription(TestController tester) {
    var result = behaviorDrivenDescriptions[0];

    result = result.replaceAll(
      '{{equals}}',
      equals == true ? 'equal' : 'not equal',
    );
    result = result.replaceAll('{{path}}', path);
    result = result.replaceAll('{{value}}', value ?? 'null');

    return result;
  }

  /// Converts this to a JSON compatible map.  For a description of the format,
  /// see [fromDynamic].
  @override
  Map<String, dynamic> toJson() => {
        'equals': equals,
        'path': path,
        'value': value,
      };
}
