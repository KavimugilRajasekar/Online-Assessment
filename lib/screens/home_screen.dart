import 'dart:async';
import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';
import 'package:provider/provider.dart';
import '../state/quiz_state.dart';
import '../state/attempt_state.dart';
import '../theme.dart';
import '../widgets/bwb_card.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _fadeController;
  late final Animation<double> _fadeAnimation;
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _fadeAnimation = CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeIn,
    );
    _fadeController.forward();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<QuizState>().loadQuizzes();
      // Silently submit any attempt that was left in_progress on the server
      // (app killed mid-quiz, timer expired while offline, etc.)
      context.read<AttemptState>().reconcileStaleAttempts();
    });

    // Background polling timer every 3 seconds
    _pollTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      if (mounted) {
        context.read<QuizState>().loadQuizzes(silent: true);
      }
    });
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _fadeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final quizState = context.watch<QuizState>();

    return Scaffold(
      body: SafeArea(
        child: FadeTransition(
          opacity: _fadeAnimation,
          child: CustomScrollView(
            slivers: [
              // Hero header
              SliverToBoxAdapter(
                child: Container(
                  width: double.infinity,
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Color(0xFF1e3a8a), Color(0xFF2563EB)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                  ),
                  child: SafeArea(
                    bottom: false,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(24, 20, 24, 28),
                      child: Column(
                        children: [
                          // Logo row
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(
                                    8,
                                  ), // Adjust as needed
                                  child: Image.asset(
                                    'assets/icons/online_assessment_logo.png',
                                    height: 32,
                                    width: 32,
                                    fit: BoxFit.cover,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              const Text(
                                'Online Assessment',
                                style: TextStyle(
                                  fontFamily: BwbTheme.fontFamily,
                                  color: Colors.white,
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 24),
                          // Lottie animation
                          SizedBox(
                            height: 140,
                            child: Lottie.asset(
                              'assets/json/cat_cloud.json',
                              fit: BoxFit.contain,
                            ),
                          ),
                          const SizedBox(height: 12),
                          const Text(
                            'Welcome!',
                            style: TextStyle(
                              fontFamily: BwbTheme.fontFamily,
                              color: Colors.white,
                              fontSize: 28,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Select a quiz below to begin your assessment.',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.8),
                              fontSize: 14,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),

              // Content
              SliverPadding(
                padding: const EdgeInsets.all(20),
                sliver: SliverToBoxAdapter(child: _buildBody(quizState)),
              ),

              // Footer
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 24, top: 8),
                  child: Text(
                    'Dev by Kavi',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey.shade400,
                      fontWeight: FontWeight.w500,
                      letterSpacing: 0.4,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBody(QuizState quizState) {
    if (quizState.loadState == QuizLoadState.loading) {
      return SizedBox(
        height: 200,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Lottie.asset('assets/json/searching.json', height: 100),
              const SizedBox(height: 12),
              const Text(
                'Loading quizzes...',
                style: TextStyle(color: BwbTheme.muted),
              ),
            ],
          ),
        ),
      );
    }

    if (quizState.loadState == QuizLoadState.error) {
      return Column(
        children: [
          Lottie.asset('assets/json/searching.json', height: 140),
          const SizedBox(height: 12),
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.wifi_off_rounded,
                  color: BwbTheme.wrong,
                  size: 42,
                ),
                const SizedBox(height: 8),
                const Text(
                  'Could not load quizzes.',
                  style: TextStyle(color: BwbTheme.wrong, fontSize: 14),
                ),
                const SizedBox(height: 1),
                TextButton(
                  onPressed: () => context.read<QuizState>().loadQuizzes(),
                  child: const Text('Retry'),
                ),
              ],
            ),
          ),
        ],
      );
    }

    if (quizState.quizzes.isEmpty) {
      return Column(
        children: [
          Lottie.asset('assets/json/searching.json', height: 130),
          const SizedBox(height: 16),
          const BwbCard(
            child: Column(
              children: [
                Icon(Icons.inbox_outlined, size: 36, color: BwbTheme.muted),
                SizedBox(height: 8),
                Text(
                  'No active quizzes at the moment.\nCheck back later!',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: BwbTheme.muted, fontSize: 14),
                ),
              ],
            ),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Available Assessments',
          style: TextStyle(
            fontFamily: BwbTheme.fontFamily,
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: BwbTheme.text,
          ),
        ),
        const SizedBox(height: 14),
        ListView.separated(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: quizState.quizzes.length,
          separatorBuilder: (_, _) => const SizedBox(height: 12),
          itemBuilder: (context, i) {
            final quiz = quizState.quizzes[i];
            final mins = quiz.durationSeconds ~/ 60;
            // A card is greyed out when this device has attempted it
            // but the admin hasn't published the answer key yet.
            final attempted =
                quizState.isAttempted(quiz.id) && !quiz.answersPosted;
            return _QuizCard(
              index: i,
              title: quiz.title,
              description: quiz.description,
              topicCount: quiz.topicCount,
              mins: mins,
              answersPosted: quiz.answersPosted,
              attempted: attempted,
              onTap: () {
                if (quiz.answersPosted) {
                  Navigator.of(context).pushNamed(
                    '/answers',
                    arguments: {'quizId': quiz.id, 'quizTitle': quiz.title},
                  );
                } else {
                  context.read<QuizState>().selectQuiz(quiz);
                  Navigator.of(context).pushNamed('/topics');
                }
              },
            );
          },
        ),
      ],
    );
  }
}

class _QuizCard extends StatefulWidget {
  final int index;
  final String title;
  final String description;
  final int topicCount;
  final int mins;
  final bool answersPosted;
  /// True when this device has already submitted this quiz and the
  /// answer key has NOT yet been published by the admin.
  final bool attempted;
  final VoidCallback onTap;

  const _QuizCard({
    required this.index,
    required this.title,
    required this.description,
    required this.topicCount,
    required this.mins,
    required this.answersPosted,
    required this.attempted,
    required this.onTap,
  });

  @override
  State<_QuizCard> createState() => _QuizCardState();
}

class _QuizCardState extends State<_QuizCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final isPosted   = widget.answersPosted;
    final isAttempted = widget.attempted && !isPosted; // grey only while waiting

    // ── Colour tokens ──────────────────────────────────────────────────────────
    final cardBg = isAttempted
        ? const Color(0xFFF3F4F6)   // cool grey
        : isPosted
            ? const Color(0xFFECFDF5) // mint green
            : Colors.white;

    final borderSide = isAttempted
        ? Border.all(color: const Color(0xFFD1D5DB), width: 1.5)
        : isPosted
            ? Border.all(color: const Color(0xFFa7f3d0), width: 1.5)
            : null;

    final shadowColor = isAttempted
        ? Colors.black
        : isPosted
            ? const Color(0xFF10B981)
            : BwbTheme.primary;

    final titleColor = isAttempted ? const Color(0xFF9CA3AF) : BwbTheme.text;
    final arrowColor = isAttempted
        ? const Color(0xFFD1D5DB)
        : isPosted
            ? const Color(0xFF059669)
            : BwbTheme.primary;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: borderSide,
        boxShadow: [
          BoxShadow(
            color: shadowColor.withValues(alpha: _hovered && !isAttempted ? 0.18 : 0.06),
            blurRadius: _hovered && !isAttempted ? 18 : 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: cardBg,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          // Greyed-out cards are not tappable
          onTap: isAttempted ? null : widget.onTap,
          onHover: isAttempted ? null : (v) => setState(() => _hovered = v),
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Title
                      Text(
                        widget.title,
                        style: TextStyle(
                          fontFamily: BwbTheme.fontFamily,
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: titleColor,
                        ),
                      ),

                      // ── Status badge ─────────────────────────────────────
                      if (isAttempted) ...[
                        const SizedBox(height: 5),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 9, vertical: 4),
                          decoration: BoxDecoration(
                            color: const Color(0xFFE5E7EB),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                                color: const Color(0xFFD1D5DB), width: 1),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.hourglass_top_rounded,
                                  size: 11, color: Color(0xFF6B7280)),
                              SizedBox(width: 5),
                              Text(
                                'Waiting for Answer Key...',
                                style: TextStyle(
                                  color: Color(0xFF6B7280),
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 0.2,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ] else if (isPosted) ...[
                        const SizedBox(height: 5),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 9, vertical: 4),
                          decoration: BoxDecoration(
                            color: const Color(0xFFD1FAE5),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                                color: const Color(0xFF6EE7B7), width: 1),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.menu_book_rounded,
                                  size: 11, color: Color(0xFF047857)),
                              SizedBox(width: 5),
                              Text(
                                'Answer Key Available',
                                style: TextStyle(
                                  color: Color(0xFF047857),
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 0.2,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],

                      if (widget.description.isNotEmpty) ...[
                        const SizedBox(height: 3),
                        Text(
                          widget.description,
                          style: TextStyle(
                            color: isAttempted
                                ? const Color(0xFFD1D5DB)
                                : BwbTheme.muted,
                            fontSize: 12,
                          ),
                        ),
                      ],
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        children: [
                          _Chip(
                            icon: Icons.topic_outlined,
                            label: '${widget.topicCount} Topics',
                            muted: isAttempted,
                          ),
                          _Chip(
                            icon: Icons.timer_outlined,
                            label: '${widget.mins} min',
                            muted: isAttempted,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Icon(
                  isAttempted
                      ? Icons.lock_outline_rounded
                      : Icons.arrow_forward_ios_rounded,
                  size: 16,
                  color: arrowColor,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool muted;
  const _Chip({required this.icon, required this.label, this.muted = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: muted ? const Color(0xFFE5E7EB) : const Color(0xFFEFF6FF),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11,
              color: muted ? const Color(0xFF9CA3AF) : BwbTheme.primary),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: muted ? const Color(0xFF9CA3AF) : BwbTheme.primary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
