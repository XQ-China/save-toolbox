param()

# ==========================================================
#  存档工具箱
#  ① 查找存档（输入游戏名 → 位置 + 文件）
#  ② 上传（本地存档传进仓库）
#  ③ 下载（仓库存档放回原位置）
#  ④ 仓库连接
#  左下角区块标题可收起 / 展开
# ==========================================================

$ErrorActionPreference = 'Stop'
$script:Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$script:CfgPath = Join-Path $script:Root 'config.txt'

$global:SR_Strict = $false

$global:SR_Aliases = @{
  '星露谷' = @('stardew');   '星露谷物语' = @('stardew')
  '泰拉瑞亚' = @('terraria'); '泰拉' = @('terraria')
  '空洞骑士' = @('hollow');   '我的世界' = @('minecraft'); 'mc' = @('minecraft')
  '饥荒' = @('klei', 'dontstarve')
  '黑帝斯' = @('hades');      '哈迪斯' = @('hades')
  '以撒' = @('isaac');        '文明' = @('civilization', 'civ')
  '巫师' = @('witcher');      '赛博朋克' = @('cyberpunk')
  '上古卷轴' = @('skyrim', 'elder scrolls'); '辐射' = @('fallout')
  '侠盗猎车' = @('gta');      '群星' = @('stellaris')
  '缺氧' = @('oxygen not included'); '边缘世界' = @('rimworld')
  '模拟人生' = @('sims');     '星界边境' = @('starbound')
  '杀戮尖塔' = @('slay the spire'); '死亡细胞' = @('dead cells')
  '艾尔登法环' = @('elden ring'); '只狼' = @('sekiro')
  '博德之门' = @('baldur');   '大表哥' = @('red dead')
  '无主之地' = @('borderlands'); '最终幻想' = @('final fantasy')
  '森林' = @('theforest', 'sons of the forest'); '底特律' = @('detroit')
  '影之刃零' = @('phantombladezero', 'phantomblade', 'pbz'); '影之刃' = @('phantombladezero', 'phantomblade', 'pbz')
  '黑神话悟空' = @('blackmythwukong', 'blackmyth', 'wukong'); '黑神话' = @('blackmythwukong', 'blackmyth')
  '地下城' = @('minecraftdungeons', 'dungeons')
  '鬼谷八荒' = @('taleofimmortal'); '暖雪' = @('warmsnow'); '太吾绘卷' = @('taiwu')
  '仁王' = @('nioh'); '尼尔' = @('nier'); '师父' = @('sifu'); '戴森球' = @('dyson')
}

$script:SaveExts = @('.sav', '.save', '.es3', '.slot', '.sgm', '.plr', '.wld', '.rvdata2', '.rpgsave', '.sl2', '.dat',
  '.json', '.cfg', '.xml', '.profile', '.savx')

# ================= 配置 =================
function Read-Config([string]$path) {
  $cfg = [ordered]@{ repo = ''; branch = 'main'; token = ''; dest_root = ''; backup = 'yes'; backup_dir = '' }
  if (Test-Path -LiteralPath $path) {
    foreach ($line in (Get-Content -LiteralPath $path -Encoding UTF8)) {
      $line = $line.Trim()
      if (-not $line -or $line.StartsWith('#')) { continue }
      $eq = $line.IndexOf('=')
      if ($eq -lt 1) { continue }
      $k = $line.Substring(0, $eq).Trim().ToLower()
      $v = $line.Substring($eq + 1).Trim()
      if ($cfg.Contains($k)) { $cfg[$k] = $v }
    }
  }
  if (-not $cfg.branch) { $cfg.branch = 'main' }
  if (-not $cfg.backup) { $cfg.backup = 'yes' }
  return $cfg
}

function Save-Config($cfg, [string]$path) {
  $lines = @('# ---------------------------------------------')
  $lines += '#  存档工具箱 · 配置文件'
  $lines += '# ---------------------------------------------'
  $lines += ('repo=' + $cfg.repo)
  $lines += ('branch=' + $cfg.branch)
  $lines += ('token=' + $cfg.token)
  $lines += ('dest_root=' + $cfg.dest_root)
  $lines += ('backup=' + $cfg.backup)
  $lines += ('backup_dir=' + $cfg.backup_dir)
  [System.IO.File]::WriteAllText($path, ($lines -join "`r`n"), (New-Object System.Text.UTF8Encoding($false)))
}

# ================= GitHub =================
function Get-Headers($cfg, [string]$accept = 'application/vnd.github+json') {
  $h = @{ 'User-Agent' = 'save-toolbox'; 'Accept' = $accept }
  if ($cfg.token -and $cfg.token.Length -gt 0) { $h['Authorization'] = 'Bearer ' + $cfg.token }
  return $h
}

function ConvertTo-RepoPath([string]$path) {
  return (($path -split '/') | ForEach-Object { [uri]::EscapeDataString($_) }) -join '/'
}

function Get-Tree($cfg) {
  $url = 'https://api.github.com/repos/' + $cfg.repo + '/git/trees/' + $cfg.branch + '?recursive=1'
  $res = Invoke-RestMethod -Uri $url -Headers (Get-Headers $cfg) -Method Get
  if (-not $res.tree) { throw '拿不到仓库目录，检查 用户名/仓库名 和分支' }
  return $res.tree
}

function Get-RawText($cfg, [string]$repoPath) {
  $url = 'https://api.github.com/repos/' + $cfg.repo + '/contents/' + (ConvertTo-RepoPath $repoPath) + '?ref=' + $cfg.branch
  return Invoke-RestMethod -Uri $url -Headers (Get-Headers $cfg 'application/vnd.github.raw') -Method Get
}

function Get-RemoteSha($cfg, [string]$repoPath) {
  try {
    $url = 'https://api.github.com/repos/' + $cfg.repo + '/contents/' + (ConvertTo-RepoPath $repoPath) + '?ref=' + $cfg.branch
    $r = Invoke-RestMethod -Uri $url -Headers (Get-Headers $cfg) -Method Get
    if ($r -is [array]) { return $null }
    return $r.sha
  } catch { return $null }
}

function Put-File($cfg, [string]$repoPath, [string]$content, [string]$message) {
  $url = 'https://api.github.com/repos/' + $cfg.repo + '/contents/' + (ConvertTo-RepoPath $repoPath)
  $bytes = [System.Text.Encoding]::UTF8.GetBytes($content)
  $body = @{ message = $message; content = [Convert]::ToBase64String($bytes); branch = $cfg.branch }
  $sha = Get-RemoteSha $cfg $repoPath
  if ($sha) { $body['sha'] = $sha }
  Invoke-RestMethod -Uri $url -Method Put -Headers (Get-Headers $cfg) -Body ($body | ConvertTo-Json -Compress) -ContentType 'application/json' | Out-Null
}

function Put-BinaryFile($cfg, [string]$repoPath, [string]$localFile, [string]$message) {
  $url = 'https://api.github.com/repos/' + $cfg.repo + '/contents/' + (ConvertTo-RepoPath $repoPath)
  $bytes = [System.IO.File]::ReadAllBytes($localFile)
  $body = @{ message = $message; content = [Convert]::ToBase64String($bytes); branch = $cfg.branch }
  $sha = Get-RemoteSha $cfg $repoPath
  if ($sha) { $body['sha'] = $sha }
  Invoke-RestMethod -Uri $url -Method Put -Headers (Get-Headers $cfg) -Body ($body | ConvertTo-Json -Compress) -ContentType 'application/json' | Out-Null
}

# ================= 下载 / 上传 =================
function Build-Plan($cfg, $tree) {
  $paths = @{}
  foreach ($n in $tree) { if ($n.type -eq 'blob') { $paths[$n.path] = $true } }

  $plan = @()
  $metas = $tree | Where-Object { $_.type -eq 'blob' -and $_.path -match 'meta\.json$' }
  foreach ($m in $metas) {
    $dir = ''
    $i = $m.path.LastIndexOf('/')
    if ($i -ge 0) { $dir = $m.path.Substring(0, $i) }
    try { $meta = (Get-RawText $cfg $m.path) | ConvertFrom-Json }
    catch {
      $plan += [pscustomobject]@{ Game = '(读不了)'; File = $m.path; Target = ''; RepoPath = $m.path; State = 'meta 解析失败' }
      continue
    }
    $name = $meta.name
    if (-not $name) { $name = if ($dir) { Split-Path -Leaf $dir } else { '未命名' } }
    $dest = $meta.localPath
    if (-not $dest) { $dest = $cfg.dest_root }
    if (-not $dest) {
      $plan += [pscustomobject]@{ Game = $name; File = '(未填位置)'; Target = ''; RepoPath = $m.path; State = '缺存档位置' }
      continue
    }
    $dest = [Environment]::ExpandEnvironmentVariables($dest).TrimEnd('\', '/')
    $files = @($meta.files)
    if (-not $files -or $files.Count -eq 0) {
      $plan += [pscustomobject]@{ Game = $name; File = '(空)'; Target = $dest; RepoPath = $m.path; State = 'meta 里没有文件' }
      continue
    }
    foreach ($f in $files) {
      $f = "$f".Trim()
      if (-not $f) { continue }
      $repoPath = if ($dir) { $dir + '/' + $f } else { $f }
      $state = if ($paths.ContainsKey($repoPath)) { '待下载' } else { '仓库里找不到' }
      $plan += [pscustomobject]@{ Game = $name; File = $f; Target = $dest; RepoPath = $repoPath; State = $state }
    }
  }
  return $plan
}

function Download-Item($cfg, $item) {
  $url = 'https://api.github.com/repos/' + $cfg.repo + '/contents/' + (ConvertTo-RepoPath $item.RepoPath) + '?ref=' + $cfg.branch
  if (-not (Test-Path -LiteralPath $item.Target)) { New-Item -ItemType Directory -Force -Path $item.Target | Out-Null }
  $out = Join-Path $item.Target $item.File
  if ((Test-Path -LiteralPath $out) -and $cfg.backup -eq 'yes') {
    $bakRoot = $cfg.backup_dir
    if (-not $bakRoot) { $bakRoot = Join-Path $script:Root '备份' }
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $bakDir = Join-Path (Join-Path $bakRoot $item.Game) $stamp
    if (-not (Test-Path -LiteralPath $bakDir)) { New-Item -ItemType Directory -Force -Path $bakDir | Out-Null }
    Copy-Item -LiteralPath $out -Destination (Join-Path $bakDir $item.File) -Force
  }
  Invoke-WebRequest -Uri $url -Headers (Get-Headers $cfg 'application/vnd.github.raw') -OutFile $out -UseBasicParsing | Out-Null
  return $out
}

function Clear-BackupFolder($cfg, [scriptblock]$logFn) {
  $root = $cfg.backup_dir
  if (-not $root) { $root = Join-Path $script:Root '备份' }
  if (-not (Test-Path -LiteralPath $root)) { & $logFn '没有备份文件夹，不用清' 'warn'; return 0 }
  $files = @(Get-ChildItem -LiteralPath $root -Recurse -File -Force -ErrorAction SilentlyContinue)
  if ($files.Count -eq 0) { & $logFn '备份文件夹是空的' 'warn'; return 0 }
  $kb = [math]::Round((($files | Measure-Object Length -Sum).Sum) / 1KB)
  Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
  & $logFn ('已清除 {0} 个备份文件（{1} KB）：{2}' -f $files.Count, $kb, $root) 'ok'
  return $files.Count
}

function Upload-Saves($cfg, [string]$game, [string]$localDir, [string[]]$files, [scriptblock]$logFn) {
  $dirRepo = '存档/' + $game
  foreach ($f in $files) {
    $local = Join-Path $localDir $f
    if (-not (Test-Path -LiteralPath $local)) { & $logFn ("跳过（本地没有）：$f") 'warn'; continue }
    Put-BinaryFile $cfg ($dirRepo + '/' + $f) $local ('上传存档 ' + $game + '/' + $f)
    & $logFn ("已上传： $f") 'ok'
  }
  $meta = [ordered]@{
    name      = $game
    localPath = $localDir
    files     = @($files)
    updated   = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
  }
  Put-File $cfg ($dirRepo + '/meta.json') ($meta | ConvertTo-Json -Depth 5) ('更新 meta.json ' + $game)
  & $logFn '已写入： meta.json' 'ok'
}

function Rebuild-Readme($cfg) {
  $tree = Get-Tree $cfg
  $rows = @()
  foreach ($m in ($tree | Where-Object { $_.type -eq 'blob' -and $_.path -match 'meta\.json$' })) {
    try {
      $meta = (Get-RawText $cfg $m.path) | ConvertFrom-Json
      $dir = ''
      $i = $m.path.LastIndexOf('/')
      if ($i -ge 0) { $dir = $m.path.Substring(0, $i) }
      $nm = if ($meta.name) { $meta.name } else { $dir }
      foreach ($f in @($meta.files)) { $rows += '| ' + $nm + ' | ' + $dir + '/' + $f + ' | ' + $meta.localPath + ' |' }
    } catch { }
  }
  $md = "# 游戏存档`r`n`r`n| 游戏名 | 存档文件 | 存档文件位置 |`r`n| --- | --- | --- |`r`n" + ($rows -join "`r`n") + "`r`n"
  Put-File $cfg 'README.md' $md '更新存档清单'
  return $rows.Count
}

# ================= 查找存档 =================
function Get-Norm([string]$t) {
  if (-not $t) { return '' }
  $t = $t.ToLower()
  $t = $t -replace '[\s_\-\.\\/]', ''
  $t = $t.Replace('"', '').Replace("'", '')
  return $t
}

function New-Hit([string]$game, [string]$path, $files) {
  $pick = @($files | Where-Object { $script:SaveExts -contains $_.Extension.ToLower() })
  if ($pick.Count -eq 0) { $pick = @($files) }
  return [pscustomobject]@{
    Game      = $game
    Path      = $path
    SaveFiles = @($pick)
    SaveCount = $pick.Count
    SizeKB    = [math]::Round((($pick | Measure-Object Length -Sum).Sum) / 1024)
    Last      = ($files | Select-Object -First 1).LastWriteTime
  }
}

function Get-SearchRoots {
  $roots = @()
  if ($env:APPDATA) { $roots += $env:APPDATA }
  if ($env:LOCALAPPDATA) { $roots += $env:LOCALAPPDATA }
  if ($env:USERPROFILE) {
    $roots += (Join-Path $env:USERPROFILE 'AppData\LocalLow')
    $roots += (Join-Path $env:USERPROFILE 'Saved Games')
  }
  $docs = [Environment]::GetFolderPath('MyDocuments')
  if ($docs) { $roots += $docs }
  try {
    $steam = (Get-ItemProperty 'HKCU:\Software\Valve\Steam' -ErrorAction Stop).SteamPath
    if ($steam -and (Test-Path -LiteralPath $steam)) {
      $roots += (Join-Path $steam 'steamapps\common')
      $roots += (Join-Path $steam 'userdata')
    }
  } catch { }
  try { $drives = Get-PSDrive -PSProvider FileSystem -ErrorAction SilentlyContinue | Where-Object { $_.Root -match '^[A-Za-z]:' } } catch { $drives = @() }
  foreach ($d in $drives) {
    foreach ($sub in @('Games', 'Game', '游戏', 'SteamLibrary', 'Epic Games', 'WeGameApps', 'XboxGames',
                       'Program Files (x86)\Steam\steamapps\common', 'Program Files\Steam\steamapps\common')) {
      $p = Join-Path $d.Root $sub
      if (Test-Path -LiteralPath $p) { $roots += $p }
    }
  }
  return $roots | Where-Object { $_ -and (Test-Path -LiteralPath $_) } | Select-Object -Unique
}

function Find-GameDirs([string]$keyword, $roots, [scriptblock]$onStep = $null) {
  $kw = $keyword.Trim().ToLower()
  if (-not $kw) { return @() }

  $terms = @(Get-Norm $kw)
  if (-not $global:SR_Strict) {
    foreach ($w in ($kw -split '[^\p{L}\p{N}]')) { if ($w.Length -ge 4) { $terms += (Get-Norm $w) } }
  }
  foreach ($k in $global:SR_Aliases.Keys) {
    $nk = Get-Norm $k
    $nkw = Get-Norm $kw
    if ($nk.Contains($nkw) -or $nkw.Contains($nk)) {
      foreach ($a in $global:SR_Aliases[$k]) {
        $terms += (Get-Norm $a)
        if (-not $global:SR_Strict) { foreach ($w in ($a -split '[^\p{L}\p{N}]')) { if ($w.Length -ge 4) { $terms += (Get-Norm $w) } } }
      }
    }
  }
  $weak = @('game', 'games', 'save', 'saves', 'data', 'files', 'user', 'player', 'players')
  $terms = $terms | Where-Object { $_ -and $_ -notin $weak } | Select-Object -Unique

  $hits = @()
  $idx = 0
  foreach ($root in $roots) {
    $idx++
    if ($onStep) { & $onStep $root $idx $roots.Count }
    try {
      $dirs = Get-ChildItem -LiteralPath $root -Recurse -Depth 4 -Directory -Force -ErrorAction SilentlyContinue |
        Where-Object {
          $n = Get-Norm $_.Name
          (@($terms | Where-Object { $n.Contains((Get-Norm $_)) }).Count -gt 0)
        }
    } catch { continue }

    foreach ($d in $dirs) {
      $done = $false
      try { $files = @(Get-ChildItem -LiteralPath $d.FullName -File -Force -ErrorAction SilentlyContinue | Where-Object { $_.Length -lt 300MB } | Sort-Object LastWriteTime -Descending) } catch { $files = @() }
      if ($files.Count -gt 0) { $hits += (New-Hit $d.Name $d.FullName $files); $done = $true }

      if (-not $done) {
        try { $subs = Get-ChildItem -LiteralPath $d.FullName -Recurse -Depth 2 -Directory -Force -ErrorAction SilentlyContinue } catch { $subs = @() }
        foreach ($sd in $subs) {
          try { $sf = @(Get-ChildItem -LiteralPath $sd.FullName -File -Force -ErrorAction SilentlyContinue | Where-Object { $_.Length -lt 300MB } | Sort-Object LastWriteTime -Descending) } catch { $sf = @() }
          if ($sf.Count -gt 0) {
            $rel = $sd.FullName.Substring($d.FullName.Length).TrimStart('\', '/')
            $hits += (New-Hit ($d.Name + '\' + $rel) $sd.FullName $sf)
          }
        }
      }
    }
  }

  $seen = @{}
  $uniq = @()
  foreach ($h in ($hits | Sort-Object Last -Descending)) {
    if ($seen.ContainsKey($h.Path)) { continue }
    $seen[$h.Path] = 1
    $uniq += $h
  }
  return $uniq
}

function Find-InPath([string]$path) {
  $hits = @()
  $base = $path.TrimEnd('\', '/')
  try { $files = @(Get-ChildItem -LiteralPath $base -File -Force -ErrorAction SilentlyContinue | Where-Object { $_.Length -lt 300MB } | Sort-Object LastWriteTime -Descending) } catch { $files = @() }
  if ($files.Count -gt 0) { $hits += (New-Hit (Split-Path -Leaf $base) $base $files) }
  try { $subs = Get-ChildItem -LiteralPath $base -Recurse -Depth 2 -Directory -Force -ErrorAction SilentlyContinue } catch { $subs = @() }
  foreach ($sd in $subs) {
    try { $sf = @(Get-ChildItem -LiteralPath $sd.FullName -File -Force -ErrorAction SilentlyContinue | Where-Object { $_.Length -lt 300MB } | Sort-Object LastWriteTime -Descending) } catch { $sf = @() }
    if ($sf.Count -gt 0) {
      $rel = $sd.FullName.Substring($base.Length).TrimStart('\', '/')
      $hits += (New-Hit $rel $sd.FullName $sf)
    }
  }
  return $hits | Sort-Object Last -Descending
}

function Find-AllCandidates($roots, [scriptblock]$onStep = $null) {
  $noise = @('cache', 'cachedata', 'logs', 'log', 'crash', 'crashes', 'temp', 'tmp', 'shader', 'shadercache', 'backup')
  $map = @{}
  $idx = 0
  foreach ($root in $roots) {
    $idx++
    if ($onStep) { & $onStep $root $idx $roots.Count }
    try {
      $fs = Get-ChildItem -LiteralPath $root -Recurse -Depth 5 -File -Force -ErrorAction SilentlyContinue |
        Where-Object { $script:SaveExts -contains $_.Extension.ToLower() -and $_.Length -lt 300MB }
    } catch { continue }
    foreach ($f in $fs) {
      $dir = $f.Directory.FullName
      $dn = $f.Directory.Name.ToLower()
      if (@($noise | Where-Object { $dn -eq $_ -or $dn.Contains($_ + 'cache') }).Count -gt 0) { continue }
      if (-not $map.ContainsKey($dir)) { $map[$dir] = @() }
      $map[$dir] += $f
    }
  }
  $hits = @()
  foreach ($k in $map.Keys) {
    $arr = @($map[$k])
    $hits += [pscustomobject]@{
      Game      = (Split-Path -Leaf (Split-Path -Parent $k)) + '\' + (Split-Path -Leaf $k)
      Path      = $k
      SaveFiles = $arr
      SaveCount = $arr.Count
      SizeKB    = [math]::Round((($arr | Measure-Object Length -Sum).Sum) / 1024)
      Last      = ($arr | Sort-Object LastWriteTime -Descending | Select-Object -First 1).LastWriteTime
    }
  }
  return $hits | Sort-Object Last -Descending | Select-Object -First 300
}

# ================= 界面 =================
function Show-Gui {
  Add-Type -AssemblyName System.Windows.Forms
  Add-Type -AssemblyName System.Drawing

  $cfg = Read-Config $script:CfgPath
  if (-not (Test-Path -LiteralPath $script:CfgPath)) {
    try { Save-Config $cfg $script:CfgPath } catch { }
  }
  $script:Active = 0          # 左侧导航当前展开项（-1 表示全收起）

  $form = New-Object System.Windows.Forms.Form
  $form.Text = '存档工具箱'
  $form.ClientSize = New-Object System.Drawing.Size(900, 660)
  $form.StartPosition = 'CenterScreen'
  $form.Font = New-Object System.Drawing.Font('Microsoft YaHei UI', 9)
  $form.BackColor = [System.Drawing.Color]::FromArgb(246, 247, 249)
  $form.FormBorderStyle = 'FixedSingle'
  $form.MaximizeBox = $false

  # ---------- 小工具 ----------
  function New-Label([string]$t, [int]$x, [int]$y, [int]$w = 90, [int]$h = 22) {
    $l = New-Object System.Windows.Forms.Label
    $l.Text = $t
    $l.Location = New-Object System.Drawing.Point($x, $y)
    $l.Size = New-Object System.Drawing.Size($w, $h)
    $l.TextAlign = 'MiddleLeft'
    return $l
  }
  function New-Box([int]$x, [int]$y, [int]$w, [int]$h = 26, [string]$v = '') {
    $t = New-Object System.Windows.Forms.TextBox
    $t.Location = New-Object System.Drawing.Point($x, $y)
    $t.Size = New-Object System.Drawing.Size($w, $h)
    $t.Text = $v
    return $t
  }
  function New-Button([string]$t, [int]$x, [int]$y, [int]$w = 90, [int]$h = 28) {
    $b = New-Object System.Windows.Forms.Button
    $b.Text = $t
    $b.Location = New-Object System.Drawing.Point($x, $y)
    $b.Size = New-Object System.Drawing.Size($w, $h)
    $b.FlatStyle = 'System'
    return $b
  }

  # ---------- 左侧导航栏 ----------
  $rail = New-Object System.Windows.Forms.Panel
  $rail.Location = New-Object System.Drawing.Point(0, 0)
  $rail.Size = New-Object System.Drawing.Size(196, 660)
  $rail.BackColor = [System.Drawing.Color]::White
  $form.Controls.Add($rail)

  $railTitle = New-Label '存档工具箱' 16 12 160 26
  $railTitle.Font = New-Object System.Drawing.Font('Microsoft YaHei UI', 11, [System.Drawing.FontStyle]::Bold)
  $railTitle.ForeColor = [System.Drawing.Color]::FromArgb(40, 46, 54)
  $rail.Controls.Add($railTitle)

  $railNames = @('查找存档', '上传存档', '下载存档', '仓库连接')
  $railBtns = @()
  $ny = 52
  for ($i = 0; $i -lt $railNames.Count; $i++) {
    $b = New-Object System.Windows.Forms.Button
    $b.Text = '▸   ' + $railNames[$i]
    $b.Location = New-Object System.Drawing.Point(10, $ny)
    $b.Size = New-Object System.Drawing.Size(176, 40)
    $b.FlatStyle = 'Flat'
    $b.FlatAppearance.BorderSize = 0
    $b.TextAlign = 'MiddleLeft'
    $b.Padding = New-Object System.Windows.Forms.Padding(10, 0, 0, 0)
    $b.BackColor = [System.Drawing.Color]::White
    $b.Cursor = 'Hand'
    $b.Tag = $i
    $rail.Controls.Add($b)
    $railBtns += $b
    $ny += 44
  }

  # 分隔线
  $sep = New-Object System.Windows.Forms.Panel
  $sep.Location = New-Object System.Drawing.Point(196, 0)
  $sep.Size = New-Object System.Drawing.Size(1, 660)
  $sep.BackColor = [System.Drawing.Color]::FromArgb(214, 219, 226)
  $form.Controls.Add($sep)

  # ---------- ① 查找存档 ----------
  $bodyFind = New-Object System.Windows.Forms.Panel
  $bodyFind.Location = New-Object System.Drawing.Point(206, 40)
  $bodyFind.Size = New-Object System.Drawing.Size(680, 332)
  $bodyFind.BackColor = $form.BackColor

  $btnFind = New-Button '查找存档' 8 10 90 28
  $form.AcceptButton = $btnFind
  $btnCand = New-Button '列出全部候选' 106 10 110 28
  $btnToUpload = New-Button '填入上传区' 224 10 110 28
  $lblFindTip = New-Label '选中一行后点“填入上传区”，会跳到上传页' 342 12 320
  $lblFindSearch = New-Label '搜索' 8 48 46
  $tbFindSearch = New-Box 56 44 240 26 ''
  $lblFindSearchTip = New-Label '游戏名或文件夹名，回车也能搜（搜不到就粘英文名）' 300 48 344
  $lblFindList = New-Label '查找结果（只读，不会写文件）' 8 78 500

  $chkFindAll = New-Object System.Windows.Forms.CheckBox
  $chkFindAll.Text = ''
  $chkFindAll.AutoSize = $false
  $chkFindAll.Size = New-Object System.Drawing.Size(12, 12)
  $chkFindAll.Location = New-Object System.Drawing.Point(10, 108)

  $gdFind = New-Object System.Windows.Forms.DataGridView
  $gdFind.Location = New-Object System.Drawing.Point(8, 102)
  $gdFind.Size = New-Object System.Drawing.Size(660, 190)
  $gdFind.AllowUserToAddRows = $false
  $gdFind.AllowUserToDeleteRows = $false
  $gdFind.AllowUserToResizeRows = $false
  $gdFind.AllowUserToResizeColumns = $false
  $gdFind.RowHeadersVisible = $false
  $gdFind.SelectionMode = 'FullRowSelect'
  $gdFind.MultiSelect = $false
  $gdFind.ReadOnly = $true
  $gdFind.BorderStyle = 'FixedSingle'
  $gdFind.CellBorderStyle = 'SingleHorizontal'
  $gdFind.BackgroundColor = [System.Drawing.Color]::White
  $gdFind.GridColor = [System.Drawing.Color]::FromArgb(229, 231, 235)
  $gdFind.ColumnHeadersHeightSizeMode = 'DisableResizing'
  $gdFind.ColumnHeadersHeight = 22
  $gdFind.RowTemplate.Height = 22
  $gdFind.Font = New-Object System.Drawing.Font('Microsoft YaHei UI', 9)
  $gdFind.DefaultCellStyle.Padding = New-Object System.Windows.Forms.Padding(0)
  $gdFind.ColumnHeadersDefaultCellStyle.Padding = New-Object System.Windows.Forms.Padding(2, 0, 0, 0)
  foreach ($c in @(@('游戏', 140), @('存档文件', 100), @('大小', 52), @('存档位置', 294), @('状态', 66))) {
    $colF = New-Object System.Windows.Forms.DataGridViewTextBoxColumn
    $colF.HeaderText = [string]$c[0]
    $colF.Width = [int]$c[1]
    $colF.SortMode = 'NotSortable'
    $colF.ReadOnly = $true
    $colF.DefaultCellStyle.Padding = New-Object System.Windows.Forms.Padding(0)
    if ([string]$c[0] -eq '游戏') { $colF.HeaderCell.Style.Padding = New-Object System.Windows.Forms.Padding(14, 0, 0, 0) }
    [void]$gdFind.Columns.Add($colF)
    if ([string]$c[0] -eq '大小') { $colF.DefaultCellStyle.Alignment = 'MiddleRight' }
    if ([string]$c[0] -eq '状态') {
      $colF.DefaultCellStyle.Alignment = 'MiddleLeft'
      $colF.DefaultCellStyle.Padding = New-Object System.Windows.Forms.Padding(6, 0, 0, 0)
    }
  }

  $gdFind.add_CellToolTipTextNeeded({
    param($s2, $e2)
    if ($e2.RowIndex -lt 0 -or $e2.ColumnIndex -lt 0) { return }
    $v = $gdFind.Rows[$e2.RowIndex].Cells[$e2.ColumnIndex].Value
    if ($v) { $e2.ToolTipText = [string]$v }
  })

  $bodyFind.Controls.AddRange(@($btnFind, $btnCand, $btnToUpload, $lblFindTip,
      $lblFindSearch, $tbFindSearch, $lblFindSearchTip, $lblFindList, $gdFind, $chkFindAll))
  $chkFindAll.BringToFront()

  # ---------- ② 上传 ----------
  $bodyUp = New-Object System.Windows.Forms.Panel
  $bodyUp.Location = New-Object System.Drawing.Point(206, 40)
  $bodyUp.Size = New-Object System.Drawing.Size(680, 160)
  $bodyUp.BackColor = $form.BackColor
  $tbGameUp = New-Box 70 4 240 26 ''
  $tbDir = New-Box 70 36 340 26 ''
  $btnDir = New-Button '浏览…' 420 35 80 28
  $btnPick = New-Button '选择文件…' 70 68 100 28
  $lblPick = New-Label '可多选；先选目录再选文件' 180 70 300
  $lstFiles = New-Object System.Windows.Forms.ListBox
  $lstFiles.Location = New-Object System.Drawing.Point(70, 100)
  $lstFiles.Size = New-Object System.Drawing.Size(340, 62)
  $lstFiles.SelectionMode = 'MultiExtended'
  $btnUpload = New-Button '上传到仓库' 420 100 110 32
  $bodyUp.Controls.AddRange(@((New-Label '游戏名' 8 6 60), (New-Label '存档目录' 8 38 60), (New-Label '存档文件' 8 72 60),
      $tbGameUp, $tbDir, $btnDir, $btnPick, $lblPick, $lstFiles, $btnUpload))

  # ---------- ③ 下载 ----------
  $bodyDown = New-Object System.Windows.Forms.Panel
  $bodyDown.Location = New-Object System.Drawing.Point(206, 40)
  $bodyDown.Size = New-Object System.Drawing.Size(680, 300)
  $bodyDown.BackColor = $form.BackColor
  $btnPreview = New-Button '预览' 8 10 90 28
  $btnRestore = New-Button '开始还原' 106 10 110 28
  $btnClearBak = New-Button '清除备份' 224 10 110 28
  $lblDownTip = New-Label '还原前先备份到 备份\<游戏名>' 342 12 320

  $tbDlSearch = New-Box 56 44 240 26 ''
  $lblDlSearch = New-Label '搜索' 8 48 46
  $lblDlSearchTip = New-Label '输入即筛选，清空恢复全部' 300 48 300

  $lblDownList = New-Label '预览结果（只读，不会写文件）' 8 78 500
  $chkAll = New-Object System.Windows.Forms.CheckBox
  $chkAll.Text = ''
  $chkAll.AutoSize = $false
  $chkAll.Size = New-Object System.Drawing.Size(12, 12)
  $chkAll.Location = New-Object System.Drawing.Point(10, 108)
  $dlGrid = New-Object System.Windows.Forms.DataGridView
  $dlGrid.Location = New-Object System.Drawing.Point(8, 102)
  $dlGrid.Size = New-Object System.Drawing.Size(660, 190)
  $dlGrid.AllowUserToAddRows = $false
  $dlGrid.AllowUserToDeleteRows = $false
  $dlGrid.AllowUserToResizeRows = $false
  $dlGrid.AllowUserToResizeColumns = $false
  $dlGrid.RowHeadersVisible = $false
  $dlGrid.SelectionMode = 'FullRowSelect'
  $dlGrid.MultiSelect = $true
  $dlGrid.ReadOnly = $true
  $dlGrid.BorderStyle = 'FixedSingle'
  $dlGrid.CellBorderStyle = 'SingleHorizontal'
  $dlGrid.BackgroundColor = [System.Drawing.Color]::White
  $dlGrid.GridColor = [System.Drawing.Color]::FromArgb(229, 231, 235)
  $dlGrid.ColumnHeadersHeightSizeMode = 'DisableResizing'
  $dlGrid.ColumnHeadersHeight = 22
  $dlGrid.RowTemplate.Height = 22
  $dlGrid.Font = New-Object System.Drawing.Font('Microsoft YaHei UI', 9)
  $dlGrid.DefaultCellStyle.Padding = New-Object System.Windows.Forms.Padding(0)
  $dlGrid.ColumnHeadersDefaultCellStyle.Padding = New-Object System.Windows.Forms.Padding(2, 0, 0, 0)
  foreach ($c in @(@('游戏', 150), @('存档文件', 145), @('会还原到', 292), @('状态', 66))) {
    $col = New-Object System.Windows.Forms.DataGridViewTextBoxColumn
    $col.HeaderText = [string]$c[0]
    $col.Width = [int]$c[1]
    $col.SortMode = 'NotSortable'
    $col.ReadOnly = $true
    $col.DefaultCellStyle.Padding = New-Object System.Windows.Forms.Padding(0)
    if ([string]$c[0] -eq '游戏') { $col.HeaderCell.Style.Padding = New-Object System.Windows.Forms.Padding(14, 0, 0, 0) }
    [void]$dlGrid.Columns.Add($col)
  }

  $dlGrid.add_CellToolTipTextNeeded({
    param($s3, $e3)
    if ($e3.RowIndex -lt 0 -or $e3.ColumnIndex -lt 0) { return }
    $v = $dlGrid.Rows[$e3.RowIndex].Cells[$e3.ColumnIndex].Value
    if ($v) { $e3.ToolTipText = [string]$v }
  })

  $bodyDown.Controls.AddRange(@($btnPreview, $btnRestore, $btnClearBak, $lblDownTip,
      $tbDlSearch, $lblDlSearch, $lblDlSearchTip, $lblDownList, $dlGrid, $chkAll))
  $chkAll.BringToFront()

  # ---------- ④ 仓库 ----------
  $bodyRepo = New-Object System.Windows.Forms.Panel
  $bodyRepo.Location = New-Object System.Drawing.Point(206, 40)
  $bodyRepo.Size = New-Object System.Drawing.Size(680, 104)
  $bodyRepo.BackColor = $form.BackColor
  $tbRepo = New-Box 100 4 320 26 $cfg.repo
  $tbBranch = New-Box 100 36 140 26 $cfg.branch
  $tbToken = New-Box 100 68 320 26 $cfg.token
  $tbToken.UseSystemPasswordChar = $true
  $btnSave = New-Button '保存' 436 3 80 28
  $btnTest = New-Button '测试连接' 436 35 100 28
  $bodyRepo.Controls.AddRange(@((New-Label '用户名/仓库' 8 6 90), (New-Label '分支' 8 38 60), (New-Label 'Token' 8 70 60),
      $tbRepo, $tbBranch, $tbToken, $btnSave, $btnTest))

  foreach ($b in @($bodyFind, $bodyUp, $bodyDown, $bodyRepo)) { $form.Controls.Add($b) }

  # ---------- 未展开时的提示 ----------
  $placeholder = New-Label '点左边任意一项展开' 230 60 400 24
  $placeholder.ForeColor = [System.Drawing.Color]::FromArgb(150, 158, 168)
  $form.Controls.Add($placeholder)

  # ---------- 日志（固定在下方） ----------
  $log = New-Object System.Windows.Forms.RichTextBox
  $log.Location = New-Object System.Drawing.Point(206, 400)
  $log.Size = New-Object System.Drawing.Size(680, 200)
  $log.ReadOnly = $true
  $log.BackColor = [System.Drawing.Color]::White
  $log.Font = New-Object System.Drawing.Font('Consolas', 9)
  $log.BorderStyle = 'FixedSingle'
  $form.Controls.Add($log)

  $status = New-Label '就绪' 206 610 500
  $status.ForeColor = [System.Drawing.Color]::FromArgb(55, 65, 77)
  $form.Controls.Add($status)

  # ---------- 展开 / 收起 ----------
  function Apply-Active {
    $i = $script:Active
    $bodies = @($bodyFind, $bodyUp, $bodyDown, $bodyRepo)
    for ($k = 0; $k -lt $bodies.Count; $k++) {
      $on = ($k -eq $i)
      $bodies[$k].Visible = $on
      if ($on) {
        $railBtns[$k].Text = '▾   ' + $railNames[$k]
        $railBtns[$k].BackColor = [System.Drawing.Color]::FromArgb(229, 239, 252)
        $railBtns[$k].Font = New-Object System.Drawing.Font('Microsoft YaHei UI', 10, [System.Drawing.FontStyle]::Bold)
      } else {
        $railBtns[$k].Text = '▸   ' + $railNames[$k]
        $railBtns[$k].BackColor = [System.Drawing.Color]::White
        $railBtns[$k].Font = New-Object System.Drawing.Font('Microsoft YaHei UI', 10, [System.Drawing.FontStyle]::Regular)
      }
    }
    $placeholder.Visible = ($i -lt 0)
  }

  foreach ($b in $railBtns) {
    $b.Add_Click({
        $idx = [int]$this.Tag
        if ($script:Active -eq $idx) { $script:Active = -1 } else { $script:Active = $idx }
        Apply-Active
      })
  }

  function Write-Log([string]$text, [string]$kind = 'info') {
    $color = switch ($kind) {
      'ok' { [System.Drawing.Color]::FromArgb(30, 120, 60) }
      'err' { [System.Drawing.Color]::FromArgb(190, 40, 40) }
      'warn' { [System.Drawing.Color]::FromArgb(170, 110, 0) }
      default { [System.Drawing.Color]::FromArgb(60, 60, 60) }
    }
    $log.SelectionStart = $log.TextLength
    $log.SelectionColor = $color
    $log.AppendText(('[{0}] {1}{2}' -f (Get-Date -Format 'HH:mm:ss'), $text, [Environment]::NewLine))
    $log.SelectionColor = [System.Drawing.Color]::Black
    $log.ScrollToCaret()
    [System.Windows.Forms.Application]::DoEvents()
  }

  # ---------- 查找 ----------
  $script:FindHits = @()

  function Fill-Find($res) {
    $script:FindHits = @($res)
    $gdFind.SuspendLayout()
    $gdFind.Rows.Clear()
    $n = 0
    foreach ($h in $res) {
      foreach ($f in $h.SaveFiles) {
        $kb = [math]::Round($f.Length / 1KB, 0).ToString() + ' KB'
        $ri = $gdFind.Rows.Add(([string]$h.Game), ([string]$f.Name), $kb, ([string]$h.Path), '已找到')
        $gdFind.Rows[$ri].Tag = $h
        $n++
      }
    }
    $gdFind.ResumeLayout()
    if ($gdFind.Rows.Count -gt 0) { $gdFind.ClearSelection() }
    $chkFindAll.Checked = $false
    return $n
  }

  function Do-Search {
    $kw = $tbFindSearch.Text.Trim()
    if (-not $kw) { Write-Log '先输入游戏名' 'warn'; return }
    $gdFind.Rows.Clear()
    if (Test-Path -LiteralPath $kw -PathType Container) {
      $res = @(Find-InPath $kw)
      $n = Fill-Find $res
      if ($n -eq 0) { $status.Text = '这个目录里没文件，或路径不对。' }
      else { $status.Text = ('找到 ' + $res.Count + ' 个目录 / ' + $n + ' 个存档文件（指定目录）') }
      return
    }
    try {
      $cb = { param($root, $i, $total) $status.Text = ('正在搜索 ' + $i + '/' + $total + '：' + $root); [System.Windows.Forms.Application]::DoEvents() }
      $res = @(Find-GameDirs $kw (Get-SearchRoots) $cb)
      $n = Fill-Find $res
      if ($n -eq 0) {
        $status.Text = '没匹配到。点“列出全部候选”，或粘游戏安装目录，或用英文文件夹名。'
        Write-Log '没匹配到，试试“列出全部候选”' 'warn'
      } else {
        $status.Text = ('找到 ' + $res.Count + ' 个目录 / ' + $n + ' 个存档文件')
        Write-Log ('找到 ' + $n + ' 个存档文件（' + $res.Count + ' 个目录）') 'ok'
      }
    } catch { Write-Log ('搜索出错：' + $_.Exception.Message) 'err' }
  }

  $btnFind.Add_Click({ Do-Search })
  $tbFindSearch.Add_KeyDown({ if ($_.KeyCode -eq 'Enter') { Do-Search } })

  $btnCand.Add_Click({
    $btnCand.Enabled = $false; $btnFind.Enabled = $false
    $gdFind.Rows.Clear()
    try {
      $cb2 = { param($root, $i, $total) $status.Text = ('正在扫 ' + $i + '/' + $total + '：' + $root); [System.Windows.Forms.Application]::DoEvents() }
      $res = @(Find-AllCandidates (Get-SearchRoots) $cb2)
      $n = Fill-Find $res
      if ($n -eq 0) { $status.Text = '没扫到带存档后缀的目录。' }
      else { $status.Text = ('扫到 ' + $res.Count + ' 个目录 / ' + $n + ' 个存档文件（全部候选）') }
    } catch { Write-Log ('扫描出错：' + $_.Exception.Message) 'err' }
    $btnCand.Enabled = $true; $btnFind.Enabled = $true
  })

  $chkFindAll.Add_CheckedChanged({
    if ($chkFindAll.Checked) { $gdFind.SelectAll() } else { $gdFind.ClearSelection() }
  })

  $btnToUpload.Add_Click({
    $sel = @($gdFind.SelectedRows | ForEach-Object { $_.Tag } | Where-Object { $_ })
    if ($sel.Count -eq 0) { Write-Log '先在列表里选一行' 'warn'; return }
    $h = $sel[0]
    $tbGameUp.Text = $h.Game
    $tbDir.Text = $h.Path
    $lstFiles.Items.Clear()
    foreach ($f in $h.SaveFiles) { [void]$lstFiles.Items.Add($f.Name) }
    $script:Active = 1
    Apply-Active
    Write-Log ('已填入上传区：' + $h.Game + '（' + $h.SaveFiles.Count + ' 个文件）') 'ok'
  })

  # ---------- 下载：筛选 + 清除备份 ----------
  $script:DlPlan = @()

  function Fill-DlList {
    $kw = $tbDlSearch.Text.Trim().ToLower()
    $dlGrid.SuspendLayout()
    $dlGrid.Rows.Clear()
    $shown = 0
    foreach ($it in $script:DlPlan) {
      if ($kw) {
        $hay = (([string]$it.Game) + ' ' + ([string]$it.File) + ' ' + ([string]$it.Target)).ToLower()
        if (-not $hay.Contains($kw)) { continue }
      }
      $ri = $dlGrid.Rows.Add(([string]$it.Game), ([string]$it.File), ([string]$it.Target), ([string]$it.State))
      $dlGrid.Rows[$ri].Tag = $it
      $shown++
    }
    $dlGrid.ResumeLayout()
    $dlGrid.ClearSelection()
    if ($kw) { $status.Text = ('筛选出 {0} 条（共 {1} 条）' -f $shown, $script:DlPlan.Count) }
  }

  $tbDlSearch.Add_TextChanged({ Fill-DlList })

  $chkAll.Add_CheckedChanged({
    $n = $dlGrid.Rows.Count
    if ($chkAll.Checked) { $dlGrid.SelectAll() } else { $dlGrid.ClearSelection() }
    if ($n -eq 0) { return }
    if ($chkAll.Checked) { $status.Text = ('已全选 ' + $n + ' 条') }
    else { $status.Text = '已取消全部勾选（点开始还原会还原全部）' }
  })

  $btnClearBak.Add_Click({
    $root = $cfg.backup_dir
    if (-not $root) { $root = Join-Path $script:Root '备份' }
    $ans = [System.Windows.Forms.MessageBox]::Show(
      ('会删除这个文件夹里的全部备份：`r`n' + $root + '`r`n`r`n继续吗？').Replace('`r`n', [Environment]::NewLine),
      '清除备份', [System.Windows.Forms.MessageBoxButtons]::YesNo, [System.Windows.Forms.MessageBoxIcon]::Warning)
    if ($ans -ne 'Yes') { return }
    try {
      Clear-BackupFolder ([pscustomobject]@{ backup_dir = $root }) { param($t, $k) Write-Log $t $k } | Out-Null
      $status.Text = '备份已清空'
    } catch { Write-Log ('清除失败：' + $_.Exception.Message) 'err' }
  })

  # ---------- 仓库 / 上传 / 下载 ----------
  function Apply-Form-To-Cfg {
    $cfg.repo = $tbRepo.Text.Trim()
    $cfg.branch = $tbBranch.Text.Trim()
    if (-not $cfg.branch) { $cfg.branch = 'main' }
    $cfg.token = $tbToken.Text.Trim()
  }

  $btnSave.Add_Click({
    Apply-Form-To-Cfg
    Save-Config $cfg $script:CfgPath
    $status.Text = '配置已保存'
    Write-Log '配置已保存到 config.txt' 'ok'
  })

  $btnTest.Add_Click({
    Apply-Form-To-Cfg
    if (-not $cfg.repo) { Write-Log '先填 用户名/仓库名' 'err'; return }
    try {
      $status.Text = '连接中…'; [System.Windows.Forms.Application]::DoEvents()
      $tree = Get-Tree $cfg
      $n = ($tree | Where-Object { $_.type -eq 'blob' -and $_.path -match 'meta\.json$' }).Count
      Write-Log ('连接成功：仓库里有 {0} 个 meta.json' -f $n) 'ok'
      $status.Text = '已连接'
    } catch { Write-Log ('连接失败：' + $_.Exception.Message) 'err'; $status.Text = '连接失败' }
  })

  $btnDir.Add_Click({
    $dlg = New-Object System.Windows.Forms.FolderBrowserDialog
    $dlg.Description = '选择这个游戏的存档目录'
    if ($dlg.ShowDialog() -eq 'OK') { $tbDir.Text = $dlg.SelectedPath }
  })

  $btnPick.Add_Click({
    if (-not $tbDir.Text) { Write-Log '先选存档目录，再挑文件' 'warn'; return }
    $dlg = New-Object System.Windows.Forms.OpenFileDialog
    $dlg.InitialDirectory = $tbDir.Text
    $dlg.Multiselect = $true
    $dlg.Title = '选择要上传的存档文件'
    if ($dlg.ShowDialog() -eq 'OK') {
      $lstFiles.Items.Clear()
      foreach ($f in $dlg.FileNames) { [void]$lstFiles.Items.Add([System.IO.Path]::GetFileName($f)) }
      Write-Log ('选中 {0} 个文件' -f $dlg.FileNames.Count)
    }
  })

  $btnUpload.Add_Click({
    Apply-Form-To-Cfg
    $game = $tbGameUp.Text.Trim()
    $dir = $tbDir.Text.Trim()
    $sel = @($lstFiles.Items | ForEach-Object { "$_" })
    if (-not $cfg.repo) { Write-Log '先在“仓库连接”里填 用户名/仓库名' 'err'; return }
    if (-not $game) { Write-Log '游戏名不能空' 'err'; return }
    if (-not $dir -or -not (Test-Path -LiteralPath $dir)) { Write-Log '存档目录不存在' 'err'; return }
    if ($sel.Count -eq 0) { Write-Log '还没选存档文件' 'err'; return }
    try {
      $status.Text = '上传中…'; [System.Windows.Forms.Application]::DoEvents()
      Upload-Saves $cfg $game $dir $sel { param($t, $k) Write-Log $t $k }
      $cnt = Rebuild-Readme $cfg
      Write-Log ('README 已更新，共 {0} 行记录' -f $cnt) 'ok'
      $status.Text = '上传完成'
    } catch { Write-Log ('上传失败：' + $_.Exception.Message) 'err'; $status.Text = '上传失败' }
  })

  function Run-Download([bool]$dry) {
    Apply-Form-To-Cfg
    if (-not $cfg.repo) { Write-Log '先填 用户名/仓库名' 'err'; return }
    try {
      $status.Text = '读取仓库…'; [System.Windows.Forms.Application]::DoEvents()
      $tree = Get-Tree $cfg
      $plan = Build-Plan $cfg $tree
      if (-not $plan -or $plan.Count -eq 0) { Write-Log '仓库里没有 meta.json' 'warn'; $status.Text = '没有记录'; return }
      Write-Log ('共 {0} 条存档记录' -f $plan.Count)
      $script:DlPlan = @($plan)
      $chkAll.Checked = $false
      Fill-DlList

      $targets = $plan
      if (-not $dry) {
        $picked = @($dlGrid.SelectedRows | ForEach-Object { $_.Tag } | Where-Object { $_ })
        if ($picked.Count -gt 0) {
          $targets = $picked
          Write-Log ('按勾选还原：{0} 条' -f $picked.Count)
        } else {
          Write-Log ('没有勾选，按全部还原：{0} 条' -f @($plan).Count)
        }
      }

      $ok = 0; $bad = 0
      foreach ($it in $targets) {
        if ($it.State -ne '待下载') { Write-Log ($it.Game + ' / ' + $it.File + '：' + $it.State) 'warn'; continue }
        if ($dry) { Write-Log ('[预览] ' + $it.Game + '  ' + $it.File + '  →  ' + $it.Target); continue }
        try {
          $out = Download-Item $cfg $it
          Write-Log ('[完成] ' + $it.Game + '  ' + $it.File + '  →  ' + $out) 'ok'
          $ok++
        } catch { Write-Log ('[失败] ' + $it.Game + '  ' + $it.File + '：' + $_.Exception.Message) 'err'; $bad++ }
      }
      if (-not $dry) {
        $status.Text = ('成功 {0} 个，失败 {1} 个' -f $ok, $bad)
        Write-Log $status.Text ($(if ($bad -eq 0) { 'ok' } else { 'warn' }))
      } else { $status.Text = '预览完成' }
    } catch { Write-Log ('出错：' + $_.Exception.Message) 'err'; $status.Text = '出错' }
  }

  $btnPreview.Add_Click({ Run-Download $true })
  $btnRestore.Add_Click({ Run-Download $false })

  Apply-Active
  Write-Log '就绪。左边点“查找存档”搜游戏，搜到后点“填入上传区”。'
  if ($cfg.repo) { Write-Log ('当前仓库：' + $cfg.repo + '（' + $cfg.branch + '）') }

  [void]$form.ShowDialog()
}

if ($env:SR_SKIP_UI -ne '1') { Show-Gui }
