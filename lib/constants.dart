import 'package:flutter/foundation.dart';

/// Base URL for the backend API.
/// Override at build time: --dart-define=API_BASE=http://your-host:8000
const String kApiBase = String.fromEnvironment(
  'API_BASE',
  defaultValue: _defaultApiBase,
);

const String _defaultApiBase = kIsWeb
    ? 'https://online-assessment-admin-pink.vercel.app'
    : 'https://online-assessment-admin-pink.vercel.app';
