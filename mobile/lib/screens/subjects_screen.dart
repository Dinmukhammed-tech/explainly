import 'package:flutter/material.dart';

import '../app_state.dart';
import '../dialogs.dart';
import '../theme.dart';
import '../widgets.dart';

/// Tab 1: the list of subjects, each with its readiness ring.
class SubjectsScreen extends StatelessWidget {
  const SubjectsScreen(this.state, {super.key});
  final AppState state;

  @override
  Widget build(BuildContext context) => RefreshIndicator(
        color: C.accent,
        onRefresh: state.refresh,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          children: [
            Row(children: [
              const Text('Explainly', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
              const Spacer(),
              IconButton(
                tooltip: 'Server address',
                onPressed: () => editServerAddress(context, state),
                icon: const Icon(Icons.settings_outlined, color: C.muted, size: 20),
              ),
            ]),
            const SizedBox(height: 20),
            Text('YOUR SUBJECTS', style: label()),
            const SizedBox(height: 14),
            if (state.subjects.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 28),
                child: Text(
                  'Upload a lecture. Explainly will ask you about it, '
                  'and you answer out loud.',
                  style: TextStyle(color: C.muted, fontSize: 16, height: 1.4),
                ),
              ),
            for (final subject in state.subjects) ...[
              AppCard(
                onTap: () => state.open(subject.id, goToTab: 2),
                onLongPress: () => editSubject(context, state, subject),
                child: Row(children: [
                  Ring(percent: subject.percent, color: statusColor(subject.status)),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(subject.name,
                          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 4),
                      Text(subject.subtitle, style: const TextStyle(color: C.muted)),
                    ]),
                  ),
                  IconButton(
                    tooltip: 'Edit subject',
                    onPressed: () => editSubject(context, state, subject),
                    icon: const Icon(Icons.more_vert, color: C.muted, size: 20),
                  ),
                ]),
              ),
              const SizedBox(height: 12),
            ],
            DashedButton(text: '+  Add material', onTap: () => addMaterial(context, state)),
          ],
        ),
      );
}
