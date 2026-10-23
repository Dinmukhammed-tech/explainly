import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../api.dart';
import '../app_state.dart';
import '../dialogs.dart';
import '../recorder.dart';
import '../theme.dart';
import '../widgets.dart';

enum _Phase { loading, question, recording, checking, result }

/// Tab 2: the oral exam. A question, your voice, an honest check.
class PracticeScreen extends StatefulWidget {
  const PracticeScreen(this.state, {super.key});
  final AppState state;

  @override
  State<PracticeScreen> createState() => _PracticeScreenState();
}

class _PracticeScreenState extends State<PracticeScreen> {
  static const _maxSeconds = 180;

  final recorder = VoiceRecorder();
  final typed = TextEditingController();

  _Phase phase = _Phase.loading;
  Topic? topic;
  CheckResult? result;
  String? error;
  bool typing = false;
  int seconds = 0;
  Timer? timer;
  String _shown = ''; // which subject and topic this screen was loaded for

  AppState get state => widget.state;

  String get _wanted => '${state.current?.id}/${state.practiceTopic?.id}';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(PracticeScreen old) {
    super.didUpdateWidget(old);
    // Another subject was opened, or a topic was tapped on the map.
    final busy = phase == _Phase.recording || phase == _Phase.checking;
    if (_wanted != _shown && !busy) _load();
  }

  @override
  void dispose() {
    timer?.cancel();
    recorder.dispose();
    super.dispose();
  }

  Future<void> _load({int? skip}) async {
    _shown = _wanted;
    final subject = state.current;
    if (subject == null) return setState(() => topic = null);
    setState(() {
      phase = _Phase.loading;
      error = null;
      result = null;
    });
    try {
      final next = state.practiceTopic ?? await state.api.nextTopic(subject.id, skip: skip);
      if (!mounted) return;
      setState(() {
        topic = next;
        phase = _Phase.question;
      });
    } on ApiError catch (e) {
      if (!mounted) return;
      setState(() {
        topic = null;
        error = e.message;
        phase = _Phase.question;
      });
    }
  }

  Future<void> _startRecording() async {
    final bool allowed;
    try {
      allowed = await recorder.start();
    } catch (_) {
      return setState(() {
        error = 'The microphone is not available. You can type your answer.';
        typing = true;
      });
    }
    if (!allowed) {
      return setState(() {
        error = 'Allow the microphone to answer out loud, or type your answer.';
        typing = true;
      });
    }
    setState(() {
      phase = _Phase.recording;
      error = null;
      seconds = 0;
    });
    timer = Timer.periodic(const Duration(seconds: 1), (_) {
      setState(() => seconds++);
      if (seconds >= _maxSeconds) _stopRecording();
    });
  }

  Future<void> _stopRecording() async {
    timer?.cancel();
    final audio = await recorder.stop();
    if (audio == null) {
      return setState(() {
        phase = _Phase.question;
        error = 'Nothing was recorded. Try again.';
      });
    }
    await _check(audio: audio.$1, audioName: audio.$2);
  }

  Future<void> _check({Uint8List? audio, String audioName = '', String text = ''}) async {
    setState(() {
      phase = _Phase.checking;
      error = null;
    });
    try {
      final checked = await state.api.answer(topic!.id,
          audio: audio, audioName: audioName, text: text);
      typed.clear();
      if (!mounted) return;
      setState(() {
        result = checked;
        topic = checked.topic;
        phase = _Phase.result;
      });
      state.refresh(); // the rings and the topic map now show this answer
    } on ApiError catch (e) {
      if (!mounted) return;
      setState(() {
        phase = _Phase.question;
        error = e.message;
      });
    }
  }

  void _tryAgain() => setState(() {
        phase = _Phase.question;
        result = null;
      });

  void _nextTopic() {
    final done = topic?.id;
    state.practiceTopic = null;
    _load(skip: done);
  }

  @override
  Widget build(BuildContext context) {
    if (state.current == null) {
      return EmptyHint(
        title: 'Nothing to practice yet',
        text: 'Add a lecture, and the first question will be here.',
        action: 'Add material',
        onAction: () => addMaterial(context, state),
      );
    }
    if (phase == _Phase.loading) {
      return const Center(child: CircularProgressIndicator(color: C.accent));
    }
    if (topic == null) {
      return EmptyHint(
        title: 'No questions yet',
        text: error ?? 'Add a lecture to ${state.current!.name}.',
        action: 'Add material',
        onAction: () => addMaterial(context, state, into: state.current),
      );
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      children: [
        Row(children: [
          Expanded(child: Text(state.current!.name.toUpperCase(), style: label())),
          if (topic!.percent != null)
            Text('${topic!.percent}%',
                style: mono(color: statusColor(topic!.status), weight: FontWeight.w700)),
        ]),
        const SizedBox(height: 10),
        Text(topic!.title, style: const TextStyle(color: C.muted, fontSize: 16)),
        const SizedBox(height: 8),
        Text(topic!.question,
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800, height: 1.25)),
        const SizedBox(height: 28),
        if (phase == _Phase.result) ..._resultView() else ..._answerView(),
      ],
    );
  }

  // ---------- before the check ----------

  List<Widget> _answerView() {
    final recording = phase == _Phase.recording;
    final checking = phase == _Phase.checking;
    return [
      if (error != null) ...[
        Text(error!, style: const TextStyle(color: C.red, height: 1.4)),
        const SizedBox(height: 16),
      ],
      if (checking)
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 40),
          child: Column(children: [
            CircularProgressIndicator(color: C.accent),
            SizedBox(height: 18),
            Text('Listening to your answer and checking it against the lecture…',
                textAlign: TextAlign.center, style: TextStyle(color: C.muted, height: 1.4)),
          ]),
        )
      else if (typing && !recording) ...[
        TextField(
          controller: typed,
          minLines: 4,
          maxLines: 8,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(hintText: 'Type your answer'),
        ),
        const SizedBox(height: 12),
        FilledButton(
          onPressed: () {
            if (typed.text.trim().isNotEmpty) _check(text: typed.text.trim());
          },
          child: const Text('Check my answer'),
        ),
        TextButton(
          onPressed: () => setState(() {
            typing = false;
            error = null;
          }),
          child: const Text('Answer out loud instead', style: TextStyle(color: C.muted)),
        ),
      ] else ...[
        const SizedBox(height: 12),
        Center(
          child: Semantics(
            button: true,
            label: recording ? 'Stop recording' : 'Start recording',
            child: GestureDetector(
              onTap: recording ? _stopRecording : _startRecording,
              child: Container(
                width: 112,
                height: 112,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: recording ? C.red : C.accent,
                  boxShadow: [
                    BoxShadow(
                        color: (recording ? C.red : C.accent).withValues(alpha: 0.35),
                        blurRadius: 32,
                        spreadRadius: recording ? 10 : 2),
                  ],
                ),
                child: Icon(recording ? Icons.stop_rounded : Icons.mic_rounded,
                    color: Colors.white, size: 48),
              ),
            ),
          ),
        ),
        const SizedBox(height: 20),
        Center(
          child: recording
              ? Text('${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}',
                  style: mono(size: 22, color: C.text, weight: FontWeight.w700))
              : const Text('Tap and answer out loud',
                  style: TextStyle(color: C.muted, fontSize: 16)),
        ),
        const SizedBox(height: 6),
        Center(
          child: recording
              ? const Text('Tap again when you finish', style: TextStyle(color: C.muted))
              : TextButton(
                  onPressed: () => setState(() => typing = true),
                  child: const Text('Type instead', style: TextStyle(color: C.muted)),
                ),
        ),
      ],
    ];
  }

  // ---------- after the check ----------

  List<Widget> _resultView() {
    final r = result!;
    final share = r.total == 0 ? 0.0 : r.named.length / r.total;
    final color = statusColor(share < 0.5 ? 'weak' : (share < 0.8 ? 'ok' : 'strong'));
    return [
      AppCard(
        child: Row(children: [
          Text('${r.named.length}/${r.total}', style: mono(size: 34, color: color, weight: FontWeight.w800)),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              'You named ${r.named.length} of ${r.total} key points',
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, height: 1.3),
            ),
          ),
        ]),
      ),
      const SizedBox(height: 22),
      if (r.missed.isNotEmpty) ...[
        Text('YOU MISSED', style: label()),
        const SizedBox(height: 12),
        for (final row in r.missed) ...[_PointCard(row, missed: true), const SizedBox(height: 10)],
        const SizedBox(height: 12),
      ],
      if (r.named.isNotEmpty) ...[
        Text('YOU EXPLAINED', style: label()),
        const SizedBox(height: 12),
        for (final row in r.named) ...[_PointCard(row, missed: false), const SizedBox(height: 10)],
        const SizedBox(height: 12),
      ],
      Text('WHAT WE HEARD', style: label()),
      const SizedBox(height: 8),
      Text(r.transcript, style: const TextStyle(color: C.muted, height: 1.45)),
      const SizedBox(height: 26),
      FilledButton(onPressed: _nextTopic, child: const Text('Next topic')),
      const SizedBox(height: 10),
      OutlinedButton(onPressed: _tryAgain, child: const Text('Try this one again')),
    ];
  }
}

class _PointCard extends StatelessWidget {
  const _PointCard(this.row, {required this.missed});
  final PointRow row;
  final bool missed;

  @override
  Widget build(BuildContext context) {
    final color = missed ? C.red : C.green;
    return AppCard(
      padding: const EdgeInsets.all(14),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(missed ? Icons.close_rounded : Icons.check_rounded, color: color, size: 20),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(row.point, style: const TextStyle(fontSize: 15, height: 1.35)),
            if (!missed && row.evidence.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text('You said: “${row.evidence}”',
                  style: const TextStyle(color: C.muted, fontSize: 13.5, height: 1.35)),
            ],
            if (missed && row.slide != null) ...[
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: C.bg, borderRadius: BorderRadius.circular(12)),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Read again: slide ${row.slide}',
                      style: const TextStyle(color: C.accent, fontWeight: FontWeight.w700)),
                  if (row.file.isNotEmpty)
                    Text(row.file, style: mono(size: 11.5), overflow: TextOverflow.ellipsis),
                  if (row.snippet.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(row.snippet,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: C.muted, fontSize: 13, height: 1.35)),
                  ],
                ]),
              ),
            ],
          ]),
        ),
      ]),
    );
  }
}
