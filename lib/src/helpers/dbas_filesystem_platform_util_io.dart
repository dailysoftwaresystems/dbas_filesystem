import 'dart:io';

bool isTestEnvironment() => Platform.environment.containsKey('FLUTTER_TEST');
