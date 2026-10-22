# i4t.com RustDesk 客户端构建模板

这个仓库保留 RustDesk 与 RustDesk-on 的开源声明，并遵循 AGPL-3.0。

## 小白构建步骤

1. 在 i4t.com 的 RustDesk 客户端构建器中完成配置与预览。
2. 下载 `i4t-customization.zip`，不要解压或改名。
3. 把该文件上传到仓库根目录并提交；它应与 `.github` 目录同级。
4. 打开 `https://github.com/你的用户名/你的仓库/actions/workflows/flutter-nightly.yml`，点击 **Run workflow**。
5. 构建完成后，在该次运行的 Artifacts 或 Release 中下载客户端。

如果看到 **Choose a workflow**，请检查地址是否错误地以 `/actions/new` 结尾。不要点击 Configure，改为打开上面指定的 `flutter-nightly.yml` 地址。刚提交配置包时可等待 10–30 秒后刷新。

## Secrets 是否需要添加

首次构建建议完全不添加 Secrets。未签名不会影响 Logo、颜色、软件名、ID Server、Key、API Server 或 SSO，只会让操作系统对下载的程序显示“未知开发者”等安全提醒。

- Android 正式签名必须同时提供：`ANDROID_SIGNING_KEY`、`ANDROID_ALIAS`、`ANDROID_KEY_STORE_PASSWORD`、`ANDROID_KEY_PASSWORD`。
- macOS 签名与公证必须同时提供：`MACOS_P12_BASE64`、`MACOS_P12_PASSWORD`、`MACOS_CODESIGN_IDENTITY`、`MACOS_NOTARIZE_JSON`。
- Windows 的 `SIGN_BASE_URL` 与 `SIGN_SECRET_KEY` 只适用于兼容模板协议的自建签名服务，不是普通 PFX 证书字段；没有该服务时不要填写。

签名 Secrets 必须进入自己仓库的 **Settings → Secrets and variables → Actions → New repository secret** 添加。不要把证书、私钥或密码上传到 Code 页面。只填写一组中的部分字段可能导致对应平台的签名任务失败。

配置包不应包含代码签名证书、私钥、GitHub Token 或代理配置。构建脚本会校验配置包、固定源码标记与图片，并在任何不一致时终止构建。

Authentik/OIDC 的 Issuer、Client ID、回调地址和 Client Secret 应配置在 RustDesk Server/API；客户端配置包只控制是否显示 SSO 按钮、优先匹配的 Provider 名称和按钮文字。

上游源码：<https://github.com/abcdocker/RustDesk-on>  
原始项目：<https://github.com/rustdesk/rustdesk>  
许可证：AGPL-3.0
