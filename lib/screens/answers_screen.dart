import 'dart:async';
import 'package:flutter/material.dart';
import '../services/api_client.dart';
import '../theme.dart';

class AnswersScreen extends StatefulWidget {
  final String quizId;
  final String quizTitle;

  const AnswersScreen({super.key, required this.quizId, required this.quizTitle});

  @override
  State<AnswersScreen> createState() => _AnswersScreenState();
}

class _AnswersScreenState extends State<AnswersScreen> with SingleTickerProviderStateMixin {
  late final AnimationController _fadeController;
  late final Animation<double> _fadeAnimation;

  bool _loading = true;
  String? _error;
  List<_TopicData> _topics = [];
  String _quizTitle = '';
  String _quizDescription = '';
  int _expandedTopic = 0;

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(vsync: this, duration: const Duration(milliseconds: 500));
    _fadeAnimation = CurvedAnimation(parent: _fadeController, curve: Curves.easeIn);
    _quizTitle = widget.quizTitle;
    _loadAnswers();
  }

  @override
  void dispose() {
    _fadeController.dispose();
    super.dispose();
  }

  Future<void> _loadAnswers() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await ApiClient.instance.get('/api/quizzes/${widget.quizId}/answers/');
      final raw = data as Map<String, dynamic>;
      _quizTitle = raw['title'] as String? ?? widget.quizTitle;
      _quizDescription = raw['description'] as String? ?? '';
      final topicsRaw = raw['topics'] as List? ?? [];
      _topics = topicsRaw.map((t) {
        final topicMap = Map<String, dynamic>.from(t as Map);
        final subtopics = (topicMap['subtopics'] as List? ?? []).map((s) {
          final subMap = Map<String, dynamic>.from(s as Map);
          final questions = (subMap['questions'] as List? ?? []).map((q) {
            final qMap = Map<String, dynamic>.from(q as Map);
            final choices = (qMap['choices'] as List? ?? []).map((c) {
              final cMap = Map<String, dynamic>.from(c as Map);
              return _ChoiceData(id: cMap['id'].toString(), text: cMap['text'].toString());
            }).toList();
            final answerRaw = qMap['answer'];
            final answers = answerRaw is List
                ? answerRaw.map((e) => e.toString()).toList()
                : answerRaw != null
                    ? [answerRaw.toString()]
                    : <String>[];
            return _QuestionData(
              id: qMap['id'].toString(),
              text: qMap['text'].toString(),
              qtype: qMap['qtype'].toString(),
              marks: (qMap['marks'] as num?)?.toDouble() ?? 1.0,
              code: qMap['code']?.toString() ?? '',
              explanation: qMap['explanation']?.toString() ?? '',
              choices: choices,
              answers: answers,
            );
          }).toList();
          return _SubtopicData(
            id: subMap['id'].toString(),
            name: subMap['name'].toString(),
            questions: questions,
          );
        }).toList();
        return _TopicData(
          id: topicMap['id'].toString(),
          name: topicMap['name'].toString(),
          subtopics: subtopics,
        );
      }).toList();
      setState(() => _loading = false);
      _fadeController.forward();
    } catch (e) {
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          // Header
          Container(
            width: double.infinity,
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFF059669), Color(0xFF10B981)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        IconButton(
                          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 20),
                          onPressed: () => Navigator.of(context).pop(),
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            _quizTitle,
                            style: const TextStyle(
                              fontFamily: BwbTheme.fontFamily,
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Padding(
                      padding: const EdgeInsets.only(left: 44),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.menu_book_rounded, color: Colors.white, size: 14),
                            SizedBox(width: 6),
                            Text(
                              'Answer Key Published',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (_quizDescription.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Padding(
                        padding: const EdgeInsets.only(left: 44),
                        child: Text(
                          _quizDescription,
                          style: TextStyle(color: Colors.white.withValues(alpha: 0.8), fontSize: 12),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),

          // Body
          Expanded(
            child: _loading
                ? const Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircularProgressIndicator(color: Color(0xFF10B981)),
                        SizedBox(height: 12),
                        Text('Loading answer key…', style: TextStyle(color: BwbTheme.muted)),
                      ],
                    ),
                  )
                : _error != null
                    ? _buildError()
                    : FadeTransition(opacity: _fadeAnimation, child: _buildContent()),
          ),
        ],
      ),
    );
  }

  Widget _buildError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.lock_outline_rounded, size: 48, color: BwbTheme.muted),
            const SizedBox(height: 12),
            Text(
              'Answer key not available',
              style: const TextStyle(
                fontFamily: BwbTheme.fontFamily,
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: BwbTheme.text,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              _error ?? '',
              style: const TextStyle(color: BwbTheme.muted, fontSize: 13),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: _loadAnswers,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Retry'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF10B981),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContent() {
    if (_topics.isEmpty) {
      return const Center(
        child: Text('No questions found.', style: TextStyle(color: BwbTheme.muted)),
      );
    }



    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
      itemCount: _topics.length,
      itemBuilder: (ctx, ti) {
        final topic = _topics[ti];
        final isExpanded = _expandedTopic == ti;
        final totalTopicQs = topic.subtopics.fold(0, (sum, s) => sum + s.questions.length);

        // Count questions before this topic for global numbering
        int beforeCount = 0;
        for (int i = 0; i < ti; i++) {
          beforeCount += _topics[i].subtopics.fold(0, (s, sub) => s + sub.questions.length);
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Topic header (expandable)
            GestureDetector(
              onTap: () => setState(() => _expandedTopic = isExpanded ? -1 : ti),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  gradient: isExpanded
                      ? const LinearGradient(
                          colors: [Color(0xFF059669), Color(0xFF10B981)],
                        )
                      : LinearGradient(
                          colors: [
                            Colors.grey.shade50,
                            Colors.grey.shade100,
                          ],
                        ),
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: (isExpanded ? const Color(0xFF10B981) : Colors.grey)
                          .withValues(alpha: 0.15),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: isExpanded
                            ? Colors.white.withValues(alpha: 0.25)
                            : const Color(0xFFD1FAE5),
                        shape: BoxShape.circle,
                      ),
                      child: Center(
                        child: Text(
                          '${ti + 1}',
                          style: TextStyle(
                            color: isExpanded ? Colors.white : const Color(0xFF059669),
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            topic.name,
                            style: TextStyle(
                              fontFamily: BwbTheme.fontFamily,
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                              color: isExpanded ? Colors.white : BwbTheme.text,
                            ),
                          ),
                          Text(
                            '$totalTopicQs questions',
                            style: TextStyle(
                              fontSize: 11,
                              color: isExpanded ? Colors.white.withValues(alpha: 0.8) : BwbTheme.muted,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Icon(
                      isExpanded ? Icons.expand_less_rounded : Icons.expand_more_rounded,
                      color: isExpanded ? Colors.white : BwbTheme.muted,
                    ),
                  ],
                ),
              ),
            ),

            // Questions (visible when expanded)
            if (isExpanded)
              ...topic.subtopics.expand((sub) {
                final widgets = <Widget>[];
                if (sub.name.isNotEmpty && sub.name != topic.name) {
                  widgets.add(
                    Padding(
                      padding: const EdgeInsets.only(left: 4, bottom: 6, top: 2),
                      child: Text(
                        sub.name,
                        style: const TextStyle(
                          color: Color(0xFF059669),
                          fontWeight: FontWeight.w600,
                          fontSize: 12,
                          letterSpacing: 0.4,
                        ),
                      ),
                    ),
                  );
                }
                for (final q in sub.questions) {
                  beforeCount++;
                  widgets.add(_QuestionCard(
                    number: beforeCount,
                    question: q,
                  ));
                }
                return widgets;
              }),

            if (ti < _topics.length - 1) const SizedBox(height: 4),
          ],
        );
      },
    );
  }
}

// ─── Data models ──────────────────────────────────────────────────────────────
class _TopicData {
  final String id, name;
  final List<_SubtopicData> subtopics;
  _TopicData({required this.id, required this.name, required this.subtopics});
}

class _SubtopicData {
  final String id, name;
  final List<_QuestionData> questions;
  _SubtopicData({required this.id, required this.name, required this.questions});
}

class _QuestionData {
  final String id, text, qtype, code, explanation;
  final double marks;
  final List<_ChoiceData> choices;
  final List<String> answers;
  _QuestionData({
    required this.id,
    required this.text,
    required this.qtype,
    required this.marks,
    required this.code,
    required this.explanation,
    required this.choices,
    required this.answers,
  });
}

class _ChoiceData {
  final String id, text;
  _ChoiceData({required this.id, required this.text});
}

// ─── Question card ─────────────────────────────────────────────────────────────
class _QuestionCard extends StatelessWidget {
  final int number;
  final _QuestionData question;
  const _QuestionCard({required this.number, required this.question});

  @override
  Widget build(BuildContext context) {
    final q = question;
    final isCode = q.qtype == 'coding';
    final isCodeMcq = q.qtype == 'code_mcq';
    final isMulti = q.qtype == 'mcq_multi';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFD1FAE5), width: 1.2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Question header
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 26,
                  height: 26,
                  decoration: BoxDecoration(
                    color: const Color(0xFFECFDF5),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Center(
                    child: Text(
                      '$number',
                      style: const TextStyle(
                        color: Color(0xFF059669),
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        q.text,
                        style: const TextStyle(
                          fontFamily: BwbTheme.fontFamily,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: BwbTheme.text,
                          height: 1.4,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          _Tag(
                            label: isCode
                                ? 'Coding'
                                : isCodeMcq
                                    ? 'Code MCQ'
                                    : isMulti
                                        ? 'Multi-Select'
                                        : 'Single Choice',
                            color: isCode
                                ? const Color(0xFF7C3AED)
                                : isCodeMcq
                                    ? const Color(0xFF2563EB)
                                    : const Color(0xFF059669),
                          ),
                          const SizedBox(width: 6),
                          _Tag(
                            label: '${q.marks.toStringAsFixed(q.marks == q.marks.truncateToDouble() ? 0 : 1)} mark${q.marks != 1 ? "s" : ""}',
                            color: const Color(0xFFD97706),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Code snippet
          if ((isCodeMcq || isCode) && q.code.isNotEmpty) ...[
            const SizedBox(height: 10),
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 14),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF1E293B),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                q.code,
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 12,
                  color: Color(0xFF94A3B8),
                  height: 1.5,
                ),
              ),
            ),
          ],

          const SizedBox(height: 10),

          // Choices (for MCQ types)
          if (!isCode && q.choices.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Column(
                children: q.choices.map((c) {
                  final isCorrect = q.answers.contains(c.id);
                  return Container(
                    margin: const EdgeInsets.only(bottom: 6),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                    decoration: BoxDecoration(
                      color: isCorrect ? const Color(0xFFECFDF5) : const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: isCorrect ? const Color(0xFF34D399) : Colors.grey.shade200,
                        width: isCorrect ? 1.5 : 1,
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          isCorrect ? Icons.check_circle_rounded : Icons.circle_outlined,
                          size: 16,
                          color: isCorrect ? const Color(0xFF059669) : Colors.grey.shade400,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            c.text,
                            style: TextStyle(
                              fontSize: 13,
                              color: isCorrect ? const Color(0xFF065F46) : BwbTheme.text,
                              fontWeight: isCorrect ? FontWeight.w600 : FontWeight.normal,
                            ),
                          ),
                        ),
                        if (isCorrect)
                          const Text(
                            '✓ Correct',
                            style: TextStyle(
                              fontSize: 11,
                              color: Color(0xFF059669),
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                      ],
                    ),
                  );
                }).toList(),
              ),
            ),
          ],

          // Coding answer note
          if (isCode) ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFF5F3FF),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFDDD6FE)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.code_rounded, color: Color(0xFF7C3AED), size: 16),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        q.answers.isNotEmpty
                            ? q.answers.first
                            : 'Open-ended coding question — no single correct answer.',
                        style: const TextStyle(
                          color: Color(0xFF5B21B6),
                          fontSize: 12,
                          fontFamily: 'monospace',
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],

          // Explanation
          if (q.explanation.isNotEmpty) ...[
            const SizedBox(height: 8),
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 14),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFFFFBEB),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFFDE68A)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.lightbulb_outline_rounded, size: 14, color: Color(0xFFD97706)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      q.explanation,
                      style: const TextStyle(
                        color: Color(0xFF92400E),
                        fontSize: 12,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],

          const SizedBox(height: 14),
        ],
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  final String label;
  final Color color;
  const _Tag({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.3,
        ),
      ),
    );
  }
}
