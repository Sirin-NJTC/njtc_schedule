/// 课表模型 —— 一份完整的课表（含学期信息与全部课程）
library;

import 'dart:convert';
import 'course.dart';

/// 一份完整课表。
class Timetable {
  /// 课表唯一标识（时间戳）
  final String id;

  /// 课表名称（用户自定义，如 "2026-2027学年第一学期"）
  String name;

  /// 学期，如 "2026-2027年第1学期"
  String semester;

  /// 专业，如 "示例工程"
  String major;

  /// 总周数
  int totalWeeks;

  /// 学期起始日期（用于计算当前是第几周）
  DateTime? startDate;

  /// 全部课程
  List<Course> courses;

  /// 创建时间
  final DateTime createdAt;

  /// 是否为当前激活课表
  bool isActive;

  Timetable({
    required this.id,
    required this.name,
    this.semester = '',
    this.major = '',
    this.totalWeeks = 20,
    this.startDate,
    List<Course>? courses,
    DateTime? createdAt,
    this.isActive = false,
  })  : courses = courses ?? [],
        createdAt = createdAt ?? DateTime.now();

  /// 按星期分组，返回 Map<星期(1-7), List<Course>>。
  Map<int, List<Course>> byDay() {
    final map = <int, List<Course>>{};
    for (var d = 1; d <= 7; d++) {
      map[d] = [];
    }
    for (final c in courses) {
      map[c.dayOfWeek]?.add(c);
    }
    // 每天内按节次排序
    for (final d in map.keys) {
      map[d]!.sort((a, b) => a.startSection.compareTo(b.startSection));
    }
    return map;
  }

  /// 获取指定星期、指定周的所有课程（按节次排序）。
  List<Course> coursesOn(int day, int week) {
    return courses
        .where((c) => c.dayOfWeek == day && c.isActiveOnWeek(week))
        .toList()
      ..sort((a, b) => a.startSection.compareTo(b.startSection));
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'semester': semester,
        'major': major,
        'totalWeeks': totalWeeks,
        'startDate': startDate?.toIso8601String(),
        'courses': courses.map((c) => c.toJson()).toList(),
        'createdAt': createdAt.toIso8601String(),
        'isActive': isActive,
      };

  factory Timetable.fromJson(Map<String, dynamic> json) => Timetable(
        id: json['id'] as String? ?? '',
        name: json['name'] as String? ?? '',
        semester: json['semester'] as String? ?? '',
        major: json['major'] as String? ?? '',
        totalWeeks: json['totalWeeks'] as int? ?? 20,
        startDate: json['startDate'] != null
            ? DateTime.tryParse(json['startDate'] as String)
            : null,
        courses: (json['courses'] as List? ?? [])
            .map((e) => Course.fromJson(e as Map<String, dynamic>))
            .toList(),
        createdAt: json['createdAt'] != null
            ? DateTime.tryParse(json['createdAt'] as String) ?? DateTime.now()
            : DateTime.now(),
        isActive: json['isActive'] as bool? ?? false,
      );

  String toJsonString() => jsonEncode(toJson());

  factory Timetable.fromJsonString(String s) =>
      Timetable.fromJson(jsonDecode(s) as Map<String, dynamic>);
}
