import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

/// Everything the app knows about the server lives in this file.
/// The screens call these methods and never build a URL themselves.

class ApiError implements Exception {
  ApiError(this.message);
  final String message;
  @override
  String toString() => message;
}

class Topic {
  Topic.fromJson(Map<String, dynamic> j)
      : id = j['id'],
        subjectId = j['subject_id'],
        title = j['title'],
        question = j['question'],
        keyPoints = j['key_points'],
        attempts = j['attempts'],
        percent = j['percent'],
        status = j['status'],
        lastMissed = List<String>.from(j['last_missed'] ?? const []),
        recentScores = List<String>.from(j['recent_scores'] ?? const []);

  final int id, subjectId, keyPoints, attempts;
  final String title, question, status;
  final int? percent;
  final List<String> lastMissed;
  final List<String> recentScores;

  String get note {
    if (attempts == 0) return 'Not practiced yet';
    if (lastMissed.isEmpty) return 'Explained all key points';
    return 'Missed: ${lastMissed.join(', ')}';
  }

  /// Where the percent comes from, like "Last answers: 2/3 · 0/3 · 1/3".
  /// Without it a good answer that lowers nothing, or a bad one that lowers
  /// the percent only a little, looks like a mistake.
  String get scoresLine => recentScores.length < 2
      ? ''
      : 'Average of the last ${recentScores.length} answers: ${recentScores.join(' · ')}';
}

class Subject {
  Subject.fromJson(Map<String, dynamic> j)
      : id = j['id'],
        name = j['name'],
        examDate = j['exam_date'] == null ? null : DateTime.parse(j['exam_date']),
        daysLeft = j['days_left'],
        topics = j['topics'],
        weak = j['weak'],
        fresh = j['new'],
        percent = j['percent'],
        status = j['status'],
        topicList = [for (final t in j['topic_list'] ?? const []) Topic.fromJson(t)];

  final int id, topics, weak, fresh, percent;
  final String name, status;
  final DateTime? examDate;
  final int? daysLeft;
  final List<Topic> topicList;

  bool get examAhead => daysLeft != null && daysLeft! >= 0;

  String get examText => switch (daysLeft) {
        0 => 'exam today',
        1 => 'exam tomorrow',
        _ => 'exam in $daysLeft days',
      };

  String get subtitle {
    final count = '$topics ${topics == 1 ? 'topic' : 'topics'}';
    if (topics == 0) return 'No material yet';
    if (examAhead) return '$count · $examText';
    if (weak > 0) return '$count · $weak weak';
    if (status == 'strong') return '$count · ready';
    return fresh == topics ? '$count · not started' : '$count · in progress';
  }
}

/// One key point in the check: named by the student, or missed.
class PointRow {
  PointRow.fromJson(Map<String, dynamic> j)
      : point = j['point'],
        evidence = j['evidence'] ?? '',
        slide = j['slide'],
        snippet = j['snippet'] ?? '',
        file = j['file'] ?? '';

  final String point, evidence, snippet, file;
  final int? slide;
}

class CheckResult {
  CheckResult.fromJson(Map<String, dynamic> j)
      : transcript = j['transcript'],
        named = [for (final r in j['named']) PointRow.fromJson(r)],
        missed = [for (final r in j['missed']) PointRow.fromJson(r)],
        topic = Topic.fromJson(j['topic']);

  final String transcript;
  final List<PointRow> named, missed;
  final Topic topic;

  int get total => named.length + missed.length;
}

class Api {
  Api(this.baseUrl);
  String baseUrl;

  Uri _uri(String path) => Uri.parse('$baseUrl$path');

  /// A quick request. If the server is not there, give up after 10 seconds
  /// so the app can say "No connection". Uploads and answers take longer
  /// and do not use this.
  Future<http.Response> _get(String path) =>
      http.get(_uri(path)).timeout(const Duration(seconds: 10));

  /// Runs a request and turns every kind of failure into one readable message.
  Future<dynamic> _send(Future<http.Response> Function() request) async {
    final http.Response response;
    try {
      response = await request();
    } catch (_) {
      throw ApiError('Cannot reach the server at $baseUrl');
    }
    final body = response.bodyBytes.isEmpty ? null : jsonDecode(utf8.decode(response.bodyBytes));
    if (response.statusCode >= 400) {
      final detail = body is Map ? body['detail'] : null;
      throw ApiError(detail is String ? detail : 'Server error ${response.statusCode}');
    }
    return body;
  }

  Future<dynamic> _json(String method, String path, Map<String, dynamic> body) => _send(() async {
        final request = http.Request(method, _uri(path))
          ..headers['content-type'] = 'application/json'
          ..body = jsonEncode(body);
        return http.Response.fromStream(await request.send());
      });

  Future<dynamic> _upload(String path, String field, Uint8List? bytes, String filename,
          [Map<String, String> fields = const {}]) =>
      _send(() async {
        final request = http.MultipartRequest('POST', _uri(path))..fields.addAll(fields);
        if (bytes != null) {
          request.files.add(http.MultipartFile.fromBytes(field, bytes, filename: filename));
        }
        return http.Response.fromStream(await request.send());
      });

  Future<Map<String, dynamic>> health() async => await _send(() => _get('/health'));

  Future<List<Subject>> subjects() async {
    final List list = await _send(() => _get('/subjects'));
    return [for (final s in list) Subject.fromJson(s)];
  }

  Future<Subject> subject(int id) async =>
      Subject.fromJson(await _send(() => _get('/subjects/$id')));

  Map<String, dynamic> _subjectBody(String name, DateTime? examDate) =>
      {'name': name, 'exam_date': examDate?.toIso8601String().substring(0, 10)};

  Future<Subject> createSubject(String name, DateTime? examDate) async =>
      Subject.fromJson(await _json('POST', '/subjects', _subjectBody(name, examDate)));

  Future<Subject> updateSubject(int id, String name, DateTime? examDate) async =>
      Subject.fromJson(await _json('PUT', '/subjects/$id', _subjectBody(name, examDate)));

  Future<void> deleteSubject(int id) => _send(() => http.delete(_uri('/subjects/$id')));

  /// Sends a lecture. Returns how many topics the server found in it.
  Future<int> uploadMaterial(int subjectId, String filename, Uint8List bytes) async {
    final body = await _upload('/subjects/$subjectId/materials', 'file', bytes, filename);
    return body['topics_added'];
  }

  /// The weakest topic of a subject. [skip] is the topic just answered.
  Future<Topic> nextTopic(int subjectId, {int? skip}) async => Topic.fromJson(await _send(
      () => _get('/subjects/$subjectId/next${skip == null ? '' : '?skip=$skip'}')));

  /// Sends the recording (or typed text) and returns the check.
  Future<CheckResult> answer(int topicId,
      {Uint8List? audio, String audioName = 'answer.m4a', String text = ''}) async {
    final body = await _upload('/topics/$topicId/answer', 'audio', audio, audioName,
        {'text': text});
    return CheckResult.fromJson(body);
  }
}
