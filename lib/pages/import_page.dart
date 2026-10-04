/// 导入页 —— 三种导入方式：网页登录导入 / 文件导入 / 粘贴解析。
///
/// 「网页登录导入」是首选：在应用内弹出真正的 WebView 让用户自己登录教务系统
/// （登录带滑块验证码，无法用代码代劳），进入课表页后点「读取课表」即可。
library;

import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import 'package:excel/excel.dart';
import '../app_state.dart';
import '../models/timetable.dart';
import '../services/timetable_parser.dart';
import '../services/xls_reader.dart';
import '../services/jwxt_service.dart';
import '../theme.dart';

/// 导入课程表页面。
class ImportPage extends StatefulWidget {
  const ImportPage({super.key});

  @override
  State<ImportPage> createState() => _ImportPageState();
}

class _ImportPageState extends State<ImportPage> {
  final _textController = TextEditingController();
  bool _loading = false;
  String _loadingText = '正在解析课表…';

  /// 上次成功抓到课表的页面地址（原生侧记住的），用于给用户一个「继续上次」的入口。
  String? _lastUrl;

  @override
  void initState() {
    super.initState();
    JwxtService.lastUrl().then((url) {
      if (mounted && url != null && url.isNotEmpty) {
        setState(() => _lastUrl = url);
      }
    });
  }

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('导入课程表')),
      body: Stack(
        children: [
          SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildMethodCard(
                  icon: Icons.language_rounded,
                  title: '登录教务系统网页导入',
                  subtitle: _lastUrl == null
                      ? '推荐：在应用内登录教务系统，进入课表页后点「读取课表」'
                      : '推荐：继续从上次的课表页读取',
                  onTap: _webImport,
                  color: AppTheme.primary,
                ),
                const SizedBox(height: 12),
                _buildMethodCard(
                  icon: Icons.upload_file,
                  title: '导入教务系统导出的文件',
                  subtitle: '在教务系统「课程表」页面导出 .xls/.xlsx 文件后导入',
                  onTap: _pickFile,
                  color: AppTheme.secondary,
                ),
                const SizedBox(height: 12),
                _buildMethodCard(
                  icon: Icons.content_paste,
                  title: '粘贴课程表文本',
                  subtitle: '从教务系统复制课程表单元格内容，粘贴到下方',
                  onTap: () => _showPasteDialog(context),
                  color: AppTheme.accent,
                ),
                const SizedBox(height: 16),
                _buildWebHintCard(),
              ],
            ),
          ),
          if (_loading)
            Positioned.fill(
              child: ColoredBox(
                color: const Color(0x66000000),
                child: Center(
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 28, vertical: 24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const CircularProgressIndicator(),
                          const SizedBox(height: 14),
                          Text(_loadingText),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildMethodCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    required Color color,
  }) {
    return Card(
      child: InkWell(
        onTap: _loading ? null : onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: color, size: 26),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: AppTheme.textSecondary),
            ],
          ),
        ),
      ),
    );
  }

  /// 网页登录导入的说明卡片（仅 Android 可用）。
  Widget _buildWebHintCard() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.primary.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.help_outline_rounded,
                  size: 18, color: AppTheme.primary),
              SizedBox(width: 8),
              Text(
                '网页导入怎么用',
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.primary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            '1. 点「登录教务系统网页导入」，应用内会打开内师融合门户（先跳统一身份认证）；\n'
            '2. 用学号密码正常登录（滑块验证码在网页里完成）；\n'
            '3. 登录后在门户里自己点进「课表查询 / 我的课表」，等课表表格出现；\n'
            '4. 点右上角「读取课表 ✓」，识别成功后自动导入。\n\n'
            '登录状态会保存在本机，下次一般不用重新登录。\n'
            '校外网络也能用（默认入口是公网可达的融合门户）。\n'
            '若门户点不动或卡住，点地址栏右边「⋮ → 打开课表查询页」，直接走教务课表页重试。',
            style: TextStyle(
              fontSize: 12,
              height: 1.6,
              color: AppTheme.textSecondary,
            ),
          ),
          if (!JwxtService.supported) ...[
            const SizedBox(height: 8),
            const Text(
              '注意：该方式仅在 Android 版可用。',
              style: TextStyle(fontSize: 12, color: Color(0xFFD97706)),
            ),
          ],
        ],
      ),
    );
  }

  // ------------------------------------------------------------ 网页登录导入

  Future<void> _webImport() async {
    setState(() {
      _loading = true;
      _loadingText = '正在读取网页…';
    });
    final WebImportResult result;
    try {
      result = await JwxtService.importFromWeb();
    } finally {
      if (mounted) setState(() => _loading = false);
    }
    if (!mounted) return;

    if (result.pageUrl.isNotEmpty) {
      setState(() => _lastUrl = result.pageUrl);
    }

    if (result.ok && result.timetable != null) {
      await _saveAndGo(result.timetable!);
      return;
    }
    if (result.cancelled) return;
    _showWebFailureDialog(result);
  }

  /// 网页打开了但没解析出课表时的兜底：可以重试、改用粘贴（已预填抓到的文字）。
  void _showWebFailureDialog(WebImportResult result) {
    final hasText = result.rawText.trim().isNotEmpty;
    if (hasText) {
      _textController.text = result.rawText;
    }
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('没有识别到课表'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(result.message, style: const TextStyle(fontSize: 13)),
              if (result.pageTitle.isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(
                  '当前页面：${result.pageTitle}',
                  style: const TextStyle(
                      fontSize: 12, color: AppTheme.textSecondary),
                ),
              ],
              if (result.pageUrl.isNotEmpty)
                Text(
                  result.pageUrl,
                  style: const TextStyle(
                      fontSize: 11, color: AppTheme.textSecondary),
                ),
              if (hasText) ...[
                const SizedBox(height: 10),
                const Text(
                  '已把抓到的页面文字填进「粘贴导入」，也可以直接用它再试一次。',
                  style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('关闭'),
          ),
          if (hasText)
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                _showPasteDialog(context);
              },
              child: const Text('改用粘贴导入'),
            ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _webImport();
            },
            child: const Text('再试一次'),
          ),
        ],
      ),
    );
  }

  // ------------------------------------------------------------ 文件导入

  /// 选择文件导入。
  Future<void> _pickFile() async {
    setState(() {
      _loading = true;
      _loadingText = '正在解析课表…';
    });
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['xls', 'xlsx'],
        withData: true,
      );
      if (result == null || result.files.isEmpty) {
        setState(() => _loading = false);
        return;
      }

      final file = result.files.first;
      final bytes = file.bytes;
      if (bytes == null) {
        _showError('无法读取文件');
        setState(() => _loading = false);
        return;
      }

      final grid = _parseExcel(bytes);
      if (grid.isEmpty) {
        _showError('解析失败：无法识别该文件格式。\n'
            '请确认是教务系统「课程表」页面导出的 .xls/.xlsx 文件；'
            '若文件已损坏，可在 Excel/WPS 中「另存为 .xlsx」后重试，'
            '或改用「粘贴课程表文本」方式导入。');
        setState(() => _loading = false);
        return;
      }

      final tt = TimetableParser.parseGrid(grid,
          name: file.name.replaceAll(RegExp(r'\.(xls|xlsx)$'), ''));
      await _saveAndGo(tt);
    } catch (e) {
      _showError('导入失败：$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// 解析导入的文件字节为二维字符串表。
  ///
  /// 教务系统导出的 `.xls` 是老式 BIFF8 / OLE2 格式，而 `excel` 包只支持
  /// `.xlsx`（zip + XML），因此这里先用 `XlsReader` 识别 OLE2 头并自行解析；
  /// 不是 OLE2 的才交给 `excel` 包按 `.xlsx` 处理。
  List<List<String>> _parseExcel(Uint8List bytes) {
    if (XlsReader.looksLikeXls(bytes)) {
      final grid = XlsReader.readFirstSheet(bytes);
      if (grid != null && grid.isNotEmpty) return grid;
    }
    return _parseXlsx(bytes);
  }

  /// 用 excel 库解析 .xlsx 字节为二维字符串表。
  List<List<String>> _parseXlsx(Uint8List bytes) {
    try {
      final excel = Excel.decodeBytes(bytes);
      final rows = <List<String>>[];
      for (final table in excel.tables.keys) {
        final sheet = excel.tables[table]!;
        for (final row in sheet.rows) {
          final cells = <String>[];
          for (final cell in row) {
            final v = cell?.value;
            cells.add(v?.toString() ?? '');
          }
          rows.add(cells);
        }
        break; // 只取第一个 sheet
      }
      return rows;
    } catch (_) {
      return const <List<String>>[];
    }
  }

  // ------------------------------------------------------------ 粘贴导入

  void _showPasteDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('粘贴课程表'),
        content: SizedBox(
          width: double.maxFinite,
          child: TextField(
            controller: _textController,
            maxLines: 12,
            decoration: const InputDecoration(
              hintText: '粘贴教务系统课程表文本（每行一门课，格式：\n课程名 周x 第n-m节 周a-b 地点 教师）\n\n或直接粘贴整个表格文本',
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () {
              final text = _textController.text.trim();
              if (text.isEmpty) {
                Navigator.pop(context);
                return;
              }
              Navigator.pop(context);
              _parseText(context, text);
            },
            child: const Text('解析导入'),
          ),
        ],
      ),
    );
  }

  void _parseText(BuildContext context, String text) {
    // TimetableParser.parseFreeText 内部已处理「制表符表格」与「逐行文本」两种情况，
    // 这里不再自行判断，避免两处逻辑不一致。
    final tt = TimetableParser.parseFreeText(text);
    _saveAndGo(tt);
  }

  // ------------------------------------------------------------ 保存

  Future<void> _saveAndGo(Timetable tt) async {
    if (tt.courses.isEmpty) {
      _showError('未解析到任何课程，请检查输入格式');
      return;
    }
    // 设置默认名称
    if (tt.name.isEmpty) {
      tt.name = '课表 ${tt.courses.length}门课';
    }
    await context.read<AppState>().addTimetable(tt);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          tt.startDate == null
              ? '成功导入 ${tt.courses.length} 门课程！'
                  '未识别到学期开始日期，请到「设置」里补充，否则课程提醒无法排准。'
              : '成功导入 ${tt.courses.length} 门课程！',
        ),
        backgroundColor: AppTheme.accent,
      ),
    );
    Navigator.pop(context);
  }

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: Colors.red),
    );
  }
}
