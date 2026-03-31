class GlobalStats {
  final int downloadSpeed;
  final int uploadSpeed;
  final int numActive;
  final int numWaiting;
  final int numStopped;

  GlobalStats({
    required this.downloadSpeed,
    required this.uploadSpeed,
    required this.numActive,
    required this.numWaiting,
    required this.numStopped,
  });

  factory GlobalStats.fromJson(Map<String, dynamic> json) {
    return GlobalStats(
      downloadSpeed: int.parse(json['downloadSpeed'] ?? '0'),
      uploadSpeed: int.parse(json['uploadSpeed'] ?? '0'),
      numActive: int.parse(json['numActive'] ?? '0'),
      numWaiting: int.parse(json['numWaiting'] ?? '0'),
      numStopped: int.parse(json['numStopped'] ?? '0'),
    );
  }
}
