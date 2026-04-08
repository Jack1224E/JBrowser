class DownloadStatus {
  final String gid;
  final String status;
  final int totalLength;
  final int completedLength;
  final int downloadSpeed;
  final int uploadSpeed;
  final String? dir;
  final List<String> files;
  final String? requestId;

  DownloadStatus({
    required this.gid,
    required this.status,
    required this.totalLength,
    required this.completedLength,
    required this.downloadSpeed,
    required this.uploadSpeed,
    this.dir,
    required this.files,
    this.requestId,
  });

  factory DownloadStatus.fromJson(Map<String, dynamic> json) {
    return DownloadStatus(
      gid: json['gid'] as String,
      status: json['status'] as String,
      totalLength: int.parse(json['totalLength'] ?? '0'),
      completedLength: int.parse(json['completedLength'] ?? '0'),
      downloadSpeed: int.parse(json['downloadSpeed'] ?? '0'),
      uploadSpeed: int.parse(json['uploadSpeed'] ?? '0'),
      dir: (json['dir'] as String?) ?? (json['dir'] != null ? json['dir'].toString() : null),
      files: (json['files'] as List<dynamic>?)
              ?.map((f) => f['path'] as String)
              .toList() ??
          [],
      requestId: json['requestId'] as String?,
    );
  }

  DownloadStatus copyWith({
    String? gid,
    String? status,
    int? totalLength,
    int? completedLength,
    int? downloadSpeed,
    int? uploadSpeed,
    String? dir,
    List<String>? files,
    String? requestId,
  }) {
    return DownloadStatus(
      gid: gid ?? this.gid,
      status: status ?? this.status,
      totalLength: totalLength ?? this.totalLength,
      completedLength: completedLength ?? this.completedLength,
      downloadSpeed: downloadSpeed ?? this.downloadSpeed,
      uploadSpeed: uploadSpeed ?? this.uploadSpeed,
      dir: dir ?? this.dir,
      files: files ?? this.files,
      requestId: requestId ?? this.requestId,
    );
  }

  double get progress => totalLength > 0 ? completedLength / totalLength : 0.0;
  
  String get fileName {
    if (files.isEmpty) return "Unknown";
    final path = files.first;
    return path.contains('/') ? path.split('/').last : (path.contains('\\') ? path.split('\\').last : path);
  }

  bool get isIntermediate => 
      status == 'pausing' || 
      status == 'resuming' || 
      status == 'deleting';
}
