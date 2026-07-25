import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'state/quiz_state.dart';
import 'state/attempt_state.dart';
import 'theme.dart';
import 'screens/home_screen.dart';
import 'screens/topic_select_screen.dart';
import 'screens/quiz_screen.dart';
import 'screens/coding_screen.dart';
import 'screens/result_screen.dart';
import 'screens/answers_screen.dart';

class OnlineAssessmentApp extends StatelessWidget {
  const OnlineAssessmentApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => QuizState()),
        ChangeNotifierProvider(create: (_) => AttemptState()),
      ],
      child: MaterialApp(
        title: 'Online Assessment',
        debugShowCheckedModeBanner: false,
        theme: BwbTheme.light(),
        initialRoute: '/',
        routes: {
          '/': (_) => const HomeScreen(),
          '/topics': (_) => const TopicSelectScreen(),
          '/quiz': (_) => const QuizScreen(),
          '/coding': (_) => const CodingScreen(),
          '/result': (_) => const ResultScreen(),
          '/answers': (ctx) {
            final args = ModalRoute.of(ctx)!.settings.arguments as Map<String, String>;
            return AnswersScreen(quizId: args['quizId']!, quizTitle: args['quizTitle']!);
          },
        },
      ),
    );
  }
}
