import 'dart:convert';
import 'dart:math';

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
    required this.db,
    this.goldenImageCollectionPath,
    this.imagePath,
    this.reportCollectionPath,
    this.reportMetadataCollectionPath,
    this.storage,
    this.testCollectionPath,
  });

  static final Logger _logger = Logger('FirebaseTestStore');

  /// The initialized Firebase Realtime Database reference that will be used to
  /// save tests, read tests, or submit test reports.
  final FirebaseDatabase db;

  /// Optional collection path to store golden image metadata.  If omitted, this
  /// defaults to 'goldens'.  Provided to allow for a single Firebase instance
  /// the ability to host multiple applications or environments.
  final String? goldenImageCollectionPath;

  /// Optional path for screenshots to be uploated to within Firebase Storage.
  /// If [storage] is null or if this is on the web platform, this value is
  /// ignored.
  final String? imagePath;

  /// Optional collection path to store test reports.  If omitted, this defaults
  /// to 'reports'.  Provided to allow for a single Firebase instance the
  /// ability to host multiple applications or environments.
  final String? reportCollectionPath;

  /// Optional collection path to store test report metadata.  If omitted, this
  /// defaults to 'reportMetadata'.  Provided to allow for a single Firebase
  /// instance the The bability to host multiple applications or environments.
  final String? reportMetadataCollectionPath;

  /// Optional [FirebaseStorage] reference object.  If set, and the platform is
  /// not web, then this will be used to upload screenshot results from test
  /// reports.  If omitted, screenshots will not be uploaded anywhere and will
  /// be lost if this test store is used for test reports.
  final FirebaseStorage? storage;

  /// Optional collection path to store test data.  If omitted, this defaults
  /// to 'tests'.  Provided to allow for a single Firebase instance the ability
  /// to host multiple applications or environments.
  final String? testCollectionPath;

  GoldenTestImages? _currentGoldenTestImages;

  /// Writes the golden images from the [report] to Cloud Storage (if it is set)
  /// and also writes the metadata that allows the reading of the golden images.
  /// This will throw an exception on failure.
  Future<void> goldenImageWriter(TestReport report) async {
    final actualCollectionPath = goldenImageCollectionPath ?? 'goldens';

    final id = _getGoldenImageId(report);

    final data = <String, String>{};
    for (var image in report.images) {
      if (image.goldenCompatible == true) {
        data[image.id] = image.hash;
      }
    }
    final golden = GoldenTestImages(
      deviceInfo: report.deviceInfo!,
      goldenHashes: data,
      suiteName: report.suiteName,
      testName: report.name!,
      testVersion: report.version,
    );

    if (!kIsWeb && storage != null) {
      final testStorage = FirebaseStorageTestStore(
        storage: storage!,
        imagePath: imagePath,
      );
      await testStorage.uploadImages(
        report,
        goldenOnly: true,
      );
    }

    await db.ref().child(actualCollectionPath).child(id).set(golden.toJson());
  }

  /// Reader to read a golden image from Cloud Storage.
  Future<Uint8List?> testImageReader({
    required TestDeviceInfo deviceInfo,
    required String imageId,
    String? suiteName,
    required String testName,
    int? testVersion,
  }) async {
    final goldenId = GoldenTestImages.createId(
      deviceInfo: deviceInfo,
      suiteName: suiteName,
      testName: testName,
    );
    GoldenTestImages? golden;
    if (_currentGoldenTestImages?.id == goldenId) {
      golden = _currentGoldenTestImages;
    } else {
      _logger.info('[GOLDEN_IMAGE]: downloading golden image hashes.');
      final actualCollectionPath = '${goldenImageCollectionPath ?? 'goldens'}';

      final id = hex.encode(utf8.encode(goldenId));

      final snapshot =
          await db.ref().child(actualCollectionPath).child(id).once();

      if (snapshot.snapshot.value == null) {
        _logger.info(
          '[GOLDEN_IMAGE]: [FAILED]: downloading golden image hashes.',
        );
      } else {
        final goldenJson = snapshot.snapshot.value;
        golden = GoldenTestImages.fromDynamic(goldenJson);
        _logger.info(
          '[GOLDEN_IMAGE]: [COMPLETE]: downloading golden image hashes.',
        );
      }
    }

    Uint8List? image;
    if (!kIsWeb && golden != null && storage != null) {
      final hash = golden.goldenHashes![imageId];
      final testStorage = FirebaseStorageTestStore(
        storage: storage!,
        imagePath: imagePath,
      );
      image = await testStorage.downloadImage(hash);
    }

    return image;
  }

  /// Implementation of the [TestReader] functional interface that can read test
  /// data from Firebase Realtime Database.
  Future<List<PendingTest>> testReader(
    BuildContext? context, {
    String? suiteName,
  }) async {
    List<PendingTest>? results;

    try {
      results = [];
      final actualCollectionPath = (testCollectionPath ?? 'tests');

      final ref = db.ref().child(actualCollectionPath);
      final snapshot = await ref.once();

      final docs = snapshot.snapshot.children;
      docs.forEach((doc) {
        final data = doc.value as Map;
        final pTest = PendingTest(
          active: JsonClass.parseBool(data['active']),
          loader: AsyncTestLoader(({bool? ignoreImages}) async {
            final version = JsonClass.parseInt(data['version'])!;
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
          results!.add(pTest);
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
    final result = false;

    final actualCollectionPath = (reportCollectionPath ?? 'reports');
    final actualMetadataCollectionPath =
        (reportMetadataCollectionPath ?? 'reportMetadata');

    final date = DateFormat('yyyy-MM-dd').format(report.endTime!.toUtc());
    final random = Random().nextInt(10000000);
    final pathId = hex.encode(
      utf8.encode(
        /// while not a truly _guaranteed_ unique key, the collision rate will be exceptionally low
        '${report.deviceInfo!.deviceSignature}_${report.startTime!.millisecondsSinceEpoch}_$random',
      ),
    );
    final doc = db.ref().child(actualCollectionPath).child(date).child(pathId);

    await doc.set(
      <String, dynamic>{
        'invertedStartTime': -1 * report.startTime!.millisecondsSinceEpoch,
      }..addAll(
          report.toJson(false),
        ),
    );

    final mdDoc =
        db.ref().child(actualMetadataCollectionPath).child(date).child(pathId);
    await mdDoc.set(<String, dynamic>{
      'invertedStartTime': -1 * report.startTime!.millisecondsSinceEpoch,
    }..addAll(TestReportMetadata.fromTestReport(
        report,
        id: pathId,
      )!
          .toJson()));

    if (!kIsWeb && storage != null) {
      final testStorage = FirebaseStorageTestStore(
        storage: storage!,
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
      final actualCollectionPath = (testCollectionPath ?? 'tests');

      final oldId =
          hex.encoder.convert(utf8.encode('${test.id}_${test.version}'));
      final oldTest =
          await db.ref().child(actualCollectionPath).child(oldId).once();
      if (oldTest.snapshot.value != null) {
        // deactivate the old test
        await db
            .ref()
            .child(actualCollectionPath)
            .child(oldId)
            .child('active')
            .set(false);
      }

      final version = test.version + 1;
      final id = hex.encoder.convert(utf8.encode('${test.id}_$version'));

      final testData = test
          .copyWith(
            steps: test.steps
                .map((e) => e.copyWith(image: Uint8List.fromList([])))
                .toList(),
            timestamp: DateTime.now(),
            version: version,
          )
          .toJson();

      await db.ref().child(actualCollectionPath).child(id).set(testData);

      result = true;
    } catch (e, stack) {
      _logger.severe('Error writing test', e, stack);
      try {
        ScaffoldMessenger.of(context).showSnackBar(
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
