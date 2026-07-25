import 'dart:async';
import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';
import 'package:provider/provider.dart';
import '../state/quiz_state.dart';
import '../theme.dart';
import '../widgets/bwb_button.dart';
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
                                child: Image.asset(
                                  'assets/icons/online_assessment_logo.png',
                                  height: 32,
                                  width: 32,
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
          BwbCard(
            borderColor: BwbTheme.wrong,
            child: Column(
              children: [
                const Icon(
                  Icons.wifi_off_rounded,
                  color: BwbTheme.wrong,
                  size: 28,
                ),
                const SizedBox(height: 8),
                Text(
                  'Could not load quizzes.\n${quizState.errorMessage}',
                  style: const TextStyle(color: BwbTheme.wrong, fontSize: 13),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                BwbButton(
                  label: 'Retry',
                  onPressed: () => context.read<QuizState>().loadQuizzes(),
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
            return _QuizCard(
              index: i,
              title: quiz.title,
              description: quiz.description,
              topicCount: quiz.topicCount,
              mins: mins,
              answersPosted: quiz.answersPosted,
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
  final VoidCallback onTap;

  const _QuizCard({
    required this.index,
    required this.title,
    required this.description,
    required this.topicCount,
    required this.mins,
    required this.answersPosted,
    required this.onTap,
  });

  @override
  State<_QuizCard> createState() => _QuizCardState();
}

class _QuizCardState extends State<_QuizCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final isPosted = widget.answersPosted;
    final cardBg = isPosted ? const Color(0xFFECFDF5) : Colors.white;
    final borderSide = isPosted
        ? Border.all(color: const Color(0xFFa7f3d0), width: 1.5)
        : null;
    final iconGradient = isPosted
        ? const LinearGradient(colors: [Color(0xFF059669), Color(0xFF10B981)])
        : const LinearGradient(colors: [Color(0xFF2563EB), Color(0xFF1D4ED8)]);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: borderSide,
        boxShadow: [
          BoxShadow(
            color: (isPosted ? const Color(0xFF10B981) : BwbTheme.primary)
                .withValues(alpha: _hovered ? 0.18 : 0.06),
            blurRadius: _hovered ? 18 : 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: cardBg,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: widget.onTap,
          onHover: (v) => setState(() => _hovered = v),
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Row(
              children: [
                // Index badge
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    gradient: iconGradient,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Center(
                    child: Icon(
                      isPosted ? Icons.menu_book_rounded : Icons.quiz_rounded,
                      color: Colors.white,
                      size: 24,
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Title
                      Text(
                        widget.title,
                        style: const TextStyle(
                          fontFamily: BwbTheme.fontFamily,
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: BwbTheme.text,
                        ),
                      ),
                      // "Answer Key Available" badge — directly below title
                      if (isPosted) ...[
                        const SizedBox(height: 5),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 9,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFD1FAE5),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: const Color(0xFF6EE7B7),
                              width: 1,
                            ),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.menu_book_rounded,
                                size: 11,
                                color: Color(0xFF047857),
                              ),
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
                          style: const TextStyle(
                            color: BwbTheme.muted,
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
                          ),
                          _Chip(
                            icon: Icons.timer_outlined,
                            label: '${widget.mins} min',
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Icon(
                  Icons.arrow_forward_ios_rounded,
                  size: 16,
                  color: isPosted ? const Color(0xFF059669) : BwbTheme.primary,
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
  const _Chip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: const Color(0xFFEFF6FF),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: BwbTheme.primary),
          const SizedBox(width: 4),
          Text(
            label,
            style: const TextStyle(
              fontSize: 11,
              color: BwbTheme.primary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
