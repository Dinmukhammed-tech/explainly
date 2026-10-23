import 'package:flutter/material.dart';

import '../api.dart';
import '../app_state.dart';
import '../dialogs.dart';
import '../theme.dart';
import '../widgets.dart';

/// Tab 3: the topic map of one subject. Green: you can explain it. Red: study it again.
class ProgressScreen extends StatelessWidget {
  const ProgressScreen(this.state, {super.key});
  final AppState state;

  @override
  Widget build(BuildContext context) {
    final subject = state.current;
    if (subject == null) {
      return EmptyHint(
        title: 'No subject yet',
        text: 'Add a lecture and your topic map will appear here.',
        action: 'Add material',
        onAction: () => addMaterial(context, state),
      );
    }
    final banner = _banner(subject);
    return RefreshIndicator(
      color: C.accent,
      onRefresh: state.refresh,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        children: [
          Row(children: [
            TextButton(
              onPressed: () => state.goTo(0),
              style: TextButton.styleFrom(foregroundColor: C.muted, padding: EdgeInsets.zero),
              child: const Text('← Back', style: TextStyle(fontSize: 15)),
            ),
            const SizedBox(width: 8),
            Expanded(
              // A long name gets smaller instead of being cut.
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(subject.name,
                    style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
              ),
            ),
            const SizedBox(width: 8),
            Tag('${subject.topics} ${subject.topics == 1 ? 'topic' : 'topics'}'),
          ]),
          const SizedBox(height: 14),
          if (banner != null) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
              decoration: BoxDecoration(color: C.paper, borderRadius: BorderRadius.circular(18)),
              child: Text.rich(
                TextSpan(children: [
                  if (banner.$1.isNotEmpty)
                    TextSpan(text: '${banner.$1}  ', style: mono(size: 15, color: C.bg, weight: FontWeight.w800)),
                  TextSpan(text: banner.$2),
                ]),
                style: const TextStyle(color: C.bg, fontSize: 15),
              ),
            ),
            const SizedBox(height: 22),
          ],
          Text('CAN YOU EXPLAIN IT?', style: label()),
          const SizedBox(height: 14),
          if (subject.topicList.isEmpty)
            const Text('This subject has no topics yet.', style: TextStyle(color: C.muted)),
          for (final topic in subject.topicList) ...[
            _TopicCard(topic, onTap: () => state.practice(topic)),
            const SizedBox(height: 12),
          ],
          const SizedBox(height: 4),
          DashedButton(
              text: '+  Add material', onTap: () => addMaterial(context, state, into: subject)),
        ],
      ),
    );
  }

  /// The light banner: (bold part, rest of the sentence).
  (String, String)? _banner(Subject subject) {
    if (subject.topics == 0) return null;
    final notReady = subject.topicList.where((t) => t.status != 'strong').length;
    final left = subject.weak > 0
        ? '${subject.weak} weak ${subject.weak == 1 ? 'topic' : 'topics'} left'
        : notReady > 0
            ? '$notReady ${notReady == 1 ? 'topic' : 'topics'} to practice'
            : 'all topics ready';
    if (!subject.examAhead) return ('', left[0].toUpperCase() + left.substring(1));
    return switch (subject.daysLeft!) {
      0 => ('Today', 'is your exam · $left'),
      1 => ('1 day', 'to your exam · $left'),
      final days => ('$days days', 'to your exam · $left'),
    };
  }
}

class _TopicCard extends StatelessWidget {
  const _TopicCard(this.topic, {required this.onTap});
  final Topic topic;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = statusColor(topic.status);
    return AppCard(
      onTap: onTap,
      padding: EdgeInsets.zero,
      child: IntrinsicHeight(
        child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Container(width: 4, color: color),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(topic.title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                Text(topic.note,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: C.muted, fontSize: 13.5)),
                if (topic.scoresLine.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(topic.scoresLine, style: mono(size: 11.5)),
                ],
                const SizedBox(height: 10),
                Bar(percent: topic.percent ?? 0, color: color),
              ]),
            ),
          ),
          SizedBox(
            width: 64,
            child: Center(
              child: Text(topic.percent == null ? '—' : '${topic.percent}%',
                  style: mono(size: 15, color: color, weight: FontWeight.w700)),
            ),
          ),
        ]),
      ),
    );
  }
}
