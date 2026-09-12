import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:notes_app/main.dart';

void main() {
  testWidgets('Notes app loads its main screen', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(const NotesApp());
    await tester.pump();

    expect(find.text('ملاحظاتي'), findsOneWidget);
    expect(find.text('ملاحظة جديدة'), findsOneWidget);
  });
}
