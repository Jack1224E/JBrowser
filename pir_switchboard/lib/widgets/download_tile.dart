import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/download_status.dart';
import '../providers/download_list_provider.dart';

class DownloadTile extends ConsumerWidget {
  final DownloadStatus download;

  const DownloadTile({super.key, required this.download});

  String _formatBytes(int bytes) {
    if (bytes <= 0) return "0 B";
    if (bytes < 1024) return "$bytes B";
    if (bytes < 1024 * 1024) return "${(bytes / 1024).toStringAsFixed(1)} KB";
    if (bytes < 1024 * 1024 * 1024) return "${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB";
    return "${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB";
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(downloadListProvider.notifier);
    final isIntermediate = download.isIntermediate;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.2),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      _getStatusIcon(download.status),
                      color: _getStatusColor(download.status),
                      size: 20,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        download.fileName,
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 15,
                          color: Colors.white,
                          letterSpacing: 0.5,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    _StatusBadge(status: download.status),
                  ],
                ),
                const SizedBox(height: 16),
                Stack(
                  children: [
                    LinearProgressIndicator(
                      value: download.progress,
                      backgroundColor: Colors.white10,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        isIntermediate ? Colors.white30 : _getStatusColor(download.status),
                      ),
                      minHeight: 6,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          "${_formatBytes(download.completedLength)} / ${_formatBytes(download.totalLength)}",
                          style: const TextStyle(fontSize: 11, color: Colors.white38),
                        ),
                        if (download.status == 'active' || download.status == 'resuming')
                          Text(
                            "${_formatBytes(download.downloadSpeed)}/s",
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: Colors.greenAccent,
                            ),
                          ),
                      ],
                    ),
                    Row(
                      children: [
                        if (download.status == 'active' || download.status == 'pausing')
                          _ControlButton(
                            icon: Icons.pause_rounded,
                            onPressed: isIntermediate ? null : () => notifier.pauseTask(download.gid),
                            color: Colors.orangeAccent,
                          ),
                        if (download.status == 'paused' || download.status == 'active' || download.status == 'resuming')
                           if (download.status == 'paused' || download.status == 'resuming')
                            _ControlButton(
                              icon: Icons.play_arrow_rounded,
                              onPressed: isIntermediate ? null : () => notifier.resumeTask(download.gid),
                              color: Colors.greenAccent,
                            ),
                        _ControlButton(
                          icon: Icons.delete_outline_rounded,
                          onPressed: isIntermediate ? null : () => notifier.removeTask(download.gid),
                          color: Colors.redAccent,
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  IconData _getStatusIcon(String status) {
    switch (status) {
      case 'active': return Icons.downloading_rounded;
      case 'paused': return Icons.pause_circle_filled_rounded;
      case 'complete': return Icons.check_circle_rounded;
      case 'error': return Icons.error_rounded;
      case 'pausing': return Icons.hourglass_bottom_rounded;
      case 'resuming': return Icons.hourglass_top_rounded;
      case 'deleting': return Icons.delete_sweep_rounded;
      default: return Icons.help_outline_rounded;
    }
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'active': return Colors.blueAccent;
      case 'paused': return Colors.orangeAccent;
      case 'complete': return Colors.greenAccent;
      case 'error': return Colors.redAccent;
      case 'pausing':
      case 'resuming':
      case 'deleting':
        return Colors.white30;
      default: return Colors.grey;
    }
  }
}

class _ControlButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onPressed;
  final Color color;

  const _ControlButton({required this.icon, this.onPressed, required this.color});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 8),
      child: IconButton(
        icon: Icon(icon),
        onPressed: onPressed,
        color: color.withValues(alpha: onPressed == null ? 0.2 : 0.8),
        iconSize: 22,
        visualDensity: VisualDensity.compact,
        style: IconButton.styleFrom(
          backgroundColor: color.withValues(alpha: 0.1),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final String status;
  const _StatusBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    Color color;
    switch (status) {
      case 'active': color = Colors.green; break;
      case 'paused': color = Colors.orange; break;
      case 'error': color = Colors.red; break;
      case 'complete': color = Colors.blue; break;
      default: color = Colors.grey;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(8)),
      child: Text(
        status.toUpperCase(),
        style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.bold),
      ),
    );
  }
}
