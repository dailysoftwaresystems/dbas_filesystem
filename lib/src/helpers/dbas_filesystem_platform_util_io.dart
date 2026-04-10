import 'dart:io';

final bool _isTest = Platform.environment.containsKey('FLUTTER_TEST');

bool isTestEnvironment() => _isTest;
