/// 课程卡片控件 —— 课表网格中的单个课程块。
///
/// 卡片高度由「跨了几节」决定，宽度由「同一格有几门冲突课」决定，
/// 因此这里用 [LayoutBuilder] 按实际可用空间**自适应**内容：
/// 太矮就只留课名、太窄就换小字号，避免出现黄黑条（overflow）。
library;

import 'package:flutter/material.dart';
import '../models/course.dart';

/// 单个课程卡片。
class CourseCard extends StatelessWidget {
  final Course course;
  final Color color;
  final VoidCallback? onTap;

  const CourseCard({
    super.key,
    required this.course,
    required this.color,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: LayoutBuilder(
        builder: (context, box) {
          final w = box.maxWidth;
          final h = box.maxHeight;
          final narrow = w < 74;
          final roomy = h >= 60 && w >= 74;
          final showLocation = h >= 40;
          final showTeacher = h >= 84 && w >= 96;

          return Container(
            margin: const EdgeInsets.all(2),
            padding: EdgeInsets.symmetric(
              horizontal: narrow ? 4 : 8,
              vertical: h >= 60 ? 6 : 4,
            ),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [color, color.withValues(alpha: 0.75)],
              ),
              borderRadius: BorderRadius.circular(roomy ? 12 : 9),
              boxShadow: roomy
                  ? [
                      BoxShadow(
                        color: color.withValues(alpha: 0.3),
                        blurRadius: 8,
                        offset: const Offset(0, 3),
                      ),
                    ]
                  : null,
            ),
            child: ClipRect(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    course.name,
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: narrow ? 10 : 12,
                      height: 1.15,
                    ),
                    maxLines: roomy ? 3 : 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (showLocation) ...[
                    const SizedBox(height: 2),
                    Text(
                      course.location,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.85),
                        fontSize: narrow ? 8.5 : 10,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                  if (showTeacher) ...[
                    const SizedBox(height: 1),
                    Text(
                      course.teacher,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.75),
                        fontSize: 9.5,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

/// 课表左上角的小角标（单/双周、冲突提醒等）。
class CourseBadge extends StatelessWidget {
  final String text;
  final Color color;

  const CourseBadge({super.key, required this.text, required this.color});

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.92),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          text,
          style: TextStyle(
            fontSize: 8.5,
            fontWeight: FontWeight.bold,
            color: color,
            height: 1.1,
          ),
        ),
      ),
    );
  }
}
