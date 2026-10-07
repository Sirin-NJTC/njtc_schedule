# 下载离线 OCR 的语言模型到 android/app/src/main/assets/tessdata/。
#
# 为什么不进仓库：chi_sim 高精度模型 12.5MB、eng 3.9MB，塞进 git 会让仓库和源码 zip
# 都胖一圈，而且这俩文件是可复现的公开资源（tesseract-ocr 官方仓库，Apache-2.0）。
# 构建前跑一次即可；`flutter build apk` 会用 Android assets 打进 APK。
#
# 用法（PowerShell 默认禁止直接运行未签名脚本，用下面这行）：
#   Invoke-Expression (Get-Content -Raw -Encoding UTF8 'D:\DSH\njtc_schedule\tool\fetch_tessdata.ps1')
#
# 模型选择：
#   chi_sim → tessdata_best（12.5MB）识别最准，课表截图里的中文课程名/教师/教室靠它
#   eng     → tessdata_fast（3.9MB）只作补充（楼栋号、Python、B213 这类拉丁字母数字），
#             用 fast 版本省 10MB；觉得英文识别不够好再换 best

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

# 注意：用 `Invoke-Expression (Get-Content ...)` 跑这个脚本时 $PSScriptRoot 是空的
# （不是脚本上下文），所以这里从当前目录往上找带 pubspec.yaml 的仓库根。
function Find-RepoRoot {
    $dir = Get-Location
    foreach ($i in 0..4) {
        if (Test-Path (Join-Path $dir.Path 'pubspec.yaml')) { return $dir.Path }
        $parent = Split-Path -Parent $dir.Path
        if (-not $parent -or $parent -eq $dir.Path) { break }
        $dir = Get-Item $parent
    }
    throw "没找到仓库根（向上 5 层都没有 pubspec.yaml）。请 cd 到 njtc_schedule 目录后再跑。"
}

$repoRoot = Find-RepoRoot
$destDir = Join-Path $repoRoot 'android\app\src\main\assets\tessdata'
New-Item -ItemType Directory -Force -Path $destDir | Out-Null

# name | 来源仓库 | 期望字节数（用于校验下载完整性）
$files = @(
    @{ Name = 'chi_sim.traineddata'; Repo = 'tessdata_best'; Size = 13077423 },
    @{ Name = 'eng.traineddata';     Repo = 'tessdata_fast'; Size = 4113088 }
)

# 直连 raw.githubusercontent.com 在国内网络经常超时/被重置（实测 12s 超时、0 字节），
# 所以按顺序试几个镜像：{repo} 换成仓库名，{file} 换成文件名。
$sources = @(
    'https://gh-proxy.com/https://raw.githubusercontent.com/tesseract-ocr/{repo}/main/{file}',
    'https://ghfast.top/https://raw.githubusercontent.com/tesseract-ocr/{repo}/main/{file}',
    'https://cdn.jsdelivr.net/gh/tesseract-ocr/{repo}@main/{file}',
    'https://raw.githubusercontent.com/tesseract-ocr/{repo}/main/{file}'
)

# 找一个能用的镜像把 $Name 下到 $Path，校验字节数。返回实际用到的 URL。
function Get-Model {
    param([string]$Repo, [string]$Name, [string]$Path, [long]$Size)
    $errors = @()
    foreach ($tpl in $sources) {
        $url = $tpl.Replace('{repo}', $Repo).Replace('{file}', $Name)
        $tmp = "$Path.part"
        Write-Host ("[get ] {0} ← {1}" -f $Name, $url)
        try {
            $sw = [System.Diagnostics.Stopwatch]::StartNew()
            Invoke-WebRequest -Uri $url -OutFile $tmp -TimeoutSec 1200
            $len = (Get-Item $tmp).Length
            if ($Size -gt 0 -and $len -ne $Size) { throw "字节数不对：$len ≠ $Size" }
            Move-Item -Force $tmp $Path
            Write-Host ("[ok  ] {0} {1:N1} MB / {2:N1}s" -f $Name, ($len / 1MB), $sw.Elapsed.TotalSeconds)
            return $url
        } catch {
            if (Test-Path $tmp) { Remove-Item -Force $tmp -ErrorAction SilentlyContinue }
            $msg = $_.Exception.Message
            if ($msg.Length -gt 70) { $msg = $msg.Substring(0, 70) }
            Write-Host ("[fail] $msg") -ForegroundColor DarkYellow
            $errors += "$url → $msg"
        }
    }
    throw "所有镜像都失败：`n" + ($errors -join "`n")
}

$total = 0
foreach ($f in $files) {
    $path = Join-Path $destDir $f.Name
    if ((Test-Path $path) -and ((Get-Item $path).Length -eq $f.Size)) {
        Write-Host ("[skip] {0} 已存在（{1:N1} MB）" -f $f.Name, ($f.Size / 1MB))
        $total += $f.Size
        continue
    }
    Get-Model -Repo $f.Repo -Name $f.Name -Path $path -Size $f.Size | Out-Null
    $total += (Get-Item $path).Length
}

Write-Host ("tessdata 就绪：{0} 个文件 / {1:N1} MB → {2}" -f $files.Count, ($total / 1MB), $destDir)
