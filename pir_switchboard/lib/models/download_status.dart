class DownloadStatus {
  final String gid;
  final String status;
  final int totalLength;
  final int completedLength;
  final int downloadSpeed;
  final int uploadSpeed;
  final String? dir;
  final List<String> files;

  DownloadStatus({
    required this.gid,
    required this.status,
    required this.totalLength,
    required this.completedLength,
    required this.downloadSpeed,
    required this.uploadSpeed,
    this.dir,
    required this.files,
  });

  factory DownloadStatus.fromJson(Map<String, dynamic> json) {
    return DownloadStatus(
      gid: json['gid'] as String,
      status: json['status'] as String,
      totalLength: int.parse(json['totalLength'] ?? '0'),
      completedLength: int.parse(json['completedLength'] ?? '0'),
      downloadSpeed: int.parse(json['downloadSpeed'] ?? '0'),
      uploadSpeed: int.parse(json['uploadSpeed'] ?? '0'),
      dir: json['dir'] as String?,
      files: (json['files'] as List<dynamic>?)
              ?.map((f) => f['path'] as String)
              .toList() ??
          [],
    );
  }

  double get progress => totalLength > 0 ? completedLength / totalLength : 0.0;
  
  String get fileName {
    if (files.isEmpty) return "Unknown";
    return files.first.split('/').last;
  }
}
