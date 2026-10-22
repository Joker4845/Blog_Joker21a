<#
.SYNOPSIS
  新建一篇博客文章（可带图片），并一键发布到线上。

.DESCRIPTION
  做三件事：
    1. 在 content/<分类>/<slug>/ 下创建 index.md（文章文件夹形式）
    2. 把指定的图片复制进同一个文件夹，并在正文末尾生成 Markdown 插图语法
    3. git add / commit / push，触发 GitHub Actions 自动部署

  为什么用「文章文件夹」而不是单个 .md 文件：
  图片和文章放在一起，Markdown 里写相对路径 ![说明](pic.png) 就行，
  不需要关心 URL 前缀。整个文件夹一起移动/改名，图片也不会断链。

  如果运行时提示「无法加载，因为在此系统上禁止运行脚本」，用：
    powershell -ExecutionPolicy Bypass -File .\new-post.ps1 ...

.PARAMETER Category
  分类目录名，通常是 tech（技术文章）或 essays（随笔）。
  也可以用别的名字，脚本会自动创建对应目录。

.PARAMETER Title
  文章标题。slug 默认由它生成。

.PARAMETER Slug
  可选。URL 里用的英文短名，比如 my-first-post。
  不填就从 Title 生成（中文标题会生成拼音风格的回退名，建议中文标题时手动指定）。

.PARAMETER Images
  可选。一张或多张图片的路径。支持通配符，比如 .\screenshots\*.png

.PARAMETER Tags
  可选。标签，逗号分隔，比如 "Hugo,Cloudflare"

.PARAMETER NoPush
  可选。只创建文件并提交，不推送（用于先本地预览）。

.PARAMETER NoCommit
  可选。只创建文件，不提交也不推送。

.EXAMPLE
  # 最简单的技术文章
  .\new-post.ps1 tech "Hugo 图片处理" -Slug hugo-images

.EXAMPLE
  # 带一张图片的随笔
  .\new-post.ps1 essays "周末爬山" -Slug weekend-hike -Images .\pic.jpg

.EXAMPLE
  # 带多张图片 + 标签
  .\new-post.ps1 tech "D1 性能调优" -Slug d1-perf -Images .\a.png,.\b.png -Tags "Cloudflare,D1"

.EXAMPLE
  # 用通配符一次带入整个文件夹的图
  .\new-post.ps1 tech "部署实录" -Slug deploy-log -Images .\shots\*.png -NoPush

.NOTES
  本文件必须保存为 UTF-8 **带 BOM**。Windows PowerShell 5.1 在没有 BOM 时
  会按系统 ANSI 代码页（中文系统上是 GBK）解读 .ps1，中文注释会变成乱码并
  导致语法错误。用记事本「另存为」时选「UTF-8 带 BOM」，或在 pwsh 7 下编辑。
#>

[CmdletBinding()]
param(
  [Parameter(Mandatory = $true, Position = 0)]
  [string]$Category,

  [Parameter(Mandatory = $true, Position = 1)]
  [string]$Title,

  [string]$Slug,
  [string[]]$Images,
  [string]$Tags,
  [switch]$NoPush,
  [switch]$NoCommit
)

$ErrorActionPreference = 'Stop'

# Always operate from the repository root, no matter where the user invoked us.
$RepoRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $RepoRoot

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

function Write-Step($msg) { Write-Host "  $msg" -ForegroundColor Cyan }
function Write-Ok($msg)   { Write-Host "  ✓ $msg" -ForegroundColor Green }
function Write-Warn2($msg){ Write-Host "  ! $msg" -ForegroundColor Yellow }

# Turn a title into a URL-safe slug. Chinese has no meaningful ASCII form, so
# when the title is mostly non-ASCII we fall back to a date-based name and tell
# the user to pass -Slug explicitly.
function New-Slug([string]$text) {
  $ascii = $text -replace '[^\x20-\x7E]', ''
  $s = $ascii.ToLowerInvariant()
  $s = $s -replace '[^a-z0-9]+', '-'
  $s = $s.Trim('-')
  if ($s.Length -lt 2) {
    return "post-$((Get-Date).ToString('yyyyMMdd-HHmmss'))"
  }
  return $s
}

function Get-GitPath {
  # git is on PATH, but a fresh shell may not have the user PATH composed.
  $cmd = Get-Command git -ErrorAction SilentlyContinue
  if ($cmd) { return $cmd.Source }
  $candidates = @(
    "$env:ProgramFiles\Git\cmd\git.exe",
    "${env:ProgramFiles(x86)}\Git\cmd\git.exe",
    "$env:LOCALAPPDATA\Programs\Git\cmd\git.exe"
  )
  foreach ($c in $candidates) { if (Test-Path $c) { return $c } }
  throw "找不到 git，请确认已安装并在 PATH 中。"
}

$Git = Get-GitPath

# ---------------------------------------------------------------------------
# 1. Work out the target folder
# ---------------------------------------------------------------------------

if ([string]::IsNullOrWhiteSpace($Slug)) {
  $Slug = New-Slug $Title
  if ($Title -notmatch '^[\x20-\x7E]+$') {
    Write-Warn2 "标题含中文，自动生成了 slug：$Slug"
    Write-Warn2 "如果想用更好记的英文地址，下次加 -Slug your-english-name"
  }
}
$Slug = $Slug.Trim().ToLowerInvariant()

$SectionDir = Join-Path $RepoRoot "content\$Category"
$PostDir    = Join-Path $SectionDir $Slug
$IndexFile  = Join-Path $PostDir 'index.md'

if (Test-Path $PostDir) {
  throw "已存在：content/$Category/$Slug/  —— 换个 -Slug，或先删掉那个文件夹。"
}

Write-Host ""
Write-Host "新建文章" -ForegroundColor White
Write-Step "分类：$Category"
Write-Step "标题：$Title"
Write-Step "地址：/$Category/$Slug/"

New-Item -ItemType Directory -Force -Path $PostDir | Out-Null

# ---------------------------------------------------------------------------
# 2. Copy images and build the Markdown for them
# ---------------------------------------------------------------------------

$imageMarkdown = @()
if ($Images) {
  # Resolve wildcards and relative paths against the ORIGINAL working directory,
  # because we already moved to the repo root.
  $resolved = @()
  foreach ($pattern in $Images) {
    $items = Get-ChildItem -Path $pattern -File -ErrorAction SilentlyContinue
    if ($items) { $resolved += $items }
    else { Write-Warn2 "找不到图片，已跳过：$pattern" }
  }

  $used = @{}
  foreach ($img in $resolved) {
    $name = $img.Name
    # Avoid silently overwriting when two source files share a name.
    if ($used.ContainsKey($name)) {
      $base = [System.IO.Path]::GetFileNameWithoutExtension($name)
      $ext  = $img.Extension
      $n = 2
      while ($used.ContainsKey("$base-$n$ext")) { $n++ }
      $name = "$base-$n$ext"
    }
    $used[$name] = $true

    Copy-Item $img.FullName (Join-Path $PostDir $name) -Force
    # Relative path: resolves to /<category>/<slug>/<name> after the build.
    $imageMarkdown += "![$([System.IO.Path]::GetFileNameWithoutExtension($name))]($name)"
    Write-Ok "图片：$name"
  }
}

# ---------------------------------------------------------------------------
# 3. Write index.md
# ---------------------------------------------------------------------------

$tagLine = ''
if ($Tags) {
  $tagList = ($Tags -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ }) |
             ForEach-Object { '"' + ($_ -replace '"', '') + '"' }
  if ($tagList) { $tagLine = "tags: [" + ($tagList -join ', ') + "]" }
}

$date = (Get-Date).ToString('yyyy-MM-ddTHH:mm:sszzz')

# UTF-8 WITHOUT BOM: Hugo tolerates a BOM, but it also ends up inside the
# rendered front matter and can break strict YAML parsers.
$frontMatter = @"
---
title: "$Title"
date: $date
draft: true
description: ""
$tagLine
---

在这里写正文。

"@

$body = $frontMatter
if ($imageMarkdown.Count -gt 0) {
  $body += ($imageMarkdown -join "`n`n")
  $body += "`n"
}

# Write UTF-8 without BOM and with LF endings, matching the repo's
# `.gitattributes` rule (`* text=auto eol=lf`). PowerShell here-strings use the
# platform newline, which is CRLF on Windows, so normalise before writing;
# otherwise git warns about CRLF on every single new post.
$body = $body -replace "`r`n", "`n"

$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText($IndexFile, $body, $utf8NoBom)
Write-Ok "文章：content/$Category/$Slug/index.md"

# ---------------------------------------------------------------------------
# 4. Commit and push
# ---------------------------------------------------------------------------

if ($NoCommit) {
  Write-Host ""
  Write-Host "已创建（未提交）。编辑好后手动提交：" -ForegroundColor White
  Write-Host "  cd $RepoRoot"
  Write-Host "  git add -A; git commit -m `"post: $Title`"; git push"
  Write-Host ""
  Write-Host "本地预览： hugo server" -ForegroundColor White
  return
}

# The draft flag must be flipped before it will appear on the site, so warn
# rather than publish a draft that silently does nothing.
$draftNote = ''
if ($body -match '(?m)^draft:\s*true') {
  $draftNote = "（仍是 draft，需改成 false 才会发布）"
}

Push-Location $RepoRoot
try {
  # git writes progress and warnings to stderr even when it succeeds, and
  # PowerShell turns native stderr into a red NativeCommandError. Route the
  # streams into the pipeline and trust the exit code instead.
  & $Git add -A 2>&1 | Out-Null
  $msg = "post: $Title"
  & $Git -c user.name="blog" -c user.email="blog@local" commit -q -m $msg 2>&1 | Out-Null
  $committed = ($LASTEXITCODE -eq 0)
  if (-not $committed) {
    Write-Warn2 "没有可提交的改动（内容与上次相同）"
  } else {
    Write-Ok "已提交 $draftNote"
  }

  if (-not $NoPush) {
    Write-Step "推送中…"
    $ok = $false
    for ($i = 1; $i -le 6; $i++) {
      $ErrorActionPreference = 'Continue'
      & $Git push origin main 2>&1 | Out-Null
      if ($LASTEXITCODE -eq 0) { $ok = $true; break }
      # github.com occasionally resets the connection mid-transfer; retry.
      Start-Sleep -Seconds 6
    }
    if ($ok) {
      Write-Ok "已推送，GitHub Actions 会自动部署（约 1 分钟）"
      Write-Host "     https://my-blog-t3l.pages.dev/$Category/$Slug/" -ForegroundColor White
    } else {
      Write-Warn2 "推送失败（网络问题）。稍后手动重试： git push origin main"
    }
  }
} finally {
  Pop-Location
}

Write-Host ""
