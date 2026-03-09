import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

enum UpdateAvailability { upToDate, updateAvailable, unavailable }

class UpdateInfo {
  final String version;
  final int buildNumber;
  final String downloadUrl;
  final String assetName;
  final String? releaseNotes;

  const UpdateInfo({
    required this.version,
    required this.buildNumber,
    required this.downloadUrl,
    required this.assetName,
    this.releaseNotes,
  });
}

class UpdateCheckResult {
  final UpdateAvailability availability;
  final String currentVersionLabel;
  final UpdateInfo? updateInfo;
  final String? message;

  const UpdateCheckResult({
    required this.availability,
    required this.currentVersionLabel,
    this.updateInfo,
    this.message,
  });

  bool get hasUpdate =>
      availability == UpdateAvailability.updateAvailable && updateInfo != null;
}

class UpdateService {
  static const String _owner = 'keen1234';
  static const String _repo = 'exspense-_tracker';

  Future<UpdateCheckResult> checkForUpdate() async {
    if (!Platform.isAndroid) {
      return const UpdateCheckResult(
        availability: UpdateAvailability.unavailable,
        currentVersionLabel: '-',
        message: 'Automatic updates are available on Android only.',
      );
    }

    final packageInfo = await PackageInfo.fromPlatform();
    final currentVersion = _normalizeVersion(packageInfo.version);
    final currentBuildNumber = int.tryParse(packageInfo.buildNumber) ?? 0;
    final currentVersionLabel = _buildVersionLabel(
      currentVersion,
      currentBuildNumber,
    );

    final release = await _fetchLatestRelease();
    if (release == null) {
      return UpdateCheckResult(
        availability: UpdateAvailability.unavailable,
        currentVersionLabel: currentVersionLabel,
        message: 'Unable to check for updates right now.',
      );
    }

    final latestVersion = _normalizeVersion(release['tag_name'] as String? ?? release['name'] as String? ?? '');
    if (latestVersion.isEmpty) {
      return UpdateCheckResult(
        availability: UpdateAvailability.unavailable,
        currentVersionLabel: currentVersionLabel,
        message: 'Latest release version is invalid.',
      );
    }

    final assets = (release['assets'] as List<dynamic>? ?? [])
        .whereType<Map>()
        .map((asset) => Map<String, dynamic>.from(asset))
        .toList();

    final apkAsset = assets.cast<Map<String, dynamic>?>().firstWhere(
      (asset) => (asset?['name'] as String? ?? '').toLowerCase().endsWith('.apk'),
      orElse: () => null,
    );

    if (apkAsset == null) {
      return UpdateCheckResult(
        availability: UpdateAvailability.unavailable,
        currentVersionLabel: currentVersionLabel,
        message: 'No APK file was found in the latest release.',
      );
    }

    final assetName = apkAsset['name'] as String;
    final latestBuildNumber = _extractBuildNumber(assetName);
    final shouldUpdate = _compareVersions(latestVersion, currentVersion) > 0 ||
        (_compareVersions(latestVersion, currentVersion) == 0 && latestBuildNumber > currentBuildNumber);

    if (!shouldUpdate) {
      return UpdateCheckResult(
        availability: UpdateAvailability.upToDate,
        currentVersionLabel: currentVersionLabel,
        message: 'You already have the latest version installed.',
      );
    }

    return UpdateCheckResult(
      availability: UpdateAvailability.updateAvailable,
      currentVersionLabel: currentVersionLabel,
      updateInfo: UpdateInfo(
        version: latestVersion,
        buildNumber: latestBuildNumber,
        downloadUrl: apkAsset['browser_download_url'] as String,
        assetName: assetName,
        releaseNotes: release['body'] as String?,
      ),
    );
  }

  Future<void> showRequiredUpdateDialog(
    BuildContext context,
    UpdateCheckResult result,
  ) async {
    final updateInfo = result.updateInfo;
    if (updateInfo == null) {
      return;
    }

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => PopScope(
        canPop: false,
        child: AlertDialog(
          title: const Text('Update Required'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'This application needs to be updated before you continue.',
              ),
              const SizedBox(height: 12),
              Text('Current version: ${result.currentVersionLabel}'),
              Text(
                'Required version: ${_buildVersionLabel(updateInfo.version, updateInfo.buildNumber)}',
              ),
              if ((updateInfo.releaseNotes ?? '').trim().isNotEmpty) ...[
                const SizedBox(height: 12),
                const Text(
                  'What\'s new',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                Text(
                  updateInfo.releaseNotes!.trim(),
                  maxLines: 6,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: SystemNavigator.pop,
              child: const Text('Close App'),
            ),
            ElevatedButton(
              onPressed: () async {
                final opened = await openUpdate(updateInfo);
                if (!dialogContext.mounted) {
                  return;
                }
                if (!opened) {
                  ScaffoldMessenger.of(dialogContext).showSnackBar(
                    const SnackBar(content: Text('Unable to open update link')),
                  );
                }
              },
              child: const Text('Update Now'),
            ),
          ],
        ),
      ),
    );
  }

  Future<bool> openUpdate(UpdateInfo updateInfo) async {
    final uri = Uri.parse(updateInfo.downloadUrl);
    return launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<Map<String, dynamic>?> _fetchLatestRelease() async {
    final client = HttpClient();
    try {
      final request = await client.getUrl(
        Uri.parse('https://api.github.com/repos/$_owner/$_repo/releases/latest'),
      );
      request.headers.set(HttpHeaders.acceptHeader, 'application/vnd.github+json');
      request.headers.set(HttpHeaders.userAgentHeader, 'expense-tracker-app');

      final response = await request.close();
      if (response.statusCode != HttpStatus.ok) {
        return null;
      }

      final responseBody = await response.transform(utf8.decoder).join();
      final decoded = jsonDecode(responseBody);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
      if (decoded is Map) {
        return Map<String, dynamic>.from(decoded);
      }
      return null;
    } finally {
      client.close(force: true);
    }
  }

  String _normalizeVersion(String rawVersion) {
    final trimmed = rawVersion.trim();
    if (trimmed.isEmpty) {
      return '';
    }

    final withoutPrefix = trimmed.startsWith('v') || trimmed.startsWith('V')
        ? trimmed.substring(1)
        : trimmed;
    return withoutPrefix.split('+').first.trim();
  }

  int _compareVersions(String left, String right) {
    final leftParts = left.split('.').map((part) => int.tryParse(part) ?? 0).toList();
    final rightParts = right.split('.').map((part) => int.tryParse(part) ?? 0).toList();
    final maxLength = leftParts.length > rightParts.length ? leftParts.length : rightParts.length;

    for (var i = 0; i < maxLength; i++) {
      final leftValue = i < leftParts.length ? leftParts[i] : 0;
      final rightValue = i < rightParts.length ? rightParts[i] : 0;
      if (leftValue != rightValue) {
        return leftValue.compareTo(rightValue);
      }
    }

    return 0;
  }

  int _extractBuildNumber(String assetName) {
    final match = RegExp(r'\((\d+)\)\.apk$', caseSensitive: false).firstMatch(assetName);
    if (match == null) {
      return 0;
    }
    return int.tryParse(match.group(1) ?? '') ?? 0;
  }

  String _buildVersionLabel(String version, int buildNumber) {
    return buildNumber > 0 ? '$version+$buildNumber' : version;
  }
}
