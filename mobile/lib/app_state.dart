import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api.dart';

/// The server address can be set when the app is built:
///   flutter run --dart-define=API_URL=http://192.168.1.5:8000
const _apiUrlFromBuild = String.fromEnvironment('API_URL');

String _defaultApiUrl() {
  if (_apiUrlFromBuild.isNotEmpty) return _apiUrlFromBuild;
  // In a browser the server is on the same computer as the page.
  if (kIsWeb) return 'http://${Uri.base.host.isEmpty ? 'localhost' : Uri.base.host}:8000';
  // 10.0.2.2 is how the Android emulator sees the computer it runs on.
  return 'http://10.0.2.2:8000';
}

/// What all three tabs share: the subjects, which one is open, and the settings.
/// A screen changes something here, and every screen that shows it is redrawn.
class AppState extends ChangeNotifier {
  final api = Api(_defaultApiUrl());

  List<Subject> subjects = [];
  Subject? current; // the subject open in Practice and Progress, with its topics
  Topic? practiceTopic; // the topic chosen on the map; null = let the server pick
  int tab = 0;
  bool loading = true;
  String? error;

  Future<void> start() async {
    final prefs = await SharedPreferences.getInstance();
    api.baseUrl = prefs.getString('api_url') ?? api.baseUrl;
    await refresh();
  }

  Future<void> refresh() async {
    try {
      subjects = await api.subjects();
      final id = current?.id ?? (subjects.isEmpty ? null : subjects.first.id);
      final stillThere = subjects.any((s) => s.id == id);
      current = stillThere ? await api.subject(id!) : null;
      if (current == null && subjects.isNotEmpty) current = await api.subject(subjects.first.id);
      error = null;
    } on ApiError catch (e) {
      error = e.message;
    }
    loading = false;
    notifyListeners();
  }

  Future<void> open(int subjectId, {int? goToTab}) async {
    if (current?.id != subjectId) practiceTopic = null;
    try {
      current = await api.subject(subjectId);
      error = null;
    } on ApiError catch (e) {
      error = e.message;
    }
    if (goToTab != null) tab = goToTab;
    notifyListeners();
  }

  void goTo(int index) {
    tab = index;
    notifyListeners();
  }

  void practice(Topic topic) {
    practiceTopic = topic;
    tab = 1;
    notifyListeners();
  }

  Future<void> setApiUrl(String url) async {
    api.baseUrl = url.trim().replaceAll(RegExp(r'/+$'), '');
    (await SharedPreferences.getInstance()).setString('api_url', api.baseUrl);
    loading = true;
    notifyListeners();
    await refresh();
  }
}
