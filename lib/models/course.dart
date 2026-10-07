/// 课程模型 —— 单门课程的一堂课（某一周次区间内的具体安排）
library;

/// 一门课程在某段时间内的一次具体安排。
class Course {
  /// 课程名称，如 "示例课程戊"
  final String name;

  /// 上课教师，如 "示例老师B"
  final String teacher;

  /// 上课地点，如 "明德楼A103"
  final String location;

  /// 星期几，1=周一 ... 7=周日
  final int dayOfWeek;

  /// 开始节次（1-11），如第3节
  final int startSection;

  /// 结束节次（1-11），如第4节
  final int endSection;

  /// 起始周（1-20）
  final int startWeek;

  /// 结束周（1-20）
  final int endWeek;

  /// 单双周类型：0=每周，1=单周，2=双周
  final int oddEven;

  /// 课程代码，如 "JC0247023-10"
  final String courseCode;

  /// 教学班组成，如 "演示26.7;演示26.8"
  final String className;

  const Course({
    required this.name,
    required this.teacher,
    required this.location,
    required this.dayOfWeek,
    required this.startSection,
    required this.endSection,
    required this.startWeek,
    required this.endWeek,
    this.oddEven = 0,
    this.courseCode = '',
    this.className = '',
  });

  /// 判断该课在指定周是否上课。
  bool isActiveOnWeek(int week) {
    if (week < startWeek || week > endWeek) return false;
    if (oddEven == 1 && week.isEven) return false; // 单周：偶数周不上
    if (oddEven == 2 && week.isOdd) return false; // 双周：奇数周不上
    return true;
  }

  /// 节次区间长度。
  int get sectionLength => endSection - startSection + 1;

  /// 周次文本，如 "7-18周" 或 "7-17周(单)"。
  String get weekText {
    final base = '$startWeek-$endWeek周';
    if (oddEven == 1) return '$base(单)';
    if (oddEven == 2) return '$base(双)';
    return base;
  }

  /// 节次文本，如 "3-4节"。
  String get sectionText => '$startSection-$endSection节';

  Map<String, dynamic> toJson() => {
        'name': name,
        'teacher': teacher,
        'location': location,
        'dayOfWeek': dayOfWeek,
        'startSection': startSection,
        'endSection': endSection,
        'startWeek': startWeek,
        'endWeek': endWeek,
        'oddEven': oddEven,
        'courseCode': courseCode,
        'className': className,
      };

  factory Course.fromJson(Map<String, dynamic> json) => Course(
        name: json['name'] as String? ?? '',
        teacher: json['teacher'] as String? ?? '',
        location: json['location'] as String? ?? '',
        dayOfWeek: json['dayOfWeek'] as int? ?? 1,
        startSection: json['startSection'] as int? ?? 1,
        endSection: json['endSection'] as int? ?? 2,
        startWeek: json['startWeek'] as int? ?? 1,
        endWeek: json['endWeek'] as int? ?? 20,
        oddEven: json['oddEven'] as int? ?? 0,
        courseCode: json['courseCode'] as String? ?? '',
        className: json['className'] as String? ?? '',
      );

  @override
  String toString() => '$name @${dayOfWeek == 0 ? 7 : dayOfWeek}周'
      '${['一', '二', '三', '四', '五', '六', '日'][dayOfWeek - 1]}'
      ' $sectionText $weekText $location $teacher';
}
