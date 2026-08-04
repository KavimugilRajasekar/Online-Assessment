import 'dart:async';
import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
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
  bool _generatingPdf = false;
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

  // ─── PDF Generation ────────────────────────────────────────────────────────
  Future<void> _downloadPdf() async {
    setState(() => _generatingPdf = true);
    try {
      final doc = pw.Document();
      final greenColor = PdfColor.fromHex('059669');
      final lightGreen = PdfColor.fromHex('ECFDF5');
      final amberColor = PdfColor.fromHex('D97706');
      final amberLight = PdfColor.fromHex('FFFBEB');
      final darkText = PdfColor.fromHex('1E293B');
      final mutedText = PdfColor.fromHex('64748B');
      final purpleColor = PdfColor.fromHex('7C3AED');
      final purpleLight = PdfColor.fromHex('F5F3FF');

      int globalQ = 0;

      for (final topic in _topics) {
        final List<pw.Widget> pageWidgets = [];

        // Topic header
        pageWidgets.add(
          pw.Container(
            padding: const pw.EdgeInsets.all(12),
            decoration: pw.BoxDecoration(
              color: greenColor,
              borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
            ),
            child: pw.Text(
              topic.name,
              style: pw.TextStyle(
                color: PdfColors.white,
                fontWeight: pw.FontWeight.bold,
                fontSize: 15,
              ),
            ),
          ),
        );
        pageWidgets.add(pw.SizedBox(height: 12));

        for (final sub in topic.subtopics) {
          if (sub.name.isNotEmpty && sub.name != topic.name) {
            pageWidgets.add(
              pw.Padding(
                padding: const pw.EdgeInsets.only(bottom: 6),
                child: pw.Text(
                  sub.name,
                  style: pw.TextStyle(
                    color: greenColor,
                    fontWeight: pw.FontWeight.bold,
                    fontSize: 11,
                  ),
                ),
              ),
            );
          }

          for (final q in sub.questions) {
            globalQ++;
            final isCode = q.qtype == 'coding';
            final isCodeMcq = q.qtype == 'code_mcq';
            final isMulti = q.qtype == 'mcq_multi';

            final typeLabel = isCode
                ? 'Coding'
                : isCodeMcq
                    ? 'Code MCQ'
                    : isMulti
                        ? 'Multi-Select'
                        : 'Single Choice';

            final qWidgets = <pw.Widget>[
              // Q number + text
              pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Container(
                    width: 22,
                    height: 22,
                    decoration: pw.BoxDecoration(
                      color: lightGreen,
                      borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
                    ),
                    child: pw.Center(
                      child: pw.Text(
                        '$globalQ',
                        style: pw.TextStyle(
                          color: greenColor,
                          fontWeight: pw.FontWeight.bold,
                          fontSize: 10,
                        ),
                      ),
                    ),
                  ),
                  pw.SizedBox(width: 8),
                  pw.Expanded(
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text(
                          q.text,
                          style: pw.TextStyle(
                            fontWeight: pw.FontWeight.bold,
                            fontSize: 12,
                            color: darkText,
                          ),
                        ),
                        pw.SizedBox(height: 3),
                        pw.Row(children: [
                          pw.Container(
                            padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: pw.BoxDecoration(
                              color: isCode ? purpleLight : lightGreen,
                              borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
                            ),
                            child: pw.Text(
                              typeLabel,
                              style: pw.TextStyle(
                                color: isCode ? purpleColor : greenColor,
                                fontSize: 8,
                                fontWeight: pw.FontWeight.bold,
                              ),
                            ),
                          ),
                          pw.SizedBox(width: 6),
                          pw.Container(
                            padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: pw.BoxDecoration(
                              color: amberLight,
                              borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
                            ),
                            child: pw.Text(
                              '${q.marks.toStringAsFixed(q.marks == q.marks.truncateToDouble() ? 0 : 1)} mark${q.marks != 1 ? "s" : ""}',
                              style: pw.TextStyle(color: amberColor, fontSize: 8, fontWeight: pw.FontWeight.bold),
                            ),
                          ),
                        ]),
                      ],
                    ),
                  ),
                ],
              ),
            ];

            // Code block — show for any question that has code,
            // except pure coding rounds (reference solution must stay hidden).
            if (!isCode && q.code.isNotEmpty) {
              qWidgets.add(pw.SizedBox(height: 6));
              qWidgets.add(
                pw.Container(
                  padding: const pw.EdgeInsets.all(8),
                  decoration: pw.BoxDecoration(
                    color: PdfColor.fromHex('1E293B'),
                    borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
                  ),
                  child: pw.Text(
                    q.code,
                    style: pw.TextStyle(
                      font: pw.Font.courier(),
                      fontSize: 9,
                      color: PdfColor.fromHex('94A3B8'),
                    ),
                  ),
                ),
              );
            }

            // Choices
            if (!isCode && q.choices.isNotEmpty) {
              qWidgets.add(pw.SizedBox(height: 6));
              for (final c in q.choices) {
                final isCorrect = q.answers.contains(c.id);
                qWidgets.add(
                  pw.Container(
                    margin: const pw.EdgeInsets.only(bottom: 4),
                    padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: pw.BoxDecoration(
                      color: isCorrect ? lightGreen : PdfColor.fromHex('F8FAFC'),
                      border: pw.Border.all(
                        color: isCorrect ? PdfColor.fromHex('34D399') : PdfColor.fromHex('E2E8F0'),
                        width: isCorrect ? 1.5 : 0.5,
                      ),
                      borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
                    ),
                    child: pw.Row(
                      children: [
                        pw.Text(
                          isCorrect ? '[X]' : '[ ]',
                          style: pw.TextStyle(
                            color: isCorrect ? greenColor : mutedText,
                            fontWeight: pw.FontWeight.bold,
                            fontSize: 11,
                          ),
                        ),
                        pw.SizedBox(width: 8),
                        pw.Expanded(
                          child: pw.Text(
                            c.text,
                            style: pw.TextStyle(
                              fontSize: 10,
                              color: isCorrect ? PdfColor.fromHex('065F46') : darkText,
                              fontWeight: isCorrect ? pw.FontWeight.bold : pw.FontWeight.normal,
                            ),
                          ),
                        ),
                        if (isCorrect)
                          pw.Text(
                            'Correct',
                            style: pw.TextStyle(
                              color: greenColor,
                              fontSize: 8,
                              fontWeight: pw.FontWeight.bold,
                            ),
                          ),
                      ],
                    ),
                  ),
                );
              }
            }

            // Coding round — the candidate writes their own code, so the
            // reference answer must never be published. Show only a note.
            if (isCode) {
              qWidgets.add(pw.SizedBox(height: 6));
              qWidgets.add(
                pw.Container(
                  padding: const pw.EdgeInsets.all(8),
                  decoration: pw.BoxDecoration(
                    color: purpleLight,
                    border: pw.Border.all(color: PdfColor.fromHex('DDD6FE'), width: 0.5),
                    borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
                  ),
                  child: pw.Text(
                    'Coding answers are reviewed manually by the examiner.',
                    style: pw.TextStyle(fontSize: 9, color: purpleColor, fontStyle: pw.FontStyle.italic),
                  ),
                ),
              );
            }

            // Explanation
            if (q.explanation.isNotEmpty) {
              qWidgets.add(pw.SizedBox(height: 6));
              qWidgets.add(
                pw.Container(
                  padding: const pw.EdgeInsets.all(8),
                  decoration: pw.BoxDecoration(
                    color: amberLight,
                    border: pw.Border.all(color: PdfColor.fromHex('FDE68A'), width: 0.5),
                    borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
                  ),
                  child: pw.Text(
                    'Explanation: ${q.explanation}',
                    style: pw.TextStyle(fontSize: 9, color: PdfColor.fromHex('92400E')),
                  ),
                ),
              );
            }

            pageWidgets.add(
              pw.Container(
                margin: const pw.EdgeInsets.only(bottom: 10),
                padding: const pw.EdgeInsets.all(10),
                decoration: pw.BoxDecoration(
                  color: PdfColors.white,
                  border: pw.Border.all(color: PdfColor.fromHex('D1FAE5'), width: 0.8),
                  borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
                ),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: qWidgets,
                ),
              ),
            );
          }
        }

        doc.addPage(
          pw.MultiPage(
            pageFormat: PdfPageFormat.a4,
            margin: const pw.EdgeInsets.all(24),
            header: (ctx) => pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Expanded(
                      child: pw.Text(
                        _quizTitle,
                        style: pw.TextStyle(
                          fontWeight: pw.FontWeight.bold,
                          fontSize: 14,
                          color: darkText,
                        ),
                      ),
                    ),
                    pw.Container(
                      padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: pw.BoxDecoration(
                        color: lightGreen,
                        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
                      ),
                      child: pw.Text(
                        'Answer Key',
                        style: pw.TextStyle(color: greenColor, fontSize: 9, fontWeight: pw.FontWeight.bold),
                      ),
                    ),
                  ],
                ),
                pw.SizedBox(height: 4),
                pw.Divider(color: PdfColor.fromHex('E2E8F0'), thickness: 0.5),
                pw.SizedBox(height: 8),
              ],
            ),
            footer: (ctx) => pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text('Generated by Online Assessment Platform',
                    style: pw.TextStyle(color: mutedText, fontSize: 8)),
                pw.Text('Page ${ctx.pageNumber} of ${ctx.pagesCount}',
                    style: pw.TextStyle(color: mutedText, fontSize: 8)),
              ],
            ),
            build: (ctx) => pageWidgets,
          ),
        );
      }

      final bytes = await doc.save();
      await Printing.sharePdf(bytes: bytes, filename: '${_quizTitle.replaceAll(' ', '_')}_Answer_Key.pdf');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('PDF generation failed: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _generatingPdf = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          // ── Header ──────────────────────────────────────────────────────────
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
                padding: const EdgeInsets.fromLTRB(8, 12, 12, 18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.arrow_back_ios_new_rounded,
                              color: Colors.white, size: 20),
                          onPressed: () => Navigator.of(context).pop(),
                        ),
                        const SizedBox(width: 2),
                        // Title — wraps freely, no ellipsis
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.only(top: 12),
                            child: Text(
                              _quizTitle,
                              style: const TextStyle(
                                fontFamily: BwbTheme.fontFamily,
                                color: Colors.white,
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                height: 1.3,
                              ),
                              softWrap: true,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        // PDF Download button
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: _generatingPdf
                              ? const SizedBox(
                                  width: 28,
                                  height: 28,
                                  child: CircularProgressIndicator(
                                    color: Colors.white,
                                    strokeWidth: 2.5,
                                  ),
                                )
                              : Tooltip(
                                  message: 'Download Answer Key PDF',
                                  child: InkWell(
                                    borderRadius: BorderRadius.circular(10),
                                    onTap: _loading || _error != null ? null : _downloadPdf,
                                    child: Container(
                                      padding: const EdgeInsets.all(8),
                                      decoration: BoxDecoration(
                                        color: Colors.white.withValues(alpha: 0.2),
                                        borderRadius: BorderRadius.circular(10),
                                        border: Border.all(
                                            color: Colors.white.withValues(alpha: 0.35),
                                            width: 1),
                                      ),
                                      child: const Icon(
                                        Icons.download_rounded,
                                        color: Colors.white,
                                        size: 20,
                                      ),
                                    ),
                                  ),
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
                    // if (_quizDescription.isNotEmpty) ...[
                    //   const SizedBox(height: 6),
                    //   Padding(
                    //     padding: const EdgeInsets.only(left: 44),
                    //     child: Text(
                    //       _quizDescription,
                    //       style: TextStyle(
                    //           color: Colors.white.withValues(alpha: 0.8), fontSize: 12),
                    //       softWrap: true,
                    //     ),
                    //   ),
                    // ],
                  ],
                ),
              ),
            ),
          ),

          // ── Body ─────────────────────────────────────────────────────────────
          Expanded(
            child: _loading
                ? const Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircularProgressIndicator(color: Color(0xFF10B981)),
                        SizedBox(height: 12),
                        Text('Loading answer key…',
                            style: TextStyle(color: BwbTheme.muted)),
                      ],
                    ),
                  )
                : _error != null
                    ? _buildError()
                    : FadeTransition(
                        opacity: _fadeAnimation, child: _buildContent()),
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
            const Text(
              'Answer key not available',
              style: TextStyle(
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
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
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
        child: Text('No questions found.',
            style: TextStyle(color: BwbTheme.muted)),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
      itemCount: _topics.length,
      itemBuilder: (ctx, ti) {
        final topic = _topics[ti];
        final isExpanded = _expandedTopic == ti;
        final totalTopicQs =
            topic.subtopics.fold(0, (sum, s) => sum + s.questions.length);

        int beforeCount = 0;
        for (int i = 0; i < ti; i++) {
          beforeCount += _topics[i]
              .subtopics
              .fold(0, (s, sub) => s + sub.questions.length);
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Topic header (expandable) ──────────────────────────────
            GestureDetector(
              onTap: () =>
                  setState(() => _expandedTopic = isExpanded ? -1 : ti),
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
                          colors: [Colors.grey.shade50, Colors.grey.shade100],
                        ),
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: (isExpanded
                              ? const Color(0xFF10B981)
                              : Colors.grey)
                          .withValues(alpha: 0.15),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Number circle
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
                            color: isExpanded
                                ? Colors.white
                                : const Color(0xFF059669),
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    // Topic name — wraps fully, no ellipsis
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
                              height: 1.35,
                            ),
                            softWrap: true, // ← wraps instead of truncating
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '$totalTopicQs question${totalTopicQs != 1 ? "s" : ""}',
                            style: TextStyle(
                              fontSize: 11,
                              color: isExpanded
                                  ? Colors.white.withValues(alpha: 0.8)
                                  : BwbTheme.muted,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 6),
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Icon(
                        isExpanded
                            ? Icons.expand_less_rounded
                            : Icons.expand_more_rounded,
                        color: isExpanded ? Colors.white : BwbTheme.muted,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // ── Questions (visible when expanded) ─────────────────────
            if (isExpanded)
              ...topic.subtopics.expand((sub) {
                final widgets = <Widget>[];
                if (sub.name.isNotEmpty && sub.name != topic.name) {
                  widgets.add(
                    Padding(
                      padding:
                          const EdgeInsets.only(left: 4, bottom: 6, top: 2),
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
  _SubtopicData(
      {required this.id, required this.name, required this.questions});
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

// ─── Question card widget ─────────────────────────────────────────────────────
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
                        softWrap: true,
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
                            label:
                                '${q.marks.toStringAsFixed(q.marks == q.marks.truncateToDouble() ? 0 : 1)} mark${q.marks != 1 ? "s" : ""}',
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

          // Code snippet — show for any question type that has code,
          // including code_mcq, regular MCQ with a code prompt, etc.
          // Only coding-round questions hide their code (reference solution).
          if (!isCode && q.code.isNotEmpty) ...[
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

          // MCQ Choices
          if (!isCode && q.choices.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Column(
                children: q.choices.map((c) {
                  final isCorrect = q.answers.contains(c.id);
                  return Container(
                    margin: const EdgeInsets.only(bottom: 6),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 9),
                    decoration: BoxDecoration(
                      color: isCorrect
                          ? const Color(0xFFECFDF5)
                          : const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: isCorrect
                            ? const Color(0xFF34D399)
                            : Colors.grey.shade200,
                        width: isCorrect ? 1.5 : 1,
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          isCorrect
                              ? Icons.check_circle_rounded
                              : Icons.circle_outlined,
                          size: 16,
                          color: isCorrect
                              ? const Color(0xFF059669)
                              : Colors.grey.shade400,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            c.text,
                            style: TextStyle(
                              fontSize: 13,
                              color: isCorrect
                                  ? const Color(0xFF065F46)
                                  : BwbTheme.text,
                              fontWeight: isCorrect
                                  ? FontWeight.w600
                                  : FontWeight.normal,
                            ),
                            softWrap: true,
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

          // Coding round — candidates write their own code, so the
          // reference solution must never be published in the answer key.
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
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.code_rounded,
                        color: Color(0xFF7C3AED), size: 16),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        'Coding answers are reviewed manually by the examiner. '
                        'No reference solution is published.',
                        style: TextStyle(
                          color: Color(0xFF5B21B6),
                          fontSize: 12,
                          fontStyle: FontStyle.italic,
                          height: 1.4,
                        ),
                        softWrap: true,
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
                  const Icon(Icons.lightbulb_outline_rounded,
                      size: 14, color: Color(0xFFD97706)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      q.explanation,
                      style: const TextStyle(
                        color: Color(0xFF92400E),
                        fontSize: 12,
                        height: 1.4,
                      ),
                      softWrap: true,
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
