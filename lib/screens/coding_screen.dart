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
  // Position of the question in the full quiz list. Required so we can
  // address the same positional state key the rest of the quiz uses
  // (`AttemptState.stateKeyFor`).  Without this, reading/writing
  // `codeAnswers[question.id]` would collide when the server re-uses
  // short integer ids across questions.
  int? _globalIndex;
  String? _stateKey;
  Timer? _debounce;
  bool _initialized = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    _initialized = true;
    final args = ModalRoute.of(context)?.settings.arguments;
    if (args is List && args.length >= 2 && args[0] is Question) {
      _question = args[0] as Question;
      _globalIndex = args[1] as int?;
      if (_globalIndex != null) {
        _stateKey = AttemptState.stateKeyFor(_question!, _globalIndex!);
      }
    } else {
      // Backwards-compat: if launched with just a Question, fall back to
      // the raw id. This won't be hit by the in-app flow, but keeps the
      // screen usable from a deep link or test harness.
      _question = args as Question?;
    }
    final state = context.read<AttemptState>();
    final initial =
        _stateKey != null ? (state.codeAnswers[_stateKey] ?? '') : '';
    _controller = TextEditingController(text: initial);
    _controller.addListener(_onTextChanged);
  }

  void _onTextChanged() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 1500), () {
      if (_question != null && mounted) {
        final state = context.read<AttemptState>();
        if (_stateKey != null) {
          state.saveCodeAnswer(_stateKey!, _controller.text);
        }
      }
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    if (_question != null && _stateKey != null) {
      // Save on exit using the positional state key, not question.id.
      context.read<AttemptState>().saveCodeAnswer(_stateKey!, _controller.text);
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
        if (_stateKey != null) {
          context.read<AttemptState>().saveCodeAnswer(_stateKey!, _controller.text);
        }
        Navigator.of(context).pop();
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Code Editor'),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () {
              _debounce?.cancel();
              if (_stateKey != null) {
                context.read<AttemptState>().saveCodeAnswer(_stateKey!, _controller.text);
              }
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

