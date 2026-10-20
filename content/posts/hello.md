---
title: "第一篇文章"
date: 2026-01-01T00:00:00+08:00
draft: false
description: "这是一篇示例文章，用来验证 Hugo 构建、主题渲染和评论组件是否正常工作。"
tags: ["Hugo", "Cloudflare"]
categories: ["博客"]
---

这是你的第一篇博客文章。Hugo 会自动把它渲染成 HTML，推送到 `main` 分支后
GitHub Actions 会构建并部署到 Cloudflare Pages。

## 写作方式

文章就是普通的 Markdown 文件，放在 `content/posts/` 目录下。新建一篇：

```powershell
hugo new content posts/我的新文章.md
```

然后把 front matter 里的 `draft: true` 改成 `draft: false`，否则 Hugo 不会构建它。

## 插入图片

推荐把图片放在 `static/images/` 下，然后用绝对路径引用：

```markdown
![示意图](/images/demo.png)
```

`static/` 里的内容会原样复制到站点根目录，所以 `/images/demo.png` 在部署后可以直接访问。

## 本地预览

```powershell
hugo server --bind 0.0.0.0 --port 1313
```

打开 <http://localhost:1313> 就能看到实时预览，改文件会自动刷新。

## 检查清单

部署完成后，确认这几件事：

1. 首页能正常打开，样式没有丢失；
2. 这篇文章能点进来，代码块有高亮；
3. 文章底部的评论区正常显示；
4. 提交一条测试评论，没有 CORS 报错。
