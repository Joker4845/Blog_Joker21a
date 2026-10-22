---
title: "用 Hugo + Cloudflare Pages 搭建这个博客"
date: 2026-01-01T00:00:00+08:00
draft: false
description: "记录这套博客是怎么搭起来的：Hugo 构建、Cloudflare Pages 部署、Ziscus 评论跑在 D1 上。"
tags: ["Hugo", "Cloudflare", "D1"]
categories: ["技术"]
---

这篇记录一下这个博客的搭建过程，方便以后回看，也方便想照着搭的人少踩点坑。

## 整体架构

```
本地 Markdown
   ↓  git push
GitHub Actions  ──构建──→  Cloudflare Pages（静态站点）
                              ↑
                        评论区 AJAX 读取
                              ↓
                    Cloudflare Worker + D1（评论存储）
```

站点本身是纯静态的，评论单独跑在一个 Worker 上，数据存在 D1 里。
这样静态页面保持简单，评论又能实时更新，不用每次有人留言就重新构建。

## 写文章

文章放在 `content/tech/`（技术文章）或 `content/essays/`（随笔）下。
新建一篇：

```powershell
hugo new content tech/my-new-post.md
```

然后把 front matter 里的 `draft: true` 改成 `draft: false`，
否则 Hugo 不会构建它。

## 插入图片

把图片放在 `static/images/` 下，用绝对路径引用：

```markdown
![示意图](/images/demo.png)
```

`static/` 里的内容会原样复制到站点根目录，所以部署后 `/images/demo.png` 可直接访问。

## 本地预览

```powershell
hugo server
```

打开 <http://localhost:1313> 就能看到实时预览，改文件会自动刷新。

## 发布

```powershell
git add -A
git commit -m "post: 新文章"
git push
```

推送后 GitHub Actions 会自动构建并部署，大约一分钟生效。
