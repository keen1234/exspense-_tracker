import 'package:flutter/material.dart';

import 'update_models.dart';
import 'update_service.dart';

class UnsupportedUpdateService implements UpdateService {
  @override
  bool get supportsInAppUpdates => false;

  @override
  String get settingsTitle => 'App Updates';

  @override
  String get settingsSubtitle => 'Updates are not managed inside this build';

  @override
  Future<UpdateCheckResult> checkForUpdate() async {
    return const UpdateCheckResult(
      availability: UpdateAvailability.unavailable,
      currentVersionLabel: '-',
      message: 'Automatic updates are not available on this platform.',
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
          'Automatic updates are not available on this platform.',
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
