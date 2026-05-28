import 'dart:io';

import 'package:flutter/material.dart';

import 'update_models.dart';
import 'update_service_android.dart';
import 'update_service_ios.dart';
import 'update_service_unsupported.dart';

abstract class UpdateService {
  factory UpdateService() {
    if (Platform.isAndroid) {
      return AndroidUpdateService();
    }
    if (Platform.isIOS) {
      return IOSUpdateService();
    }
    return UnsupportedUpdateService();
  }

  bool get supportsInAppUpdates;
  String get settingsTitle;
  String get settingsSubtitle;

  Future<UpdateCheckResult> checkForUpdate();

  Future<void> showRequiredUpdateDialog(
    BuildContext context,
    UpdateCheckResult result,
  );
}
