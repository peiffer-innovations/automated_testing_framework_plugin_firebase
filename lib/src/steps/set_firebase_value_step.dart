import 'package:automated_testing_framework/automated_testing_framework.dart';
import 'package:automated_testing_framework_plugin_firebase/automated_testing_framework_plugin_firebase.dart';
import 'package:flutter/material.dart';
import 'package:meta/meta.dart';

/// Sets a value on the identified Firebase Document identified by the
/// [collectionPath] and [documentId].
class SetFirebaseValueStep extends TestRunnerStep {
  SetFirebaseValueStep({
    @required this.path,
    @required this.value,
  })  : assert(path?.isNotEmpty == true),
        assert(value?.isNotEmpty == true);

  /// The path of the Document to look for.
  final String path;

  /// The string representation of the value to set.
  final String value;

  /// Creates an instance from a JSON-like map structure.  This expects the
  /// following format:
  ///
  /// ```json
  /// {
  ///   "path": <String>,
  ///   "value": <String>
  /// }
  /// ```
  static SetFirebaseValueStep fromDynamic(dynamic map) {
    SetFirebaseValueStep result;

    if (map != null) {
      result = SetFirebaseValueStep(
        path: map['path'],
        value: map['value']?.toString(),
      );
    }

    return result;
  }

  /// Attempts to locate the [Testable] identified by the [testableId] and will
  /// then set the associated [value] to the found widget.
  @override
  Future<void> execute({
    @required TestReport report,
    @required TestController tester,
  }) async {
    String path = tester.resolveVariable(this.path);
    String value = tester.resolveVariable(this.value);
    assert(path?.isNotEmpty == true);

    var name = "set_firebase_value('$path', '$value')";
    log(
      name,
      tester: tester,
    );

    var firebase = TestFirebaseHelper.firebase;

    var doc = firebase.reference().child(path);
    await doc.set(value);
  }

  /// Converts this to a JSON compatible map.  For a description of the format,
  /// see [fromDynamic].
  @override
  Map<String, dynamic> toJson() => {
        'path': path,
        'value': value,
      };
}
