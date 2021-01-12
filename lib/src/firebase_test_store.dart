import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:automated_testing_framework/automated_testing_framework.dart';
import 'package:automated_testing_framework_plugin_firebase/automated_testing_framework_plugin_firebase.dart';
import 'package:automated_testing_framework_plugin_firebase_storage/automated_testing_framework_plugin_firebase_storage.dart';
import 'package:convert/convert.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:json_class/json_class.dart';
import 'package:logging/logging.dart';
import 'package:static_translations/static_translations.dart';

/// Test Store for the Automated Testing Framework that can read and write tests
/// to Firebase Realtime Database.  This optionally can save screenshots to
/// Firebase Storage, when initialized and not on the `web` platform.
class FirebaseTestStore {
  /// Initializes the test store.  This requires the [FirebaseDatabase] to be
  /// assigned and initialized.
  ///
  /// The [goldenImageCollectionPath] is optional and is the path within
  /// Firebase Realtime Database where the metadata for the golden images must
  /// be saved.  If omitted, this defaults to 'goldens'.
  ///
  /// The [imagePath] is optional and is the path within Firebase Storage where
  /// the screenshots must be saved.  If omitted, this defaults to 'images'.
  /// This only is utilized if the [storage] is not-null.  If the [storage] is
  /// null then this is ignored and screenshots are not uploaded.
  ///
  /// The [reportMetadataCollectionPath] is optional and is the collection
  /// within Firebase Realtime Database test report metadata is saved.  If
  /// omitted, this defaults to 'reportMetadata'
  ///
  /// The [reportCollectionPath] is optional and is the collection within
  /// Firebase Realtime Database where the test reports must be saved.  If
  /// omitted, this defaults to 'reports'.
  ///
  /// The [testCollectionPath] is optional and is the collection within Firebase
  /// Realtime Database where the tests themselves must be saved.  If omitted,
  /// this defaults to 'tests'.
  FirebaseTestStore({
    @required this.db,
    this.goldenImageCollectionPath,
    this.imagePath,
    this.reportCollectionPath,
    this.reportMetadataCollectionPath,
    this.storage,
    this.testCollectionPath,
  }) : assert(db != null);

  static final Logger _logger = Logger('FirebaseTestStore');

  /// The initialized Firebase Realtime Database reference that will be used to
  /// save tests, read tests, or submit test reports.
  final FirebaseDatabase db;

  /// Optional collection path to store golden image metadata.  If omitted, this
  /// defaults to 'goldens'.  Provided to allow for a single Firebase instance
  /// the ability to host multiple applications or environments.
  final String goldenImageCollectionPath;

  /// Optional path for screenshots to be uploated to within Firebase Storage.
  /// If [storage] is null or if this is on the web platform, this value is
  /// ignored.
  final String imagePath;

  /// Optional collection path to store test reports.  If omitted, this defaults
  /// to 'reports'.  Provided to allow for a single Firebase instance the
  /// ability to host multiple applications or environments.
  final String reportCollectionPath;

  /// Optional collection path to store test report metadata.  If omitted, this
  /// defaults to 'reportMetadata'.  Provided to allow for a single Firebase
  /// instance the The bability to host multiple applications or environments.
  final String reportMetadataCollectionPath;

  /// Optional [FirebaseStorage] reference object.  If set, and the platform is
  /// not web, then this will be used to upload screenshot results from test
  /// reports.  If omitted, screenshots will not be uploaded anywhere and will
  /// be lost if this test store is used for test reports.
  final FirebaseStorage storage;

  /// Optional collection path to store test data.  If omitted, this defaults
  /// to 'tests'.  Provided to allow for a single Firebase instance the ability
  /// to host multiple applications or environments.
  final String testCollectionPath;

  GoldenTestImages _currentGoldenTestImages;

  /// Writes the golden images from the [report] to Cloud Storage (if it is set)
  /// and also writes the metadata that allows the reading of the golden images.
  /// This will throw an exception on failure.
  Future<void> goldenImageWriter(TestReport report) async {
    var actualCollectionPath = goldenImageCollectionPath ?? 'goldens';

    var id = _getGoldenImageId(report);

    var data = <String, String>{};
    for (var image in (report.images ?? <TestImage>[])) {
      if (image.goldenCompatible == true) {
        data[image.id] = image.hash;
      }
    }
    var golden = GoldenTestImages(
      deviceInfo: report.deviceInfo,
      goldenHashes: data,
      suiteName: report.suiteName,
      testName: report.name,
      testVersion: report.version,
    );

    if (!kIsWeb && storage != null) {
      var testStorage = FirebaseStorageTestStore(
        storage: storage,
        imagePath: imagePath,
      );
      await testStorage.uploadImages(
        report,
        goldenOnly: true,
      );
    }

    await db
        .reference()
        .child(actualCollectionPath)
        .child(id)
        .set(golden.toJson());
  }

  /// Reader to read a golden image from Cloud Storage.
  Future<Uint8List> testImageReader({
    @required TestDeviceInfo deviceInfo,
    @required String imageId,
    String suiteName,
    @required String testName,
    int testVersion,
  }) async {
    var goldenId = GoldenTestImages.createId(
      deviceInfo: deviceInfo,
      suiteName: suiteName,
      testName: testName,
    );
    GoldenTestImages golden;
    if (_currentGoldenTestImages?.id == goldenId) {
      golden = _currentGoldenTestImages;
    } else {
      var actualCollectionPath = '${goldenImageCollectionPath ?? 'goldens'}';

      var id = hex.encode(utf8.encode(goldenId));

      var snapshot =
          await db.reference().child(actualCollectionPath).child(id).once();
      if (snapshot.value != null) {
        var goldenJson = snapshot.value;
        golden = GoldenTestImages.fromDynamic(goldenJson);
      }
    }

    Uint8List image;
    if (!kIsWeb && golden != null && storage != null) {
      var hash = golden.goldenHashes[imageId];
      var testStorage = FirebaseStorageTestStore(
        storage: storage,
        imagePath: imagePath,
      );
      image = await testStorage.downloadImage(hash);
    }

    return image;
  }

  /// Implementation of the [TestReader] functional interface that can read test
  /// data from Firebase Realtime Database.
  Future<List<PendingTest>> testReader(
    BuildContext context, {
    String suiteName,
  }) async {
    List<PendingTest> results;

    try {
      results = [];
      var actualCollectionPath = (testCollectionPath ?? 'tests');

      var ref = db.reference().child(actualCollectionPath);
      var snapshot = await ref.once();

      var docs = snapshot.value;
      docs?.forEach((key, doc) {
        var data = doc;
        var pTest = PendingTest(
          active: JsonClass.parseBool(data['active']),
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
              suiteName: data['suiteName'],
              version: version,
            );
          }),
          name: data['name'],
          numSteps: data['steps']?.length ?? 0,
          suiteName: data['suiteName'],
          version: data['version'],
        );

        if (pTest.active == true && suiteName == null ||
            pTest.suiteName == suiteName) {
          results.add(pTest);
        }
      });
    } catch (e, stack) {
      _logger.severe('Error loading tests', e, stack);
    }

    return results ?? <PendingTest>[];
  }

  /// Implementation of the [TestReport] functional interface that can submit
  /// test reports to Firebase Realtime Database.  This will collect
  /// all reports under a single day (as defined by the UTC time zone) in the
  /// same parent collection path.
  Future<bool> testReporter(TestReport report) async {
    var result = false;

    var actualCollectionPath = (reportCollectionPath ?? 'reports');
    var actualMetadataCollectionPath =
        (reportMetadataCollectionPath ?? 'reportMetadata');

    var date = DateFormat('yyyy-MM-dd').format(report.endTime.toUtc());
    var random = Random().nextInt(10000000);
    var pathId = hex.encode(
      utf8.encode(
        /// while not a truly _guaranteed_ unique key, the collision rate will be exceptionally low
        '${report.deviceInfo.deviceSignature}_${report.startTime.millisecondsSinceEpoch}_$random',
      ),
    );
    var doc =
        db.reference().child(actualCollectionPath).child(date).child(pathId);

    await doc.set(
      <String, dynamic>{
        'invertedStartTime': -1 * report.startTime.millisecondsSinceEpoch,
      }..addAll(
          report.toJson(false),
        ),
    );

    var mdDoc = db
        .reference()
        .child(actualMetadataCollectionPath)
        .child(date)
        .child(pathId);
    await mdDoc.set(<String, dynamic>{
      'invertedStartTime': -1 * report.startTime.millisecondsSinceEpoch,
    }..addAll(TestReportMetadata.fromTestReport(
        report,
        id: pathId,
      ).toJson()));

    if (!kIsWeb && storage != null) {
      var testStorage = FirebaseStorageTestStore(
        storage: storage,
        imagePath: imagePath,
      );
      await testStorage.uploadImages(report);
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

      var oldId =
          hex.encoder.convert(utf8.encode('${test.id}_${test.version}'));
      var oldTest =
          await db.reference().child(actualCollectionPath).child(oldId).once();
      if (oldTest.value != null) {
        // deactivate the old test
        await db
            .reference()
            .child(actualCollectionPath)
            .child(oldId)
            .child('active')
            .set(false);
      }

      var version = (test.version ?? 0) + 1;
      var id = hex.encoder.convert(utf8.encode('${test.id}_$version'));

      var testData = test
          .copyWith(
            steps: test.steps
                .map((e) => e.copyWith(image: Uint8List.fromList([])))
                .toList(),
            timestamp: DateTime.now(),
            version: version,
          )
          .toJson();

      await db.reference().child(actualCollectionPath).child(id).set(testData);

      result = true;
    } catch (e, stack) {
      _logger.severe('Error writing test', e, stack);
      try {
        // ignore: deprecated_member_use
        Scaffold.of(context).showSnackBar(
          SnackBar(
            content: Text(
              Translator.of(context).translate(
                TestFirebaseTranslations.atf_firebase_error_exporting_test,
              ),
            ),
          ),
        );
      } catch (e2) {
        // no-op
      }
    }
    return result;
  }

  String _getGoldenImageId(TestReport report) =>
      hex.encode(utf8.encode(GoldenTestImages.createIdFromReport(report)));
}
