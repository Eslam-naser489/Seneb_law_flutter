import 'package:drift/drift.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:drift/native.dart';
import 'package:seneb_law/core/database/database.dart';
import 'package:seneb_law/core/database/app_repository.dart';
import 'package:seneb_law/main.dart';

void main() {
  testWidgets('App builds and runs smoke test', (WidgetTester tester) async {
    // 1. الداتابيز الوهمية
    final db = AppDatabase.forTesting(DatabaseConnection(NativeDatabase.memory()));
    final repository = AppRepository(db);

    // 2. تشغيل التطبيق
    await tester.pumpWidget(SenebLawApp(repository: repository));

    // التأكد من بناء الـ MaterialApp
    expect(find.byType(MaterialApp), findsOneWidget);

    // 3. تسريع الزمن 5 ثواني لاجتياز شاشة البداية (Splash Screen Timer)
    await tester.pump(const Duration(seconds: 5));
    
    // الانتظار حتى استقرار الشاشة الجديدة (شاشة الأجندة)
    await tester.pumpAndSettle();

    // 4. إغلاق الداتابيز
    await db.close();
  });
}