class DbasPathValidator {
  static void validate(String path) {
    if (path.isEmpty) {
      throw ArgumentError.value(path, 'path', 'Path must not be empty.');
    }
    if (path.trim().isEmpty) {
      throw ArgumentError.value(path, 'path', 'Path must not be blank.');
    }
    if (path.contains('\x00')) {
      throw ArgumentError.value(path, 'path', 'Path must not contain null bytes.');
    }
  }

  static void validateAll(List<String> paths) {
    for (final path in paths) {
      validate(path);
    }
  }
}
