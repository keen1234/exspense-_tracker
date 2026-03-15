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

class UpdateInstallResult {
  final bool installerOpened;
  final String? message;

  const UpdateInstallResult({
    required this.installerOpened,
    this.message,
  });
}
