class ReleaseInfo {
  const ReleaseInfo({
    required this.tagName,
    required this.name,
    required this.body,
    required this.assets,
  });

  final String tagName;
  final String name;
  final String body;
  final Map<String, String> assets;

  String get version =>
      tagName.startsWith('v') ? tagName.substring(1) : tagName;

  int get build {
    final match = RegExp(r'(?im)\\bBuild\\s*:\\s*(\\d+)').firstMatch(body);
    return int.tryParse(match?.group(1) ?? '') ?? 0;
  }
}

class UpdateInfo {
  const UpdateInfo({
    required this.currentVersion,
    required this.currentBuild,
    required this.latestVersion,
    required this.latestBuild,
    required this.releaseName,
    required this.releaseUrl,
    required this.mandatory,
    required this.notes,
    required this.apk,
  });

  final String currentVersion;
  final int currentBuild;
  final String latestVersion;
  final int latestBuild;
  final String releaseName;
  final String? releaseUrl;
  final bool mandatory;
  final List<String> notes;
  final UpdateAsset? apk;
}

class UpdateAsset {
  const UpdateAsset({
    required this.name,
    required this.downloadUrl,
    required this.size,
  });

  final String name;
  final String downloadUrl;
  final int size;
}

class UpdateCheckException implements Exception {
  const UpdateCheckException(this.message);

  final String message;

  @override
  String toString() => message;
}
