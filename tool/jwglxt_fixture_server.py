"""正方 jwglxt 课表接口固件服务（仅用于端到端测试）。

模拟四件事：
  1. GET  /jwglxt/kbcx/xskbcx_cxXskbcxIndex.html
     一个「课表查询」页面：带 xnm/xqm 控件、一张带「星期一」的课表骨架表。
  2. POST /jwglxt/kbcx/xskbcx_cxXskbcxIndex.html?doType=query&gnmkdm=N2151
     返回真实的 `kbList` JSON（字段与正方 V9 一致）。
  3. GET  /sso/driotlogin?url=kbcx%252Fxskbcx_cxXskbcxIndex.html%253F...
     **内江师范真实形态**：反向代理把真地址藏在 `url=` 参数里（双层百分号编码），
     路径里没有 `/kbcx/` 那一段。这里直接吐课表页（不跳转）—— 用来验证
     App 能解两遍码把接口端点推出来。
  4. GET  /sso/driotlogin_r  → 302 → /kbcx/xskbcx_cxXskbcxIndex.html
     同一个反向代理，但登录完是**跳转**过去的（更接近真实跳链）。跳转后
     `url=` 参数没了，只能靠路径推端点 —— 两条路都要能推导出同一个接口。

用来验证 App 里那条「优先走 JSON 接口」的抓取路径：
WebView 打开页面，注入脚本算出端点点，Kotlin 侧 POST 数据接口，把 kbList 回传给 Dart。

    python jwglxt_fixture_server.py 8138

另外两个只给测试用的观察口：
  GET /__posts  → {"posts": ["/kbcx/xskbcx_cxXsKb.html", ...]}  按顺序记录收到的 POST 路径
  GET /__reset  → 清空上面的记录
"""

import json
import sys
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlparse

# 收到的 POST 路径（供 `/__posts` 读取，用来证明「打的是推导出来的数据接口」）
POSTS = []
POSTS_LOCK = threading.Lock()

PAGE = """<!DOCTYPE html>
<html lang="zh-CN"><head><meta charset="utf-8">
<title>学生课表</title></head>
<body>
<div class="container">
  <h2>课表查询</h2>
  <form id="searchForm">
    <select id="xnm" name="xnm">
      <option value="2026" selected>2026-2027</option>
    </select>
    <select id="xqm" name="xqm">
      <option value="3" selected>1</option>
      <option value="12">2</option>
    </select>
    <input type="button" value="查询">
  </form>
  <table id="kbtable">
    <thead><tr><th>节次</th><th>星期一</th><th>星期二</th><th>星期三</th>
      <th>星期四</th><th>星期五</th><th>星期六</th><th>星期日</th></tr></thead>
    <tbody>
      <tr><td>第1-2节</td><td><div class="kbcontent">人工智能导论</div></td>
        <td></td><td></td><td></td><td></td><td></td><td></td></tr>
      <tr><td>第3-4节</td><td></td><td></td><td></td><td></td><td></td><td></td><td></td></tr>
    </tbody>
  </table>
</div>
</body></html>
"""

KBLIST = {
    "kbList": [
        {
            "kcmc": "人工智能导论",
            "xm": "韩云",
            "cdmc": "明德楼B216",
            "xqj": "1",
            "jcs": "1-2",
            "zcd": "7-18周",
        },
        {
            "kcmc": "高等数学Ⅰ（上）",
            "xm": "曾玉祥",
            "cdmc": "明德楼A103",
            "xqj": "1",
            "jcs": "3-4",
            "zcd": "1-16周",
        },
        {
            "kcmc": "大学物理V（上）",
            "xm": "张熙程",
            "cdmc": "明德楼B105",
            "xqj": "4",
            "jcs": "7-8",
            "zcd": "1-15周(单)",
        },
        {
            "kcmc": "思想道德与法治",
            "xm": "代维",
            "cdmc": "明德楼B303",
            "xqj": "5",
            "jcs": "9-10",
            "zcd": "1,3,5-9周",
        },
    ],
    "sjkList": [],
    "xkkg": True,
}


class Handler(BaseHTTPRequestHandler):
    def _send(self, body: bytes, ctype: str):
        self.send_response(200)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _send_json(self, obj):
        self._send(json.dumps(obj, ensure_ascii=False).encode("utf-8"),
                   "application/json; charset=utf-8")

    def do_GET(self):  # noqa: N802
        parsed = urlparse(self.path)
        path = parsed.path
        if path == "/__posts":
            with POSTS_LOCK:
                self._send_json({"posts": list(POSTS)})
            return
        if path == "/__reset":
            with POSTS_LOCK:
                POSTS.clear()
            self._send_json({"ok": True})
            return
        # 反向代理：登录接口「不跳转」，直接在原地吐课表页（`url=` 参数还在）
        if path == "/sso/driotlogin":
            self._send(PAGE.encode("utf-8"), "text/html; charset=utf-8")
            return
        # 反向代理：登录接口「跳转」到真正的课表页（更接近真实跳链）
        if path == "/sso/driotlogin_r":
            self.send_response(302)
            self.send_header("Location", "/kbcx/xskbcx_cxXskbcxIndex.html")
            self.end_headers()
            return
        if path.endswith("xskbcx_cxXskbcxIndex.html") or path.endswith(
            "xskbcx_cxXsgrkb.html"
        ):
            self._send(PAGE.encode("utf-8"), "text/html; charset=utf-8")
        else:
            self.send_response(404)
            self.end_headers()

    def do_POST(self):  # noqa: N802
        length = int(self.headers.get("Content-Length") or 0)
        body = self.rfile.read(length)
        sys.stderr.write(f"[fixture] POST {self.path} body={body!r}\n")
        sys.stderr.flush()
        with POSTS_LOCK:
            POSTS.append(urlparse(self.path).path)
        self._send_json(KBLIST)

    def log_message(self, fmt, *args):  # 静音
        pass


if __name__ == "__main__":
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 8138
    print(f"jwglxt fixture serving on 0.0.0.0:{port}", flush=True)
    ThreadingHTTPServer(("0.0.0.0", port), Handler).serve_forever()
