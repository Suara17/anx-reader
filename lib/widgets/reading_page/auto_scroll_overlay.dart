import 'package:anx_reader/main.dart';
import 'package:anx_reader/page/book_player/epub_player.dart';
import 'package:anx_reader/page/reading_page.dart';
import 'package:flutter/material.dart';

class AutoScrollOverlay extends StatelessWidget {
  final bool isScrolling;
  final bool isPaused;
  final int speedLevel;
  final VoidCallback onTogglePause;
  final ValueChanged<int> onSpeedChanged;
  final VoidCallback onStop;

  const AutoScrollOverlay({
    super.key,
    required this.isScrolling,
    required this.isPaused,
    required this.speedLevel,
    required this.onTogglePause,
    required this.onSpeedChanged,
    required this.onStop,
  });

  @override
  Widget build(BuildContext context) {
    if (!isScrolling) {
      return const SizedBox.shrink();
    }

    final colorScheme = Theme.of(context).colorScheme;

    return Material(
      color: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: colorScheme.surface.withAlpha(220),
          borderRadius: BorderRadius.circular(30),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withAlpha(40),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
          border: Border.all(
            color: colorScheme.outlineVariant.withAlpha(120),
            width: 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Play / Pause toggle
            IconButton(
              iconSize: 22,
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              icon: Icon(
                isPaused ? Icons.play_arrow_rounded : Icons.pause_rounded,
                color: isPaused ? colorScheme.primary : colorScheme.onSurface,
              ),
              tooltip: isPaused ? '继续自动翻页' : '暂停自动翻页',
              onPressed: onTogglePause,
            ),
            const SizedBox(width: 4),

            // Speed decrease
            IconButton(
              iconSize: 18,
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
              icon: const Icon(Icons.remove_rounded),
              tooltip: '减速',
              onPressed: speedLevel > 1
                  ? () => onSpeedChanged(speedLevel - 1)
                  : null,
            ),

            // Speed indicator badge
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: colorScheme.primaryContainer.withAlpha(150),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                '$speedLevel 档',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: colorScheme.onPrimaryContainer,
                ),
              ),
            ),

            // Speed increase
            IconButton(
              iconSize: 18,
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
              icon: const Icon(Icons.add_rounded),
              tooltip: '加速',
              onPressed: speedLevel < 10
                  ? () => onSpeedChanged(speedLevel + 1)
                  : null,
            ),

            const SizedBox(width: 4),
            Container(
              height: 16,
              width: 1,
              color: colorScheme.outlineVariant,
            ),
            const SizedBox(width: 4),

            // Close button
            IconButton(
              iconSize: 18,
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
              icon: const Icon(Icons.close_rounded),
              tooltip: '退出自动翻页',
              onPressed: onStop,
            ),
          ],
        ),
      ),
    );
  }
}
