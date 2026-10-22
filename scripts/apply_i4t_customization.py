#!/usr/bin/env python3
"""Apply an i4t.com customization archive to the pinned RustDesk-on source tree."""

from __future__ import annotations

import base64
import hashlib
import io
import json
import re
import sys
import zipfile
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
EXPECTED_SOURCE_COMMIT = "5f358984defeadd007154786f1ef208ac459b325"


class CustomizationError(RuntimeError):
    pass


def read_text(relative: str) -> str:
    return (ROOT / relative).read_text(encoding="utf-8")


def write_text(relative: str, content: str) -> None:
    (ROOT / relative).write_text(content, encoding="utf-8")


def replace_exact(relative: str, old: str, new: str, minimum: int = 1) -> None:
    content = read_text(relative)
    count = content.count(old)
    if count < minimum:
        raise CustomizationError(
            f"{relative}: expected at least {minimum} occurrence(s) of the pinned source marker, found {count}"
        )
    write_text(relative, content.replace(old, new))


def dart_color(value: str) -> str:
    if not re.fullmatch(r"#[0-9A-Fa-f]{6}", value or ""):
        raise CustomizationError(f"Invalid color: {value!r}")
    return "0xFF" + value[1:].upper()


def dart_quote(value: str) -> str:
    return value.replace("\\", "\\\\").replace("'", "\\'").replace("\n", " ").replace("\r", " ")


def rust_quote(value: str) -> str:
    return json.dumps(value, ensure_ascii=False)


def validate_config(config: dict) -> None:
    enabled = config.get("enabled", {})
    values = config.get("values", {})
    label = re.compile(r"[\w .()+-]+", re.UNICODE)
    if enabled.get("appName") and not (1 <= len(values.get("appName", "")) <= 28 and label.fullmatch(values["appName"])):
        raise CustomizationError("Application name contains unsupported characters or is too long")
    if enabled.get("deploymentNames"):
        for key in ("installerName", "serviceName"):
            if not (1 <= len(values.get(key, "")) <= 48 and label.fullmatch(values[key])):
                raise CustomizationError(f"{key} contains unsupported characters or is too long")
        if not re.fullmatch(r"[A-Za-z][A-Za-z0-9._-]{0,31}", values.get("executableName", "")):
            raise CustomizationError("Invalid executableName")
        if not re.fullmatch(r"[A-Za-z][A-Za-z0-9_]*(?:\.[A-Za-z][A-Za-z0-9_]*)+", values.get("packageId", "")):
            raise CustomizationError("Invalid packageId")
    if enabled.get("serverConfig"):
        if not re.fullmatch(r"[A-Za-z0-9.-]+(?::\d{1,5})?", values.get("idServer", "")):
            raise CustomizationError("Invalid ID Server")
        relay = values.get("relayServer", "")
        if relay and not re.fullmatch(r"[A-Za-z0-9.-]+(?::\d{1,5})?", relay):
            raise CustomizationError("Invalid Relay Server")
        if not re.fullmatch(r"https://[^\s'\"<>]+", values.get("apiServer", ""), re.IGNORECASE):
            raise CustomizationError("API Server must use HTTPS")
        if not re.fullmatch(r"[A-Za-z0-9_+/=-]{16,256}", values.get("serverKey", "")):
            raise CustomizationError("Invalid server public key")
    if enabled.get("welcomeText") and (not values.get("welcomeText") or len(values["welcomeText"]) > 42 or "\n" in values["welcomeText"]):
        raise CustomizationError("Invalid welcome text")


def parse_archive(archive_path: Path) -> tuple[dict, zipfile.ZipFile]:
    if not archive_path.is_file():
        raise CustomizationError(f"Customization archive not found: {archive_path}")
    archive = zipfile.ZipFile(archive_path, "r")
    names = set(archive.namelist())
    if "config.json" not in names or "MANIFEST.json" not in names:
        archive.close()
        raise CustomizationError("Archive must contain config.json and MANIFEST.json")
    manifest = json.loads(archive.read("MANIFEST.json"))
    config_bytes = archive.read("config.json")
    if hashlib.sha256(config_bytes).hexdigest() != manifest.get("config_sha256"):
        archive.close()
        raise CustomizationError("config.json checksum does not match MANIFEST.json")
    assets = manifest.get("assets", {})
    # Packages generated before i4T Builder 0.3.9 encoded an empty PHP map as
    # a JSON array. Accept only that harmless empty legacy form.
    if assets == []:
        assets = {}
    if not isinstance(assets, dict):
        archive.close()
        raise CustomizationError("MANIFEST.json assets must be an object")
    for asset_name, expected_sha in assets.items():
        if not isinstance(asset_name, str) or not asset_name.startswith("assets/") or ".." in Path(asset_name).parts:
            archive.close()
            raise CustomizationError(f"Invalid asset path in MANIFEST.json: {asset_name!r}")
        if asset_name not in names:
            archive.close()
            raise CustomizationError(f"Asset listed in MANIFEST.json is missing: {asset_name}")
        if hashlib.sha256(archive.read(asset_name)).hexdigest() != expected_sha:
            archive.close()
            raise CustomizationError(f"Asset checksum does not match MANIFEST.json: {asset_name}")
    config = json.loads(config_bytes)
    config_assets = config.get("assets", {})
    if config_assets == []:
        config["assets"] = {}
    elif not isinstance(config_assets, dict):
        archive.close()
        raise CustomizationError("config.json assets must be an object")
    if config.get("schema_version") != 1:
        archive.close()
        raise CustomizationError("Unsupported customization schema version")
    if config.get("source", {}).get("commit") != EXPECTED_SOURCE_COMMIT:
        archive.close()
        raise CustomizationError("Customization package targets a different RustDesk-on commit")
    return config, archive


def apply_server(values: dict) -> None:
    id_server = values["idServer"].strip()
    relay_server = values.get("relayServer", "").strip()
    api_server = values["apiServer"].strip()
    server_key = values["serverKey"].strip()
    rendezvous_host = re.sub(r":21116$", "", id_server)
    config_path = "libs/hbb_common/src/config.rs"
    replace_exact(config_path, 'pub const RENDEZVOUS_SERVERS: &[&str] = &["wh.frps.cn"];', f'pub const RENDEZVOUS_SERVERS: &[&str] = &[{rust_quote(rendezvous_host)}];')
    replace_exact(config_path, 'pub const RS_PUB_KEY: &str = "LI3ALGhbXCrrhnyullTNS9ufslhJCvQCIeTDfw11hjM=";', f"pub const RS_PUB_KEY: &str = {rust_quote(server_key)};")
    replace_exact(config_path, '("custom-rendezvous-server", "wh.frps.cn:21116")', f'("custom-rendezvous-server", {rust_quote(id_server)})')
    replace_exact(config_path, '("relay-server", "wh.frps.cn:21117")', f'("relay-server", {rust_quote(relay_server)})')
    replace_exact(config_path, '("api-server", "http://wh.frps.cn:21114")', f'("api-server", {rust_quote(api_server)})')
    replace_exact("flutter/lib/common/widgets/i4t_sso_link.dart", "const i4tRustDeskApiUrl = 'http://wh.frps.cn:21114';", f"const i4tRustDeskApiUrl = '{dart_quote(api_server)}';")


def apply_sso(values: dict) -> None:
    relative = "flutter/lib/common/widgets/i4t_sso_link.dart"
    provider = values.get("ssoProviderName", "Authentik").strip() or "Authentik"
    button = values.get("ssoButtonText", "使用 Authentik SSO 登录").strip() or "使用 Authentik SSO 登录"
    replace_exact(relative, "const i4tSsoLabel = 'i4T SSO运维单点登录';", f"const i4tSsoProviderName = '{dart_quote(provider)}';\nconst i4tSsoLabel = '{dart_quote(button)}';")
    replace_exact(relative, "const i4tCopyNote = 'i4T 运维博客单点登录Rustdesk客户端使用';", f"const i4tCopyNote = '{dart_quote(provider)} 单点登录 RustDesk 客户端使用';")
    replace_exact(relative, "if (name.contains('authentik')) return 0;", "if (name.contains(i4tSsoProviderName.toLowerCase())) return 0;")


def apply_names(values: dict, enabled: dict) -> None:
    app_name = values.get("appName", "RustDesk").strip() or "RustDesk"
    package_id = values.get("packageId", "com.carriez.rustdesk").strip() or "com.carriez.rustdesk"
    installer_name = values.get("installerName", app_name).strip() or app_name
    executable_name = values.get("executableName", "rustdesk").strip() or "rustdesk"
    service_name = values.get("serviceName", f"{app_name} Service").strip() or f"{app_name} Service"
    if enabled.get("appName"):
        replace_exact("libs/hbb_common/src/config.rs", 'pub static ref APP_NAME: RwLock<String> = RwLock::new("RustDesk".to_owned());', f"pub static ref APP_NAME: RwLock<String> = RwLock::new({rust_quote(app_name)}.to_owned());")
        replace_exact("flutter/android/app/src/main/res/values/strings.xml", '<string name="app_name">RustDesk</string>', f'<string name="app_name">{app_name}</string>')
        replace_exact("flutter/android/app/src/main/AndroidManifest.xml", 'android:label="RustDesk"', f'android:label="{app_name}"')
        replace_exact("flutter/macos/Runner/Configs/AppInfo.xcconfig", "PRODUCT_NAME = RustDesk", f"PRODUCT_NAME = {app_name}")
    if enabled.get("deploymentNames"):
        replace_exact("flutter/windows/runner/Runner.rc", 'VALUE "FileDescription", "RustDesk Remote Desktop"', f'VALUE "FileDescription", "{installer_name} Remote Desktop"')
        replace_exact("flutter/windows/runner/Runner.rc", 'VALUE "InternalName", "rustdesk"', f'VALUE "InternalName", "{executable_name}"')
        replace_exact("flutter/windows/runner/Runner.rc", 'VALUE "OriginalFilename", "rustdesk.exe"', f'VALUE "OriginalFilename", "{executable_name}.exe"')
        replace_exact("flutter/windows/runner/Runner.rc", 'VALUE "ProductName", "RustDesk"', f'VALUE "ProductName", "{installer_name}"')
        replace_exact("src/platform/windows.rs", 'DisplayName= \\"{app_name} Service\\"', f'DisplayName= \\"{service_name}\\"', minimum=2)
        replace_exact("res/msi/Package/Language/Package.en-us.wxl", '<String Id="Service_DisplayName" Value="RustDesk Service" />', f'<String Id="Service_DisplayName" Value="{service_name}" />')
        replace_exact("flutter/android/app/src/main/kotlin/com/carriez/flutter_hbb/MainService.kt", 'val channelName = "RustDesk Service"', f'val channelName = "{service_name}"')
        replace_exact("flutter/android/app/src/main/kotlin/com/carriez/flutter_hbb/MainService.kt", 'description = "RustDesk Service Channel"', f'description = "{service_name} Channel"')
        replace_exact("flutter/macos/Runner.xcodeproj/project.pbxproj", "PRODUCT_BUNDLE_IDENTIFIER = com.carriez.rustdesk;", f"PRODUCT_BUNDLE_IDENTIFIER = {package_id};")
        replace_exact("flutter/android/app/build.gradle", 'applicationId "com.carriez.flutter_hbb"', f'applicationId "{package_id}"')


def apply_colors(values: dict) -> None:
    relative = "flutter/lib/desktop/pages/desktop_home_page.dart"
    primary = dart_color(values["primaryColor"])
    icon = dart_color(values["iconColor"])
    background = dart_color(values["backgroundColor"])
    replace_exact(relative, "0xFF0B3A82", primary)
    replace_exact(relative, "0xFF1266F1", icon)
    replace_exact(relative, "0xFFEAF2FF", background)


def apply_logo(archive: zipfile.ZipFile, config: dict) -> None:
    asset = config.get("assets", {}).get("logo")
    if not asset:
        raise CustomizationError("Logo customization is enabled but the archive has no logo asset")
    data = archive.read(asset)
    mime = config.get("assets", {}).get("logo_mime", "image/png")
    encoded = base64.b64encode(data).decode("ascii")
    svg = (
        '<svg xmlns="http://www.w3.org/2000/svg" width="480" height="160" viewBox="0 0 480 160">'
        f'<image width="480" height="160" preserveAspectRatio="xMidYMid meet" href="data:{mime};base64,{encoded}"/>'
        "</svg>\n"
    )
    write_text("flutter/assets/custom_logo.svg", svg)


def apply_icon(archive: zipfile.ZipFile, config: dict) -> None:
    asset = config.get("assets", {}).get("icon")
    if not asset:
        raise CustomizationError("Icon customization is enabled but the archive has no icon asset")
    try:
        from PIL import Image
    except ImportError as exc:
        raise CustomizationError("Pillow is required for application icon generation") from exc
    source = Image.open(io.BytesIO(archive.read(asset))).convert("RGBA")
    side = max(source.size)
    canvas = Image.new("RGBA", (side, side), (0, 0, 0, 0))
    canvas.alpha_composite(source, ((side - source.width) // 2, (side - source.height) // 2))

    def png(relative: str, size: int) -> None:
        target = ROOT / relative
        target.parent.mkdir(parents=True, exist_ok=True)
        canvas.resize((size, size), Image.Resampling.LANCZOS).save(target, "PNG")

    png("res/icon.png", 256)
    png("res/mac-icon.png", 1024)
    for density, size in {"mdpi": 48, "hdpi": 72, "xhdpi": 96, "xxhdpi": 144, "xxxhdpi": 192}.items():
        for name in ("ic_launcher.png", "ic_launcher_foreground.png", "ic_launcher_round.png", "ic_stat_logo.png"):
            png(f"flutter/android/app/src/main/res/mipmap-{density}/{name}", size)
    ios_dir = ROOT / "flutter/ios/Runner/Assets.xcassets/AppIcon.appiconset"
    for path in ios_dir.glob("Icon-App-*.png"):
        match = re.search(r"-(\d+(?:\.\d+)?)x\d+(?:\.\d+)?@(\d)x", path.name)
        if match:
            size = round(float(match.group(1)) * int(match.group(2)))
            canvas.resize((size, size), Image.Resampling.LANCZOS).save(path, "PNG")
    ico = canvas.resize((256, 256), Image.Resampling.LANCZOS)
    for relative in ("res/icon.ico", "flutter/windows/runner/resources/app_icon.ico"):
        ico.save(ROOT / relative, "ICO", sizes=[(16, 16), (24, 24), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)])
    canvas.resize((1024, 1024), Image.Resampling.LANCZOS).save(ROOT / "flutter/macos/Runner/AppIcon.icns", "ICNS")


def main() -> int:
    archive_path = Path(sys.argv[1] if len(sys.argv) > 1 else ROOT / "i4t-customization.zip").resolve()
    config, archive = parse_archive(archive_path)
    try:
        validate_config(config)
        enabled = config.get("enabled", {})
        values = config.get("values", {})
        if enabled.get("serverConfig"):
            apply_server(values)
        if enabled.get("ssoConfig") and values.get("ssoEnabled"):
            apply_sso(values)
        apply_names(values, enabled)
        if enabled.get("colors"):
            apply_colors(values)
        if enabled.get("welcomeText"):
            replace_exact("flutter/lib/desktop/pages/desktop_home_page.dart", "安全 · 开源 · 高效的远程桌面", values["welcomeText"])
        if enabled.get("logo"):
            apply_logo(archive, config)
        if enabled.get("appIcon"):
            apply_icon(archive, config)
    finally:
        archive.close()
    applied = {
        "schema_version": 1,
        "source_commit": EXPECTED_SOURCE_COMMIT,
        "scheme_uuid": config.get("scheme", {}).get("uuid"),
        "config_sha256": hashlib.sha256(json.dumps(config, ensure_ascii=False, sort_keys=True).encode()).hexdigest(),
    }
    (ROOT / ".i4t-customization-applied.json").write_text(json.dumps(applied, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print("i4t customization applied and verified")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (CustomizationError, KeyError, ValueError, zipfile.BadZipFile) as exc:
        print(f"::error title=i4t customization failed::{exc}", file=sys.stderr)
        raise SystemExit(2)
