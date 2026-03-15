import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'update_models.dart';
import 'update_service.dart';

class IOSUpdateService implements UpdateService {
  @override
  bool get supportsInAppUpdates => false;

  @override
  String get settingsTitle => 'App Updates';

  @override
  String get settingsSubtitle => 'Install updates from the App Store or TestFlight';

  @override
  Future<UpdateCheckResult> checkForUpdate() async {
    final packageInfo = await PackageInfo.fromPlatform();
    final version = packageInfo.version.trim();

    return UpdateCheckResult(
      availability: UpdateAvailability.unavailable,
      currentVersionLabel: version.isEmpty ? '-' : version,
      message: 'On iOS, updates are installed from the App Store or TestFlight.',
    );
  }

  @override
  Future<void> showRequiredUpdateDialog(
    BuildContext context,
    UpdateCheckResult result,
  ) async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('App Updates'),
        content: const Text(
          'On iOS, install new versions from the App Store or TestFlight.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }
}
