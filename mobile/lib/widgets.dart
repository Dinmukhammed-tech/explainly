import 'dart:math';

import 'package:flutter/material.dart';

import 'theme.dart';

/// A dark rounded card, the basic block of every screen.
class AppCard extends StatelessWidget {
  const AppCard({super.key, required this.child, this.onTap, this.onLongPress, this.padding});
  final Widget child;
  final VoidCallback? onTap, onLongPress;
  final EdgeInsets? padding;

  @override
  Widget build(BuildContext context) => Material(
        color: C.card,
        borderRadius: BorderRadius.circular(18),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          onLongPress: onLongPress,
          child: Padding(padding: padding ?? const EdgeInsets.all(16), child: child),
        ),
      );
}

/// The circle with a number on the Subjects screen.
class Ring extends StatelessWidget {
  const Ring({super.key, required this.percent, required this.color, this.size = 56});
  final int percent;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: size,
        height: size,
        child: CustomPaint(
          painter: _RingPainter(percent / 100, color),
          child: Center(child: Text('$percent', style: mono(size: 14, color: C.text, weight: FontWeight.w700))),
        ),
      );
}

class _RingPainter extends CustomPainter {
  _RingPainter(this.share, this.color);
  final double share;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = (Offset.zero & size).deflate(3);
    final pen = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(rect, 0, 2 * pi, false, pen..color = C.line);
    if (share > 0) canvas.drawArc(rect, -pi / 2, 2 * pi * share, false, pen..color = color);
  }

  @override
  bool shouldRepaint(_RingPainter old) => old.share != share || old.color != color;
}

/// The thin bar under a topic on the map.
class Bar extends StatelessWidget {
  const Bar({super.key, required this.percent, required this.color});
  final int percent;
  final Color color;

  @override
  Widget build(BuildContext context) => ClipRRect(
        borderRadius: BorderRadius.circular(3),
        child: LinearProgressIndicator(
            value: percent / 100, minHeight: 4, color: color, backgroundColor: C.line),
      );
}

/// The orange "+ Add material" button with a dashed border.
class DashedButton extends StatelessWidget {
  const DashedButton({super.key, required this.text, required this.onTap});
  final String text;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => CustomPaint(
        foregroundPainter: _DashPainter(),
        child: Material(
          color: C.accent.withValues(alpha: 0.13),
          borderRadius: BorderRadius.circular(18),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: SizedBox(
              height: 64,
              child: Center(
                child: Text(text,
                    style: const TextStyle(color: C.accent, fontSize: 16, fontWeight: FontWeight.w700)),
              ),
            ),
          ),
        ),
      );
}

class _DashPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final outline = Path()
      ..addRRect(RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(18)));
    final pen = Paint()
      ..color = C.accent
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    for (final metric in outline.computeMetrics()) {
      for (double at = 0; at < metric.length; at += 8) {
        canvas.drawPath(metric.extractPath(at, at + 4), pen);
      }
    }
  }

  @override
  bool shouldRepaint(_DashPainter old) => false;
}

/// A small outlined tag, like "9 topics".
class Tag extends StatelessWidget {
  const Tag(this.text, {super.key, this.onTap});
  final String text;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          decoration:
              BoxDecoration(border: Border.all(color: C.line), borderRadius: BorderRadius.circular(10)),
          child: Text(text, style: mono(size: 12, color: C.text.withValues(alpha: 0.8), weight: FontWeight.w700)),
        ),
      );
}

/// Shown in the middle of a screen that has nothing to show yet.
class EmptyHint extends StatelessWidget {
  const EmptyHint({super.key, required this.title, required this.text, this.action, this.onAction});
  final String title, text;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(title,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Text(text, textAlign: TextAlign.center, style: const TextStyle(color: C.muted, height: 1.4)),
            if (action != null) ...[
              const SizedBox(height: 20),
              OutlinedButton(onPressed: onAction, child: Text(action!)),
            ],
          ]),
        ),
      );
}

void showMessage(BuildContext context, String text) =>
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
