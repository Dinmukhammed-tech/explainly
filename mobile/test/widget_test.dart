import 'package:explainly/api.dart';
import 'package:flutter_test/flutter_test.dart';

Topic topic({int attempts = 1, List<String> missed = const []}) => Topic.fromJson({
      'id': 1,
      'subject_id': 1,
      'title': 'Deadlocks',
      'question': 'Explain deadlocks.',
      'key_points': 3,
      'attempts': attempts,
      'percent': attempts == 0 ? null : 33,
      'status': attempts == 0 ? 'new' : 'weak',
      'last_missed': missed,
    });

void main() {
  test('the topic note says what was missed', () {
    expect(topic(attempts: 0).note, 'Not practiced yet');
    expect(topic(missed: ['four conditions']).note, 'Missed: four conditions');
    expect(topic().note, 'Explained all key points');
  });

  test('the subject line shows the exam first', () {
    Subject subject(Map<String, dynamic> extra) => Subject.fromJson({
          'id': 1,
          'name': 'OS',
          'exam_date': null,
          'days_left': null,
          'topics': 6,
          'weak': 2,
          'new': 0,
          'percent': 40,
          'status': 'weak',
          ...extra,
        });

    expect(subject({'days_left': 3}).subtitle, '6 topics · exam in 3 days');
    expect(subject({}).subtitle, '6 topics · 2 weak');
    expect(subject({'weak': 0, 'status': 'strong'}).subtitle, '6 topics · ready');
  });
}
