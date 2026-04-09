import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:dbas_filesystem/dbas_filesystem.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('DbasFileSystem can be initialized', (WidgetTester tester) async {
    final fs = await DbasFileSystem.getInstance();
    expect(fs, isNotNull);
  });
}
