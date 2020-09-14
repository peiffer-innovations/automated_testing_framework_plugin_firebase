import 'dart:typed_data';

import 'package:automated_testing_framework/automated_testing_framework.dart';
import 'package:convert/convert.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:json_class/json_class.dart';
import 'package:logging/logging.dart';

/// Test Store for the Automated Testing Framework that can read and write tests
/// to Firebase Realtime Database.  This optionally can save screenshots to
/// Firebase Storage, when initialized and not on the `web` platform.
class FirebaseTestStore {
  /// Initializes the test store.  This requires the [FirebaseDatabase] to be
  /// assigned and initialized.
  ///
  /// The [imagePath] is optional and is the path within Firebase Storage where
  /// the screenshots must be saved.  If omitted, this defaults to 'images'.
  /// This only is utilized if the [storage] is not-null.  If the [storage] is
  /// null then this is ignored and screenshots are not uploaded.
  ///
  /// The [testCollectionPath] is optional and is the collection within Firebase
  /// Realtime Databse where the tests themselves must be saved.  If omitted,
  /// this defaults to 'tests'.
  ///
  /// The [reportCollectionPath] is optional and is the collection within
  /// Firebase Realtime Database where the test reports must be saved.  If
  /// omitted, this defaults to 'reports'.
  FirebaseTestStore({
    @required this.db,
    this.imagePath,
    this.reportCollectionPath,
    this.storage,
    this.testCollectionPath,
  }) : assert(db != null);

  static final Logger _logger = Logger('FirebaseTestStore');

  /// The initialized Firebase Realtime Database reference that will be used to
  /// save tests, read tests, or submit test reports.
  final FirebaseDatabase db;

  /// Optional path for screenshots to be uploated to within Firebase Storage.
  /// If [storage] is null or if this is on the web platform, this value is
  /// ignored.
  final String imagePath;

  /// Optional collection path to store test reports.  If omitted, this defaults
  /// to 'reports'.  Provided to allow for a single Firebase instance the
  /// ability to host multiple applications or environments.
  final String reportCollectionPath;

  /// Optional [FirebaseStorage] reference object.  If set, and the platform is
  /// not web, then this will be used to upload screenshot results from test
  /// reports.  If omitted, screenshots will not be uploaded anywhere and will
  /// be lost if this test store is used for test reports.
  final FirebaseStorage storage;

  /// Optional collection path to store test data.  If omitted, this defaults
  /// to 'tests'.  Provided to allow for a single Firebase instance the ability
  /// to host multiple applications or environments.
  final String testCollectionPath;

  /// Implementation of the [TestReader] functional interface that can read test
  /// data from Firebase Realtime Database.
  Future<List<PendingTest>> testReader(BuildContext context) async {
    List<PendingTest> results;

    try {
      results = [];
      var actualCollectionPath = (testCollectionPath ?? 'tests');

      var ref = db.reference().child(actualCollectionPath);
      var snapshot = await ref.once();

      var docs = snapshot.value;
      docs.forEach((key, doc) {
        var data = doc;
        var pTest = PendingTest(
          loader: AsyncTestLoader(({bool ignoreImages}) async {
            var version = JsonClass.parseInt(data['version']);
            return Test(
              active: JsonClass.parseBool(data['active']),
              name: data['name'],
              steps: JsonClass.fromDynamicList(
                data['steps'],
                (entry) => TestStep.fromDynamic(
                  entry,
                  ignoreImages: true,
                ),
              ),
              version: version,
            );
          }),
          name: data['name'],
          numSteps: data['steps']?.length ?? 0,
          version: data['version'],
        );

        results.add(pTest);
      });
    } catch (e, stack) {
      _logger.severe('Error loading tests', e, stack);
    }

    return results ?? <PendingTest>[];
  }

  /// Implementation of the [TestReport] functional interface that can submit
  /// test reports to Firebase Realtime Database.
  Future<bool> testReporter(TestReport report) async {
    var result = false;

    var actualCollectionPath = (reportCollectionPath ?? 'reports');

    var doc = db
        .reference()
        .child(actualCollectionPath)
        .child(hex.encode(report.name.codeUnits))
        .child('v${report.version}')
        .child(hex.encode(
            '${report.deviceInfo.deviceSignature}_${report.startTime.millisecondsSinceEpoch}'
                .codeUnits));

    await doc.set({
      'deviceInfo': report.deviceInfo.toJson(),
      'endTime': report.endTime?.millisecondsSinceEpoch,
      'errorSteps': report.errorSteps,
      'images': report.images.map((entity) => entity.hash).toList(),
      'invertedStartTime': -1 * report.startTime.millisecondsSinceEpoch,
      'logs': report.logs,
      'name': report.name,
      'passedSteps': report.passedSteps,
      'runtimeException': report.runtimeException,
      'startTime': report.startTime.millisecondsSinceEpoch,
      'steps': JsonClass.toJsonList(report.steps),
      'success': report.success,
      'version': report.version,
    });

    if (!kIsWeb && storage != null) {
      for (var image in report.images) {
        var ref = storage
            .ref()
            .child(imagePath ?? 'images')
            .child('${image.hash}.png');
        var uploadTask = ref.putData(
          image.image,
          StorageMetadata(contentType: 'image/png'),
        );

        int lastProgress = -10;
        uploadTask.events.listen((event) {
          int progress =
              event.snapshot.bytesTransferred ~/ event.snapshot.totalByteCount;
          if (lastProgress + 10 <= progress) {
            _logger.log(Level.FINER, 'Image: ${image.hash} -- $progress%');
            lastProgress = progress;
          }
        });

        await uploadTask.onComplete;
      }
    }

    return result;
  }

  /// Implementation of the [TestWriter] functional interface that can submit
  /// test data to Firebase Realtime Database.
  Future<bool> testWriter(
    BuildContext context,
    Test test,
  ) async {
    var result = false;

    try {
      var actualCollectionPath = (testCollectionPath ?? 'tests');

      var id = hex.encoder.convert(test.name.codeUnits);

      int version = (test.version ?? 0) + 1;

      var testData = test
          .copyWith(
            steps: test.steps
                .map((e) => e.copyWith(image: Uint8List.fromList([])))
                .toList(),
            version: version,
          )
          .toJson();

      await db.reference().child(actualCollectionPath).child(id).set(testData);

      result = true;
    } catch (e, stack) {
      _logger.severe('Error writing test', e, stack);
    }
    return result;
  }
}
