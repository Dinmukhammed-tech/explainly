import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import 'api.dart';
import 'app_state.dart';
import 'theme.dart';
import 'widgets.dart';

/// A dialog to type where the server is. Needed on a real phone,
/// where the server is another device in the same Wi-Fi.
Future<void> editServerAddress(BuildContext context, AppState state) async {
  final field = TextEditingController(text: state.api.baseUrl);
  final url = await showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Server address'),
      content: TextField(
        controller: field,
        autofocus: true,
        keyboardType: TextInputType.url,
        decoration: const InputDecoration(hintText: 'http://192.168.1.5:8000'),
        onSubmitted: (value) => Navigator.pop(context, value),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        TextButton(onPressed: () => Navigator.pop(context, field.text), child: const Text('Save')),
      ],
    ),
  );
  if (url != null && url.trim().isNotEmpty) await state.setApiUrl(url);
}

/// The "Add material" sheet: pick a subject (or name a new one), pick a file, upload.
Future<void> addMaterial(BuildContext context, AppState state, {Subject? into}) =>
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => _AddMaterialSheet(state, into),
    );

class _AddMaterialSheet extends StatefulWidget {
  const _AddMaterialSheet(this.state, this.into);
  final AppState state;
  final Subject? into;

  @override
  State<_AddMaterialSheet> createState() => _AddMaterialSheetState();
}

class _AddMaterialSheetState extends State<_AddMaterialSheet> {
  final name = TextEditingController();
  late int? subjectId = widget.into?.id; // null = make a new subject
  DateTime? examDate;
  PlatformFile? file;
  bool busy = false;
  String? error;

  Future<void> pickFile() async {
    final picked = await FilePicker.pickFiles(
        type: FileType.custom, allowedExtensions: ['pdf', 'pptx']);
    if (picked.isNotEmpty) setState(() => file = picked.first);
  }

  Future<void> pickDate() async {
    final today = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: examDate ?? today.add(const Duration(days: 7)),
      firstDate: today,
      lastDate: today.add(const Duration(days: 365)),
    );
    if (date != null) setState(() => examDate = date);
  }

  Future<void> upload() async {
    if (subjectId == null && name.text.trim().isEmpty) {
      return setState(() => error = 'Give the subject a name.');
    }
    if (file == null) return setState(() => error = 'Choose a .pdf or .pptx file.');
    setState(() {
      busy = true;
      error = null;
    });
    final api = widget.state.api;
    try {
      final bytes = await file!.readAsBytes();
      final id = subjectId ?? (await api.createSubject(name.text.trim(), examDate)).id;
      subjectId = id; // if the upload fails, a second try reuses this subject
      final added = await api.uploadMaterial(id, file!.name, bytes);
      await widget.state.refresh();
      await widget.state.open(id);
      if (!mounted) return;
      Navigator.pop(context);
      showMessage(context, '$added ${added == 1 ? 'topic' : 'topics'} found in ${file!.name}');
    } on ApiError catch (e) {
      await widget.state.refresh();
      if (mounted) {
        setState(() {
          busy = false;
          error = e.message;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final subjects = widget.state.subjects;
    return Padding(
      // Keeps the sheet above the keyboard.
      padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('ADD MATERIAL', style: label()),
          const SizedBox(height: 14),
          if (subjects.isNotEmpty) ...[
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final s in subjects)
                ChoiceChip(
                  label: Text(s.name),
                  selected: subjectId == s.id,
                  onSelected: busy ? null : (_) => setState(() => subjectId = s.id),
                ),
              ChoiceChip(
                label: const Text('+ New subject'),
                selected: subjectId == null,
                onSelected: busy ? null : (_) => setState(() => subjectId = null),
              ),
            ]),
            const SizedBox(height: 14),
          ],
          if (subjectId == null) ...[
            TextField(
              controller: name,
              enabled: !busy,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(hintText: 'Subject, for example Operating Systems'),
            ),
            const SizedBox(height: 10),
            OutlinedButton(
              onPressed: busy ? null : pickDate,
              child: Text(examDate == null
                  ? 'Exam date (optional)'
                  : 'Exam: ${examDate!.day}.${examDate!.month}.${examDate!.year}'),
            ),
            const SizedBox(height: 10),
          ],
          OutlinedButton(
            onPressed: busy ? null : pickFile,
            child: Text(file?.name ?? 'Choose a lecture (.pdf, .pptx)', overflow: TextOverflow.ellipsis),
          ),
          if (error != null) ...[
            const SizedBox(height: 12),
            Text(error!, style: const TextStyle(color: C.red)),
          ],
          const SizedBox(height: 16),
          FilledButton(
            onPressed: busy ? null : upload,
            child: busy
                ? const Row(mainAxisSize: MainAxisSize.min, children: [
                    SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)),
                    SizedBox(width: 12),
                    Text('Reading your lecture…'),
                  ])
                : const Text('Upload'),
          ),
        ]),
      ),
    );
  }
}

/// Rename a subject, change its exam date, or delete it.
Future<void> editSubject(BuildContext context, AppState state, Subject subject) async {
  final name = TextEditingController(text: subject.name);
  var examDate = subject.examDate;
  final action = await showDialog<String>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: const Text('Subject'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: name),
          const SizedBox(height: 10),
          OutlinedButton(
            onPressed: () async {
              final today = DateTime.now();
              final date = await showDatePicker(
                context: context,
                initialDate: examDate != null && examDate!.isAfter(today) ? examDate! : today,
                firstDate: today,
                lastDate: today.add(const Duration(days: 365)),
              );
              if (date != null) setState(() => examDate = date);
            },
            child: Text(examDate == null
                ? 'Set exam date'
                : 'Exam: ${examDate!.day}.${examDate!.month}.${examDate!.year}'),
          ),
        ]),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, 'delete'),
            child: const Text('Delete', style: TextStyle(color: C.red)),
          ),
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, 'save'), child: const Text('Save')),
        ],
      ),
    ),
  );
  if (action == null || !context.mounted) return;

  try {
    if (action == 'save' && name.text.trim().isNotEmpty) {
      await state.api.updateSubject(subject.id, name.text.trim(), examDate);
    } else if (action == 'delete') {
      final sure = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('Delete ${subject.name}?'),
          content: const Text('Its topics and all your answers will be deleted too.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Delete', style: TextStyle(color: C.red)),
            ),
          ],
        ),
      );
      if (sure != true) return;
      await state.api.deleteSubject(subject.id);
    }
    if (state.current?.id == subject.id) state.current = null;
    await state.refresh();
  } on ApiError catch (e) {
    if (context.mounted) showMessage(context, e.message);
  }
}
