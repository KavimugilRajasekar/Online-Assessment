import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/question.dart';
import '../state/attempt_state.dart';
import '../widgets/code_editor_field.dart';

class CodingScreen extends StatefulWidget {
  const CodingScreen({super.key});

  @override
  State<CodingScreen> createState() => _CodingScreenState();
}

class _CodingScreenState extends State<CodingScreen> {
  late TextEditingController _controller;
  Question? _question;
  Timer? _debounce;
  bool _initialized = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    _initialized = true;
    _question = ModalRoute.of(context)?.settings.arguments as Question?;
    final state = context.read<AttemptState>();
    final initial =
        state.codeAnswers[_question?.id] ?? _question?.starterCode ?? '';
    _controller = TextEditingController(text: initial);
    _controller.addListener(_onTextChanged);
  }

  void _onTextChanged() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 1500), () {
      if (_question != null && mounted) {
        context.read<AttemptState>().saveCodeAnswer(_question!.id, _controller.text);
      }
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    if (_question != null) {
      // Save on exit
      context.read<AttemptState>().saveCodeAnswer(_question!.id, _controller.text);
    }
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final q = _question;
    if (q == null) {
      return const Scaffold(body: Center(child: Text('No question.')));
    }

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        _debounce?.cancel();
        context.read<AttemptState>().saveCodeAnswer(q.id, _controller.text);
        Navigator.of(context).pop();
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Code Editor'),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () {
              _debounce?.cancel();
              context.read<AttemptState>().saveCodeAnswer(q.id, _controller.text);
              Navigator.of(context).pop();
            },
          ),
        ),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(q.text, style: const TextStyle(fontSize: 16, height: 1.4)),
                const SizedBox(height: 16),
                Expanded(
                  child: CodeEditorField(
                    controller: _controller,
                    placeholder: q.starterCode.isNotEmpty ? q.starterCode : null,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

