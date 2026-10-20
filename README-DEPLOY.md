# 部署手册（Windows → Cloudflare Pages）

本仓库已经是一个完整的 Hugo 站点骨架。**只差需要联网 / 需要你账号权限的几步**，
按下面的顺序执行即可上线。

下面的命令都在 **PowerShell** 中运行，工作目录为仓库根目录
（`C:\Users\Redmi\Codex\blog`）。

---

## 0. 当前状态

已完成：

- `hugo.toml` —— 站点配置（中文、Ananke 主题、标签/分类）
- `.gitattributes` —— 强制 LF + 二进制文件保护
- `.gitignore` —— 排除 `public/`、`node_modules/`、密钥
- `content/posts/hello.md` —— 示例文章
- `layouts/partials/comments.html` —— 评论区占位模板（当前渲染为空）
- `.github/workflows/deploy.yml` —— 自动构建部署工作流
- 本地 git 仓库已初始化，分支 `main`，`core.autocrlf=false`

未完成（需要网络或你的凭证）：

- 安装 Hugo
- 添加 Ananke 主题
- 创建 Cloudflare Pages 项目
- 部署 Ziscus 评论系统
- 推送到 GitHub

---

## 1. 安装 Hugo Extended

**不要用 `winget`。** 本机实测 `winget` 无法工作（任何子命令都返回
`0x8A150001` 内部错误，包括 `winget --version`），属于 winget 自身损坏，
与本项目无关。

改用**手动下载**（最有把握，且不需要管理员权限）：

1. 打开 <https://github.com/gohugoio/hugo/releases>；
2. 找最新版的 **`hugo_extended_<版本>_windows-amd64.zip`**；
   **必须选带 `extended` 的那个** —— 普通版缺少 SCSS 支持，Ananke 会用不了；
3. 解压到一个固定目录，例如 `C:\Users\<你的用户名>\tools\hugo\`；
4. 把该目录加入**用户** PATH（不需要管理员）：

```powershell
$hugoDir = "$env:USERPROFILE\tools\hugo"
New-Item -ItemType Directory -Force -Path $hugoDir | Out-Null
# 把 hugo.exe 解压到 $hugoDir 之后执行：
$userPath = [Environment]::GetEnvironmentVariable("Path", "User")
if ($userPath -notlike "*$hugoDir*") {
    [Environment]::SetEnvironmentVariable("Path", "$userPath;$hugoDir", "User")
}
$env:Path = "$env:Path;$hugoDir"   # 当前窗口立即生效
hugo version
```

`hugo version` 的输出里必须包含 **`extended`** 字样。

> 备选：`npm install -g hugo-extended`（Node 已装，本机 `v24.20.0`）。
> 这条路可行但**本次未能实际验证**（离线环境无法确认包状态），
> 如果报 `EACCES` / `EPERM`，改用用户目录作为全局 prefix：
>
> ```powershell
> npm config set prefix "$env:APPDATA\npm-global"
> $env:Path = "$env:APPDATA\npm-global;$env:Path"
> npm install -g hugo-extended
> ```

## 2. 添加 Ananke 主题

主题以 git submodule 形式引入，这样 GitHub Actions 的
`submodules: recursive` 才能拉到它：

```powershell
git submodule add https://github.com/gohugo-ananke/ananke themes/ananke
```

Hugo 主题在 submodule 里**不要**加 `.gitattributes` 覆盖规则，本仓库根目录的
规则已经够用。

## 3. 本地构建验证

```powershell
hugo --minify --gc
```

产物在 `public\`。本地预览：

```powershell
hugo server --bind 0.0.0.0 --port 1313
```

打开 <http://localhost:1313> 检查首页和示例文章。**这一步必须先通过**，
再去动 Cloudflare，否则线上出问题很难定位是构建还是部署的锅。

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
把它覆盖写入：

```
layouts\partials\comments.html
```

不要手写猜测 Ziscus 的渲染逻辑 —— 写错通常不报错，只是评论区静默消失。
覆盖后把 `hugo.toml` 里的开关打开：

```toml
[params.ziscus]
  enabled = true
  api-url = "ziscus.<你的子域>.workers.dev"
```

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
| `winget` 任何命令都失败 | 本机 winget 已损坏（`0x8A150001`）；改用 npm 安装 Hugo |
| `hugo` 找不到命令 | PATH 未刷新；关闭重开 PowerShell，或手动把 `hugo.exe` 目录加入用户 PATH |
| `npm install -g` 报 `EACCES`/`EPERM` | 全局目录权限受限；按第 1 节改 prefix 到用户目录，或直接用 `npx` |
| 线上样式全丢 | submodule 没拉下来；确认 checkout 步骤有 `submodules: recursive`，以及主题已提交 |
| 图片裂开 / 损坏 | 历史提交里被 CRLF 转换过；见下方「换行符」一节 |
| `wrangler pages deploy` 权限不足 | Token 缺 `Cloudflare Pages: Edit`，或 `CLOUDFLARE_ACCOUNT_ID` 没设 |
| 评论提交 CORS 报错 | `ALLOWED_ORIGINS` 必须精确等于 `*.pages.dev` 主机名，不带协议/路径/通配符 |
| 新评论不显示 | Ziscus 是构建时渲染；确认 `--github-repo` 配好且能触发 `repository_dispatch` |
| 构建报 Hugo 版本相关错误 | 工作流里 Hugo 版本是**固定**的（`0.140.2`），可手动升级这一行 |

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
