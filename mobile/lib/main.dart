import 'package:flutter/material.dart';

import 'app_state.dart';
import 'dialogs.dart';
import 'screens/practice_screen.dart';
import 'screens/progress_screen.dart';
import 'screens/subjects_screen.dart';
import 'theme.dart';
import 'widgets.dart';

void main() => runApp(const ExplainlyApp());

class ExplainlyApp extends StatefulWidget {
  const ExplainlyApp({super.key});

  @override
  State<ExplainlyApp> createState() => _ExplainlyAppState();
}

class _ExplainlyAppState extends State<ExplainlyApp> {
  final state = AppState();

  @override
  void initState() {
    super.initState();
    state.start();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Explainly',
        debugShowCheckedModeBanner: false,
        theme: appTheme(),
        // Redraw the whole shell every time the shared state changes.
        home: ListenableBuilder(listenable: state, builder: (_, _) => Shell(state)),
      );
}

/// The frame of the app: one of three screens and the bar at the bottom.
class Shell extends StatelessWidget {
  const Shell(this.state, {super.key});
  final AppState state;

  static const _tabs = ['Subjects', 'Practice', 'Progress'];
  static const _icons = [Icons.menu_book_rounded, Icons.mic_rounded, Icons.insights_rounded];

  @override
  Widget build(BuildContext context) => Scaffold(
        body: SafeArea(
          // A phone-wide column, so the app also looks right in a browser.
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: _body(context),
            ),
          ),
        ),
        bottomNavigationBar: _BottomBar(
          labels: _tabs,
          icons: _icons,
          current: state.tab,
          onTap: state.goTo,
        ),
      );

  Widget _body(BuildContext context) {
    if (state.loading) return const Center(child: CircularProgressIndicator(color: C.accent));
    if (state.error != null && state.subjects.isEmpty) {
      return EmptyHint(
        title: 'No connection',
        text: '${state.error}\n\nStart the server, or change its address.',
        action: 'Server address',
        onAction: () => editServerAddress(context, state),
      );
    }
    return IndexedStack(index: state.tab, children: [
      SubjectsScreen(state),
      PracticeScreen(state),
      ProgressScreen(state),
    ]);
  }
}

class _BottomBar extends StatelessWidget {
  const _BottomBar({required this.labels, required this.icons, required this.current, required this.onTap});
  final List<String> labels;
  final List<IconData> icons;
  final int current;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) => Container(
        decoration: const BoxDecoration(
            color: C.card, border: Border(top: BorderSide(color: C.line))),
        child: SafeArea(
          top: false,
          child: Row(children: [
            for (var i = 0; i < labels.length; i++)
              Expanded(
                child: InkWell(
                  onTap: () => onTap(i),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Icon(icons[i], size: 24, color: i == current ? C.accent : C.muted),
                      const SizedBox(height: 4),
                      Text(labels[i],
                          style: TextStyle(
                            fontSize: 13,
                            color: i == current ? C.accent : C.muted,
                            fontWeight: i == current ? FontWeight.w700 : FontWeight.w500,
                          )),
                    ]),
                  ),
                ),
              ),
          ]),
        ),
      );
}
