// 演示数据入口：先往本地存储灌一份**全部虚构**的演示课表，再进真正的首页。
//
// 用途只有一个：**在模拟器上生成 README 的界面截图**。仓库里不许出现真机截图
// （真机上装的是作者本人的真实课表，课程名 / 教师 / 教室都是个人信息），
// 所以截图一律用这个入口灌好虚构数据后再截。
//
// 跑法：
//   1) flutter run -t lib/dev/demo_seed.dart -d emulator-5554
//   2) 需要「发布版长相」的截图时（其实 debug 版也只多一条横幅、本项目已关掉）：
//      adb install -r dist/内师课程表-<版本>-x86_64.apk   # 同签名覆盖安装，数据保留
//
// 注意：这里只写死通用课名 + 「示例老师A~J」+ 明德楼A101 这类虚构地点，
// **不要**把任何真实课表内容粘进来。
library;

import 'package:flutter/material.dart';

import '../app_state.dart';
import '../main.dart' as app;
import '../models/course.dart';
import '../models/timetable.dart';

/// 演示课程：课名都是通用课名，教师 / 教室全部虚构（示例老师 / 明德楼A101 之类）。
const List<Course> _demoCourses = [
  Course(
    name: '高等数学',
    teacher: '示例老师A',
    location: '明德楼A101',
    dayOfWeek: 1,
    startSection: 1,
    endSection: 2,
    startWeek: 1,
    endWeek: 18,
  ),
  Course(
    name: '大学英语',
    teacher: '示例老师B',
    location: '明德楼B203',
    dayOfWeek: 1,
    startSection: 3,
    endSection: 4,
    startWeek: 1,
    endWeek: 18,
  ),
  Course(
    name: '程序设计基础',
    teacher: '示例老师C',
    location: '格致楼205',
    dayOfWeek: 2,
    startSection: 1,
    endSection: 4,
    startWeek: 1,
    endWeek: 18,
  ),
  Course(
    name: '大学物理',
    teacher: '示例老师D',
    location: '明德楼B314',
    dayOfWeek: 2,
    startSection: 5,
    endSection: 6,
    startWeek: 1,
    endWeek: 18,
  ),
  Course(
    name: '体育',
    teacher: '示例老师E',
    location: '田径场',
    dayOfWeek: 3,
    startSection: 3,
    endSection: 4,
    startWeek: 1,
    endWeek: 18,
  ),
  Course(
    name: '中国近现代史纲要',
    teacher: '示例老师F',
    location: '明德楼A203',
    dayOfWeek: 3,
    startSection: 7,
    endSection: 8,
    startWeek: 1,
    endWeek: 18,
  ),
  Course(
    name: '数据结构',
    teacher: '示例老师G',
    location: '格致楼113',
    dayOfWeek: 4,
    startSection: 1,
    endSection: 2,
    startWeek: 1,
    endWeek: 9,
  ),
  Course(
    name: '数据结构',
    teacher: '示例老师G',
    location: '格致楼113',
    dayOfWeek: 4,
    startSection: 1,
    endSection: 2,
    startWeek: 10,
    endWeek: 18,
  ),
  Course(
    name: '电路分析',
    teacher: '示例老师H',
    location: '实验楼301',
    dayOfWeek: 4,
    startSection: 5,
    endSection: 6,
    startWeek: 1,
    endWeek: 18,
  ),
  Course(
    name: '形势与政策',
    teacher: '示例老师I',
    location: '培训中心',
    dayOfWeek: 5,
    startSection: 1,
    endSection: 2,
    startWeek: 1,
    endWeek: 8,
  ),
  Course(
    name: '大学物理实验',
    teacher: '示例老师D',
    location: '实验楼202',
    dayOfWeek: 5,
    startSection: 3,
    endSection: 4,
    startWeek: 9,
    endWeek: 18,
  ),
  Course(
    name: '线性代数',
    teacher: '示例老师J',
    location: '明德楼A105',
    dayOfWeek: 6,
    startSection: 1,
    endSection: 2,
    startWeek: 1,
    endWeek: 9,
  ),
];

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final state = AppState();
  await state.init();

  // 清掉设备上已有的课表，保证截图里只有演示数据。
  for (final t in [...state.timetables]) {
    await state.removeTimetable(t.id);
  }

  await state.addTimetable(
    Timetable(
      id: 'demo-timetable',
      name: '演示课表',
      semester: '2026-2027年第1学期',
      major: '演示专业',
      totalWeeks: 22,
      startDate: DateTime(2026, 8, 31),
      courses: _demoCourses,
    ),
  );

  // 顺手把法定节假日换成联网拿到的国家公布安排（失败也无所谓，保持内置估算值）。
  await state.syncHolidaysFromNetwork();

  debugPrint('DEMO SEED OK courses=${state.active?.courses.length} '
      'week=${state.currentWeek} holidays=${state.holidays.holidays.length} '
      'ranges=${state.holidays.holidayRanges.length}');

  app.main();
}
