# 部署手册（Windows → Cloudflare Pages）

**博客已经上线，评论功能已接通。** 剩余工作只有「推送到 GitHub」和
「配置 Actions 密钥」两步，见第 0 节。

下面的命令都在 **PowerShell** 中运行，工作目录为仓库根目录
（`C:\Users\Redmi\Codex\blog`）。

---

## 0. 当前状态

| 项目 | 值 |
|---|---|
| 线上地址 | <https://my-blog-t3l.pages.dev> |
| Pages 项目名 | `my-blog` |
| Cloudflare Account ID | `ed70a03909cfb104b44883190bab42d9` |
| Ziscus Worker | `https://ziscus-comments.gentle-math-b39e.workers.dev` |
| D1 数据库 | `ziscus-comments`（区域 WNAM，5 张表） |
| GitHub 仓库 | <https://github.com/Joker4845/Blog_Joker21a> |
| 本地 Hugo | 0.168.0 extended（`%USERPROFILE%\tools\hugo\`） |
| 主题 | Ananke v2.19.1（随仓库提交，非 submodule） |

实测结果：

```
hugo --minify --gc   → 18 pages, exit 0, 无警告
线上首页/文章页      → HTTP 200
线上评论表单         → 渲染正常，endpoint 与 slug 正确
CSS 完整性校验       → SRI 哈希与页面声明一致
GitHub Actions       → push 与 workflow_dispatch 均 success
D1 读写              → 写入 changes:1，读回记录正常
```

> **域名注意**：Pages 项目在控制台叫 `my-blog`，但实际域名是
> **`my-blog-t3l.pages.dev`** —— 因为 `my-blog` 子域已被他人占用。
> 凡涉及域名的地方（`baseURL`、Ziscus 的 `ALLOWED_ORIGINS`）
> 都必须用带 `-t3l` 的全名，否则提交评论会报 CORS 错误。

### 部署已全部完成

推送和 Actions 密钥都已配置好，**日常发布只剩改文章 + push**：

```powershell
cd C:\Users\Redmi\Codex\blog
# 写新文章：hugo new content posts/my-post.md
git add -A
git commit -m "post: 新文章"
git push
```

push 后 GitHub Actions 会自动构建并部署到 Cloudflare Pages，
约 1 分钟生效。也可以在仓库 **Actions → Deploy Hugo site to Cloudflare Pages
→ Run workflow** 手动触发。

当前已配置的仓库密钥：

| 类型 | 名称 | 状态 |
|---|---|---|
| Secret | `CLOUDFLARE_API_TOKEN` | ✅ 已配置 |
| Secret | `CLOUDFLARE_ACCOUNT_ID` | ✅ 已配置 |
| Variable | `BLOG_PROJECT_NAME` | ✅ `my-blog` |

> `BLOG_PROJECT_NAME` **必须是 Variable**，不是 Secret —— 工作流读的是
> `${{ vars.BLOG_PROJECT_NAME }}`，放进 Secrets 会读不到。

### ⚠️ 务必现在做：备份管理员密钥

密钥已保存在本地 `.env`（已被 git 忽略），并已写入 Cloudflare 的
`ADMIN_SECRET`。**Cloudflare 的密钥是只写的，写入后无法再读取**，
所以请立刻复制到密码管理器：

```powershell
Get-Content C:\Users\Redmi\Codex\blog\.env
```

### ⚠️ 另外建议：吊销对话中暴露过的凭据

本次搭建过程中，Cloudflare API Token 和 GitHub Token 都在对话里出现过，
建议部署稳定后到各自控制台**删除并重新生成**：

- Cloudflare：My Profile → API Tokens → Roll / Delete
- GitHub：Settings → Developer settings → Personal access tokens → Delete

重新生成后，把新值更新到仓库 Secrets 即可，站点本身不受影响。

审核评论：

```powershell
cd C:\Users\Redmi\Codex\blog
npx ziscus dashboard
```

---

## 1. Hugo 安装（已完成，此处仅存档）

**本机的 `winget` 是坏的** —— 任何子命令都返回 `0x8A150001` 内部错误，
连 `winget --version` 都不行。如果以后想修，可以试：

- 「设置 → 应用 → 应用和功能」找到 **App Installer** → 高级选项 → 修复 / 重置；
- 或以管理员身份运行 PowerShell：
  ```powershell
  Get-AppxPackage *DesktopAppInstaller* | Reset-AppxPackage
  ```

**已经装好的 Hugo 在当前版本**（无需重装）：

```powershell
hugo version
# hugo v0.168.0+extended windows/amd64
```

若将来要重装或升级，手动下载是唯一可靠方式：

1. 打开 <https://github.com/gohugoio/hugo/releases>；
2. 下载 **`hugo_extended_<版本>_windows-amd64.zip`**；
   **必须带 `extended`** —— 普通版没有 SCSS 支持，Ananke 会直接无法渲染样式；
3. 解压后把 `hugo.exe` 放到 `C:\Users\<用户名>\tools\hugo\`；
4. 该目录已在用户 PATH 中，重开终端即可生效。

> **版本下限**：Ananke v2 的 `theme.toml` 要求 `min_version = "0.160.0"`。
> 低于这个版本会构建失败，不要降级。

## 2. 主题（已完成，此处仅存档）

主题**不是** git submodule，而是把 Ananke v2.19.1 的发行版解压进
`themes\ananke\` 并随仓库提交（约 1.2 MB）。

这样做的原因：本机 git 到 `github.com:443` 的连接会被重置，`git submodule add`
克隆不下来；而 `codeload.github.com` 可用。更重要的是，submodule 会让 CI 多一个
失败点（忘了 `submodules: recursive`、或 GitHub 临时抽风就构建不出来），
直接提交进去最稳。

将来升级主题：

```powershell
curl.exe -L -o ananke.tar.gz https://codeload.github.com/gohugo-ananke/ananke/tar.gz/refs/tags/v2.19.1
tar.exe -xzf ananke.tar.gz
# 用解压出的目录内容替换 themes\ananke\
```

**注意**：Ananke v2 用的是 Hugo 新版目录规范 —— `layouts/_partials/`
（带下划线），不是旧的 `layouts/partials/`。放错位置不会被加载，且不报错。

## 3. 本地构建验证

```powershell
hugo --minify --gc
```

产物在 `public\`。本地预览：

```powershell
hugo server --port 1313
```

打开 <http://localhost:1313> 检查首页和示例文章。

---

## 4. Cloudflare 凭证

```powershell
$env:CLOUDFLARE_API_TOKEN  = "你的 API Token"
$env:CLOUDFLARE_ACCOUNT_ID = "你的 Account ID"
```

Token 权限至少需要：

- **Cloudflare Pages: Edit**（部署站点）
- **Workers & Pages: Edit**（Ziscus 要创建 D1 数据库和 Worker）
- **D1: Edit**

## 5. 创建 Pages 项目

```powershell
$env:BLOG_PROJECT_NAME = "my-blog"      # 换成你想要的名字
npx wrangler pages project create $env:BLOG_PROJECT_NAME --production-branch main
```

记下输出的域名 `https://<项目名>.pages.dev`，后面要用。

## 6. 部署 Ziscus 评论

```powershell
npm init -y
npm install -D ziscus wrangler

npx wrangler login
npx ziscus deploy --site-url "https://$env:BLOG_PROJECT_NAME.pages.dev" --ssg hugo --github-repo "你的用户名/仓库名"
```

`--site-url` 用真实的 `*.pages.dev` 域名，**不要加通配符、不要带路径**。
`--github-repo` 让 Ziscus 在评论审核通过后通过 `repository_dispatch` 触发重新构建 ——
因为 Ziscus 是**构建时渲染**评论的，不重建就不会显示新评论。

### 6.1 接入评论模板

`npx ziscus deploy --ssg hugo` 会生成一段模板片段。**以 CLI 实际生成的为准**，
把它粘贴到下面这个文件里：

```
layouts\_partials\commento.html
```

> **路径很重要，别写错。** Ananke v2 用的是 Hugo 新版目录规范
> **`layouts/_partials/`**（带下划线），不是旧的 `layouts/partials/`。
> 放到旧路径不会有任何效果，而且**不报错**，只是评论区静默消失。

**为什么覆盖的是 `commento.html` 而不是 `comments.html`：**
主题的 `layouts/page/single.html` 里写死了：

```go-html-template
{{ if .Site.Params.commentoEnable }}
  {{- partials.Include "commento.html" . -}}
{{ end }}
```

主题只认这个名字。Hugo 的查找顺序是「站点 `layouts/` 优先于主题 `layouts/`」，
所以在站点侧放同名文件即可覆盖主题自带的 Commento 实现，
既不用改主题源码，也不用维护 fork。

粘贴片段后，把 `hugo.toml` 里两处开关都打开：

```toml
commentoEnable = true          # Ananke 的开关，控制是否渲染评论区

[params.ziscus]
  enabled = true
  api_url = "ziscus.<你的子域>.workers.dev"   # 不带 https://
```

改完先本地验证：`hugo server`，确认文章底部出现评论框，再推送。

### 6.2 检查 ALLOWED_ORIGINS

打开生成的 `wrangler.toml`：

```toml
[vars]
ALLOWED_ORIGINS = "my-blog.pages.dev"
```

必须**精确等于** Pages 主机名：不带 `https://`、不带路径、不带通配符。
写错的表现是提交评论时报 CORS 错误。

### 6.3 保存管理员凭证

```powershell
npx ziscus dashboard
```

输出的 Bearer token 保存到密码管理器。**不要提交进仓库**
（`.gitignore` 已排除 `.env` 和 `.dev.vars`）。

---

## 7. 推送到 GitHub

先在 GitHub 网页上创建一个**空仓库**（不要勾选 README / .gitignore），然后：

```powershell
$env:GITHUB_REPO = "你的用户名/仓库名"

git add -A
git commit -m "init: Hugo blog with Ziscus comments"
git remote add origin "https://github.com/$env:GITHUB_REPO.git"
git push -u origin main
```

### 7.1 配置 Secrets

```powershell
gh secret set CLOUDFLARE_API_TOKEN  --body $env:CLOUDFLARE_API_TOKEN
gh secret set CLOUDFLARE_ACCOUNT_ID --body $env:CLOUDFLARE_ACCOUNT_ID
gh variable set BLOG_PROJECT_NAME   --body $env:BLOG_PROJECT_NAME
```

本机**没有安装 `gh`**。要么先 `winget install GitHub.cli`（winget 已损坏，需手动装），
要么直接在网页上操作：仓库 **Settings → Secrets and variables → Actions**，
添加上面两个 Secret 和那个 Variable。

> `BLOG_PROJECT_NAME` 必须是 **Variable** 而不是 Secret —— 工作流里用的是
> `${{ vars.BLOG_PROJECT_NAME }}`，放到 Secrets 里读不到。

---

## 8. 推送后的验证清单

```powershell
gh run list --limit 5
gh run watch
```

部署成功后依次确认：

1. `https://<项目名>.pages.dev` 首页能打开，**样式正常**（样式全丢通常是 submodule 没拉下来）；
2. 示例文章能点进去，代码块有高亮；
3. 文章底部显示评论框；
4. 提交一条测试评论，**没有 CORS / 403 报错**（有的话回头查 `ALLOWED_ORIGINS`）；
5. 用 `npx ziscus dashboard` 审核这条评论，确认它触发了重新构建并最终显示出来。

---

## 9. 日常写作

```powershell
hugo new content posts/文章标题.md
# 编辑 content\posts\文章标题.md，把 draft 改成 false
git add -A
git commit -m "post: 文章标题"
git push
```

不需要手动跑 `hugo` 或 `wrangler`，GitHub Actions 会自动构建部署。
图片放 `static\images\`，用 `/images/xxx.png` 引用。

---

## 10. 排错

| 症状 | 原因与处理 |
|---|---|
| `winget` 任何命令都失败 | 本机 winget 已损坏（`0x8A150001`）；见第 1 节的修复方法，Hugo 改用手动下载安装 |
| `hugo` 找不到命令 | PATH 未刷新；关闭重开 PowerShell。Hugo 已在 `%USERPROFILE%\tools\hugo\` |
| 构建报 `min_version` 错误 | Hugo 版本低于 0.160.0（Ananke v2 的下限）；升级 Hugo |
| 线上样式全丢 / SCSS 报错 | 装成了非 extended 版 Hugo；必须是 `extended` |
| 评论区完全不出现 | 模板放错目录了。必须是 **`layouts\_partials\commento.html`**（带下划线），不是 `layouts\partials\comments.html`。放错不报错 |
| 评论区不出现（模板已放对） | `hugo.toml` 里 `commentoEnable` 和 `params.ziscus.enabled` **两个**都要为 `true` |
| `git submodule` 拉不下来 | 本机到 `github.com:443` 会被重置；主题已改为随仓库提交，不需要 submodule |
| `npm install -g` 报 `EACCES`/`EPERM` | 全局目录权限受限；改 prefix 到用户目录，或直接用 `npx` |
| 图片裂开 / 损坏 | 历史提交里被 CRLF 转换过；见下方「换行符」一节 |
| `wrangler pages deploy` 权限不足 | Token 缺 `Cloudflare Pages: Edit`，或 `CLOUDFLARE_ACCOUNT_ID` 没设 |
| 评论提交 CORS 报错 | `ALLOWED_ORIGINS` 必须精确等于 `*.pages.dev` 主机名，不带协议/路径/通配符 |
| 新评论不显示 | Ziscus 是构建时渲染；确认 `--github-repo` 配好且能触发 `repository_dispatch` |
| 构建报 Hugo 版本相关错误 | 工作流里 Hugo 版本是**固定**的（`0.168.0`）；与本地保持一致再改 |

### 关于换行符（重要）

本仓库已设置 `core.autocrlf=false` 和 `.gitattributes`，**新提交的文件不会再被转换**。

但如果你从别处拷入了已经被 CRLF 转换过的图片，需要重建索引：

```powershell
git add --renormalize .
git commit -m "chore: renormalize line endings"
```

验证某个文件是否干净：

```powershell
git ls-files --eol static/images
```

输出里 `i/lf` 表示索引中已是 LF。对 `*.png` 之类的二进制文件，
对应字段应显示 `-text`。

---

## 11. 安全提醒

- `CLOUDFLARE_API_TOKEN`、Ziscus 的 Bearer token、`wrangler.toml` 里可能出现的密钥
  **都不要提交进仓库**。`.gitignore` 已覆盖常见情况，但提交前仍建议 `git status` 看一眼。
- `hugo.toml` 里 `markup.goldmark.renderer.unsafe = true` 允许 Markdown 中直接写 HTML。
  自己写博客很方便，但**不要**把这个能力暴露给不受信任的投稿者。
