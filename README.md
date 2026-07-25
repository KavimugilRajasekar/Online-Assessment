# 📝 Online Assessment

> A cross-platform, **lockdown-secured** online assessment application built with Flutter. Candidates take timed quizzes (MCQ + coding), answers sync through an offline-tolerant queue, and anti-cheat proctoring auto-submits on repeated violations.

The app is one half of a two-tier system: a **Django REST backend** (the "admin" side, hosted on Vercel) serves quizzes, attempts, and answer keys, and this **Flutter client** is the candidate-facing front-end. It supports **Android, iOS, Web, and Windows** from a single Dart codebase.

---

## ✨ Highlights

- 🎯 **Live quiz list** with background polling for newly published assessments
- 📚 **Topic browser** with per-topic question counts and difficulty visibility
- ⏱ **Server-anchored countdown timer** with auto-submit at deadline
- 🔒 **Anti-cheat proctoring** — fullscreen lockdown, lifecycle hooks, and 3-strike violation policy
- 📡 **Offline-tolerant answer queue** with exponential-backoff retry and connectivity banner
- 💻 **In-app code editor** for coding questions (manual review)
- 🧾 **Downloadable answer-key PDF** (published quizzes) with correct/incorrect highlights and explanations
- 📊 **Detailed result review** with score arc, per-question verdict, marks awarded, and explanations
- 🪪 **Flag-for-review** system with marker chips in the pager
- 🌗 **Custom theme** built on `BwbTheme` (Comfortaa typography, blue/emerald palette)
- ✨ **Lottie-animated** screens (cat cloud, error shake, present celebration, searching indicator)

---

## 🧰 Tech Stack

| Layer            | Choice                                                   |
|------------------|----------------------------------------------------------|
| Framework        | **Flutter** (Dart SDK `^3.12.1`), `Material 3`           |
| State management | **Provider** (`ChangeNotifier`)                          |
| HTTP             | `http ^1.2.2` (with custom `ApiClient` + cookie jar)     |
| Persistence      | `shared_preferences ^2.2.3`                              |
| Animations       | `lottie ^3.5.1`                                          |
| PDF export       | `pdf ^3.11.1` + `printing ^5.13.1`                       |
| IDs              | `uuid ^4.4.0`                                            |
| Icons (iOS)      | `cupertino_icons ^1.0.8`                                 |
| Lints            | `flutter_lints ^6.0.0`                                   |
| Icons generation | `flutter_launcher_icons ^0.14.4`                         |

### Fonts (bundled)
- **Comfortaa** — primary UI font
- **Playwrite US Modern** — accent / display font

---

## 📂 Directory Structure

```
online_assessment/
├── android/                  # Android platform shell (Kotlin MainActivity, manifest, icons)
├── ios/                      # iOS platform shell (Runner.xcodeproj, AppDelegate, SceneDelegate)
├── web/                      # Web platform shell (index.html, manifest.json, icons)
├── windows/                  # Windows platform shell (CMakeLists, runner, flutter_window.cpp)
├── build/                    # Generated build artifacts (gitignored)
│
├── assets/
│   ├── icons/
│   │   └── online_assessment_logo.png
│   ├── json/                 # Lottie animations
│   │   ├── cat_cloud.json    # Decorative header animation
│   │   ├── error.json        # Shake-animated warning icon
│   │   ├── present.json      # Result-screen celebration
│   │   └── searching.json    # Loading indicator
│   └── fonts/
│       ├── Comfortaa/        # Variable + static weights
│       └── Playwrite_US_Modern/
│
├── lib/
│   ├── main.dart             # App entry: locks to portrait, runs OnlineAssessmentApp
│   ├── app.dart              # MaterialApp + MultiProvider (QuizState, AttemptState) + named routes
│   ├── constants.dart        # kApiBase — overridable via --dart-define=API_BASE=...
│   ├── theme.dart            # BwbTheme: color palette, Material 3 ThemeData, fonts
│   │
│   ├── models/               # Plain Dart data classes (fromJson-only)
│   │   ├── quiz.dart             # Quiz, duration, shuffle, topicCount, answersPosted
│   │   ├── topic.dart            # Topic → subtopics[]
│   │   ├── subtopic.dart         # Subtopic
│   │   ├── question.dart         # Question (mcqSingle, mcqMulti, codeMcq, coding)
│   │   ├── choice.dart           # Choice (id, text, optional isCorrect)
│   │   ├── answer.dart           # Answer (selectedChoiceIds + codeText + isCorrect + marks)
│   │   ├── attempt.dart          # Attempt + AttemptStatus enum (in_progress / submitted / expired)
│   │   └── result.dart           # QuizResult + AnswerResult
│   │
│   ├── services/             # Singletons — networking, persistence, anti-cheat
│   │   ├── api_client.dart       # ApiClient — persistent cookie jar, JSON, ApiException
│   │   ├── quiz_service.dart     # listQuizzes(), getTopics(quizId)
│   │   ├── attempt_service.dart  # start/resume/get attempt, upsertAnswer, submit, getResult
│   │   ├── attempt_store.dart    # SharedPreferences-backed attempt resume (per quiz)
│   │   └── lockdown_service.dart # SystemChrome immersive + lifecycle hooks
│   │
│   ├── state/                # ChangeNotifier providers
│   │   ├── quiz_state.dart       # List of quizzes, topics, load state, selected quiz
│   │   └── attempt_state.dart    # Active attempt, answers, queue, timer, violations
│   │
│   ├── screens/              # Top-level pages
│   │   ├── home_screen.dart          # Quiz list w/ polling
│   │   ├── topic_select_screen.dart   # Candidate form + instructions + topic summary
│   │   ├── quiz_screen.dart          # Active quiz, PageView, topic tabs, review screen
│   │   ├── coding_screen.dart        # Full-screen code editor with debounced autosave
│   │   ├── result_screen.dart        # Score arc + per-question review
│   │   └── answers_screen.dart       # Published answer key with PDF export
│   │
│   └── widgets/              # Reusable UI primitives
│       ├── bwb_button.dart           # Themed ElevatedButton / OutlinedButton
│       ├── bwb_card.dart             # Bordered surface card with optional onTap
│       ├── choice_tile.dart          # MCQ choice with selected / correct / wrong states
│       ├── code_block_view.dart      # Read-only monospaced code block
│       ├── code_editor_field.dart    # Editable monospaced TextField
│       ├── question_card.dart        # Single question (MCQ or coding entry)
│       ├── timer_bar.dart            # Linear progress + mm:ss countdown
│       └── lockdown_overlay.dart     # Animated violation dialog (shake + pulse + 10s lockout)
│
├── test/
│   ├── widget_test.dart         # Smoke test
│   ├── markup_test.dart         # CodeBlockView renders with monospace
│   ├── quiz_state_test.dart     # AttemptState offline queue
│   └── lockdown_test.dart       # Violation counter + auto-submit threshold
│
├── build_releases.bat       # One-shot cross-platform build script (Win-friendly)
├── pubspec.yaml             # Manifest (deps, fonts, assets, app icons)
├── pubspec.lock             # Locked dependency versions
├── analysis_options.yaml    # Lint rules (flutter_lints)
├── online_assessment.iml    # IntelliJ module file
└── README.md                # You are here
```

---

## 🚀 Getting Started

### Prerequisites
- **Flutter SDK** (Dart `^3.12.1`) — install from [flutter.dev](https://docs.flutter.dev/get-started/install)
- Platform toolchains as needed:
  - **Android**: Android Studio + Android SDK
  - **iOS**: macOS with Xcode
  - **Windows**: Visual Studio 2022 with “Desktop development with C++”
  - **Web**: nothing extra (Chrome recommended)

### Install
```bash
flutter pub get
```

### Run (development)
```bash
# Pick a device first
flutter devices

# Launch
flutter run -d chrome              # web
flutter run -d <android-device-id> # android
flutter run -d windows             # windows desktop
```

### Configure the API base
The client reads `kApiBase` from `lib/constants.dart` with a `String.fromEnvironment` override:

```bash
flutter run --dart-define=API_BASE=https://staging.example.com
```

Default backend is `https://online-assessment-admin-pink.vercel.app`.

---

## 🏗️ Building Releases

The repo ships with **`build_releases.bat`**, a Windows-friendly cross-platform build script that:

1. `flutter clean`
2. `flutter pub get`
3. `flutter build apk --release --split-per-abi` + `flutter build appbundle --release`
4. `flutter build ios --release` *(skipped on Windows)*
5. `flutter build web --release`
6. `flutter build windows --release`

Output locations printed by the script:
- Android APKs: `build/app/outputs/flutter-apk/`
- Android AAB: `build/app/outputs/bundle/release/`
- Web: `build/web/`
- Windows: `build/windows/runner/Release/`
- iOS: `build/ios/iphoneos/`

Update `FLUTTER_PATH` at the top of the script to match your local install.

You can also run any individual target by hand:

```bash
flutter build apk --release --split-per-abi
flutter build appbundle --release
flutter build web --release
flutter build windows --release
flutter build ios --release    # macOS only
```

---

## 🧭 App Flow

```
┌──────────────┐    ┌────────────────────┐    ┌──────────────┐
│  HomeScreen  │───▶│  TopicSelectScreen │───▶│  QuizScreen  │
│ quiz list +  │    │  candidate form +  │    │ PageView +   │
│  3s polling  │    │  instructions +    │    │ topic tabs + │
└──────────────┘    │  topic summary     │    │ review gate  │
       │            └────────────────────┘    └──────┬───────┘
       │                                             │
       │ answersPosted=true                          │ submit
       ▼                                             ▼
┌──────────────┐                              ┌──────────────┐
│AnswersScreen │                              │ResultScreen  │
│answer key +  │                              │ score arc +  │
│  PDF export  │                              │ per-Q review │
└──────────────┘                              └──────────────┘
```

`coding_screen.dart` is pushed from `question_card.dart` whenever the active question is a `QuestionType.coding`; it returns to the quiz with the typed solution saved.

---

## 🔌 Backend Contract

The client is REST-only and relies on the Django backend (admin app) for everything. All requests go through `ApiClient`, which:

- Persists Django session cookies across calls (a tiny in-memory jar rebuilt from `Set-Cookie`).
- Sends `Content-Type: application/json` and includes the latest `Cookie` header automatically.
- Throws `ApiException(statusCode, message, body)` on non-2xx responses (with parsed `detail` when present).

### Endpoints used

| Method | Path                                          | Purpose                                                |
|--------|-----------------------------------------------|--------------------------------------------------------|
| GET    | `/api/quizzes/`                               | List active quizzes (with `answersPosted` flag)        |
| GET    | `/api/quizzes/{quizId}/topics/`               | Topics + subtopic + question counts for a quiz         |
| POST   | `/api/quizzes/{quizId}/attempts/`             | Start a new attempt (returns `409` if one exists)      |
| GET    | `/api/attempts/{attemptId}/`                  | Fetch attempt detail (resume)                          |
| POST   | `/api/attempts/{attemptId}/answers/`          | Upsert an MCQ choice or code answer                    |
| POST   | `/api/attempts/{attemptId}/submit/`           | Submit attempt, returns a `QuizResult` (or 204)        |
| GET    | `/api/attempts/{attemptId}/result/`           | Fetch the `QuizResult` for a submitted attempt        |
| GET    | `/api/quizzes/{quizId}/answers/`              | Fetch the published answer key for a quiz              |

The submit endpoint is intentionally permissive — `AttemptService._parseResult` accepts the result directly, wrapped under `result` / `attempt` / `data`, or as a 204 with a follow-up `getResult()`.

---

## 🛡️ Anti-Cheat / Lockdown

`LockdownService` (singleton) runs whenever `QuizScreen` is mounted:

1. **Mobile & Desktop** — `SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky, overlays: [])` hides the status bar and quick-access panel, and forces portrait orientation.
2. **Web** — conditional hooks (`_setupWebListeners`) are no-op stubs on non-web builds and can be extended with fullscreen / `visibilitychange` listeners.
3. **App lifecycle** — `handleLifecycleState` flags any transition to `inactive`, `paused`, or `hidden` as a violation.
4. **PopScope** — the quiz screen cannot be dismissed by the OS back gesture; the device back is intercepted.

### Violation policy
- **3 strikes = auto-submit.** `AttemptState.recordViolation(reason)` increments `violationCount` and **deducts 1/6 of remaining time** (or a 30 s floor). On the third strike the attempt is auto-submitted.
- A non-dismissible `LockdownOverlayDialog` is shown with a **shaking Lottie warning icon**, a pulsing red glow, the violation reason, and a **10-second lockout** before the user can dismiss and resume.
- `LockdownService.disableLockdown()` restores the system UI when leaving the quiz.

---

## 🧠 State Management

Two `ChangeNotifier`s are provided at the app root via `MultiProvider`:

### `QuizState`
- `quizzes`, `topics`, `selectedQuiz`, `loadState`, `errorMessage`
- `loadQuizzes({silent})` — silent polls every 3 s on `HomeScreen`
- `loadTopics(quizId)`, `selectQuiz(quiz)`

### `AttemptState`
- Active `attempt`, `result`, `submitState`, `connectivityState`
- `currentQuestionIndex`, `selectedChoices: Map<questionId, choiceIds>`, `codeAnswers: Map<questionId, code>`, `flaggedQuestions: Set<questionId>`
- **Timer**: anchored to `attempt.deadlineDateTime`, ticks every 1 s, auto-submits on expiry.
- **Answer queue**: every selection/code save is enqueued; the queue flushes in-order with **exponential backoff** (1 s → 30 s cap). On failure the connectivity state flips to `offline` and a red banner appears at the top of `QuizScreen`.
- **Submit flow**: flushes queue → POSTs `/submit/` → clears `AttemptStore` → cancels timers → routes to `/result`.
- **Proctoring**: `violationCount`, `lastViolationReason`, `maxViolations = 3`, auto-submit on threshold.

Attempt resumption is persisted via `AttemptStore` (SharedPreferences keys `oa_attempt_id`, `oa_quiz_id`).

---

## 🎨 Theming

`BwbTheme.light()` provides:

- **Primary** `Color(0xFF2563EB)` (Modern Blue) with variant `#1D4ED8`
- **Secondary** `Color(0xFF10B981)` (Emerald) for success
- **Error** `Color(0xFFEF4444)`, **Unanswered** `Color(0xFF94A3B8)`, **Correct** `Color(0xFF10B981)`
- **Background** `Color(0xFFF8FAFC)` (Slate 50)
- **Text** `Color(0xFF0F172A)` (Slate 900) / Muted `Color(0xFF64748B)` (Slate 500)
- **Fonts** Comfortaa (UI) and Playwrite US Modern (display)
- Rounded corners, 1px slate borders, white surfaces, Material 3 `ColorScheme.fromSeed`

All gradient headers across screens use `[#1e3a8a → #2563EB]` for hero blocks and a per-screen semantic gradient (green for the answer key, score color for results).

---

## 🧪 Testing

```bash
flutter test
```

The repo ships with four test files under `test/`:

| File                  | What it covers                                                 |
|-----------------------|----------------------------------------------------------------|
| `widget_test.dart`    | Smoke test — app renders without crashing                       |
| `markup_test.dart`    | `CodeBlockView` renders code in monospace                      |
| `quiz_state_test.dart`| `AttemptState.isSubmitBlocked` defaults to false               |
| `lockdown_test.dart`  | Violation counter increments, threshold = 3, auto-submit hint  |

---

## 🧱 Platform Notes

- **Android** — `android:label="OA"`, `INTERNET` permission declared in `android/app/src/main/AndroidManifest.xml`. The launcher icon is generated from `assets/icons/online_assessment_logo.png` via `flutter_launcher_icons`.
- **iOS** — standard `Runner.xcodeproj` shell; portrait-locked by `SystemChrome` at runtime.
- **Web** — `web/index.html` with `mobile-web-app-capable`, `apple-touch-icon`, and `manifest.json` linking the bundled PWA icons (`192`, `512`, `maskable-192`, `maskable-512`).
- **Windows** — `windows/runner/CMakeLists.txt` + `flutter_window.cpp` from the standard Flutter template.

The app **forces portrait orientation** in `main.dart` regardless of platform.

---

## 📦 Data Model Cheat-Sheet

```
Quiz
├── id, title, description
├── durationSeconds, shuffleQuestions, shuffleChoices
├── topicCount, answersPosted
└── (lazy) topics → Topic[]

Topic
├── id, name
├── questionCount
└── subtopics → Subtopic[]

Question
├── id, qtype ∈ {mcqSingle, mcqMulti, codeMcq, coding, unknown}
├── text, code, marks, explanation
├── choices → Choice[]   (Choice.isCorrect is null in public view)
├── starterCode, language
└── topicId, topicName

Attempt
├── id, quizId, status ∈ {in_progress, submitted, expired}
├── startedAt, deadlineAt (UTC strings, tolerant parser)
├── totalMarks
├── questionOrder → id[]
└── questions → Question[]

Answer
├── questionId
├── selectedChoiceIds → String[]
├── codeText
├── isCorrect? (server-side, null for coding)
└── marksAwarded

QuizResult
├── id, quizId, status, totalMarks, score, submittedAt
└── answers → AnswerResult[] { question, answer }
```

---

## 📑 License & Credits

- **Comfortaa** font — Google Fonts (OFL).
- **Playwrite US Modern** font — Google Fonts (OFL).
- **Lottie** animations bundled in `assets/json/`.
- This is a private assessment tool — the `publish_to: 'none'` line in `pubspec.yaml` keeps it off pub.dev.
