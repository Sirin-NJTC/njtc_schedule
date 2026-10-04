/// 应用入口。
library;

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';
import 'app_state.dart';
import 'pages/home_page.dart';
import 'pages/holiday_settings_page.dart';
import 'pages/import_page.dart';
import 'pages/period_settings_page.dart';
import 'pages/reminder_settings_page.dart';
import 'pages/timetables_page.dart';
import 'pages/settings_page.dart';
import 'theme.dart';

void main() {
  runApp(const NjtcScheduleApp());
}

class NjtcScheduleApp extends StatelessWidget {
  const NjtcScheduleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => AppState()..init(),
      child: MaterialApp(
        title: '内江师范学院课程表',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.lightTheme,
        // 让 showDatePicker / showTimePicker 这些系统弹窗也用中文
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        supportedLocales: const [Locale('zh', 'CN'), Locale('en')],
        home: const HomePage(),
        routes: {
          '/import': (_) => const ImportPage(),
          '/timetables': (_) => const TimetablesPage(),
          '/settings': (_) => const SettingsPage(),
          '/reminders': (_) => const ReminderSettingsPage(),
          '/periods': (_) => const PeriodSettingsPage(),
          '/holidays': (_) => const HolidaySettingsPage(),
        },
      ),
    );
  }
}
