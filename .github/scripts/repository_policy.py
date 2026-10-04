#!/usr/bin/env python3
"""从 Git 对象检查已跟踪文件规范，不扫描工作区资源。

默认 / --staged：对比 index 与 HEAD，也支持尚无 HEAD 的新仓库。
--base COMMIT：对比基线提交树与 HEAD 提交树，供拉取请求 CI 使用。

仅加载元数据和运行时 JSON blob，其余路径使用空字节占位，避免读取
图片、音频等大资源。纯函数 validate_repository() 接受路径到 bytes 的
映射，仅检查 .meta 和应校验的 JSON 资源内容，方便独立测试。
"""

from __future__ import annotations

import argparse
from collections import defaultdict
from dataclasses import dataclass
import json
import os
from pathlib import Path, PurePosixPath
import re
import subprocess
import sys
from typing import Mapping, Sequence


# 引擎参考目录仅匹配仓库根；scripts/shared/schemas 属于用户代码。
ROOT_ONLY_DIRECTORIES = frozenset(
    {".emmylua", "engine-docs", "examples", "urhox-libs", "schemas", "templates", "screenshots"}
)
LOCAL_DIRECTORIES = frozenset(
    {
        "dist", ".build", ".cli", "logs", ".tmp", ".tmp-headless", "node_modules",
        "__pycache__", ".maker", ".maker-mcp", ".sce",
    }
)
ELECTRON_GENERATED_DIRECTORIES = frozenset({"game", "game_engine", "release"})
ENV_TEMPLATES = frozenset({".env.example", ".env.sample", ".env.template"})
PRIVATE_FILES = frozenset({".git-credentials", ".netrc", "id_rsa", "id_ed25519"})

# game_material 是上传的发布素材，不是构建资源根。
# 已有 sidecar 仍须校验，但新增发布图片不强求 sidecar。
RESOURCE_ROOTS = frozenset({"scripts", "assets", "i18n", ".project"})
RESOURCE_EXTENSIONS = frozenset(
    {
        ".lua", ".png", ".jpg", ".jpeg", ".webp", ".ogg", ".mp3", ".wav",
        ".json", ".xml", ".fsm", ".blendspace", ".atlas", ".shader", ".ttf",
        ".otf", ".mdl",
    }
)
DEVELOPMENT_FILES = frozenset({".luarc.json", ".luarc.jsonc", ".gitkeep", ".DS_Store"})
SHARED_CONFIG_PATHS = (
    ".project/project.json",
    ".project/settings.json",
    ".project/resources.json",
    ".project/i18n.json",
)
IDENTITY_FIELDS = (
    ("project_id",),
    ("author", "id"),
    ("taptap_publish", "app_id"),
    ("taptap_publish", "developer_id"),
    ("taptap_publish", "miniapp_id"),
    ("taptap_publish", "client_id"),
)
UUID_PATTERN = re.compile(r"^[A-Za-z0-9_-]+$")
OID_PATTERN = re.compile(r"^[0-9a-fA-F]{40}(?:[0-9a-fA-F]{24})?$")
_MISSING = object()


@dataclass(frozen=True)
class Issue:
    severity: str
    code: str
    path: str
    message: str


class GitReadError(RuntimeError):
    """脱敏的 Git 读取错误，不包含 stderr 或 blob 内容。"""


def forbidden_reason(path: str) -> str | None:
    """返回禁止类别；允许的已跟踪路径返回 None。"""
    # 同时按 sidecar 的源文件名检查，例如 save.json.meta、id_rsa.meta。
    source = path[:-5] if path.endswith(".meta") else path
    parts = source.split("/")
    directories = parts[:-1]
    if any(part in LOCAL_DIRECTORIES for part in directories) or (
        path.endswith(".meta") and parts[-1] in LOCAL_DIRECTORIES
    ):
        return "本机构建、缓存或工具状态"
    if parts[0] in ROOT_ONLY_DIRECTORIES and (len(parts) > 1 or path.endswith(".meta")):
        return "根目录引擎参考文件或本地截图"
    if (
        len(parts) >= 2
        and parts[0] == "electron-shell"
        and parts[1] in ELECTRON_GENERATED_DIRECTORIES
        and (len(parts) > 2 or path.endswith(".meta"))
    ):
        return "Electron 游戏构建产物"
    name = parts[-1]
    lower_name = name.lower()
    if lower_name.endswith((".log", ".pyc", ".pyo")):
        return "日志或 Python 字节码"
    if name in PRIVATE_FILES:
        return "本地凭据或私钥"
    if name == ".env" or (name.startswith(".env.") and name not in ENV_TEMPLATES):
        return "私有环境配置（可改用 .env.example/.env.sample/.env.template）"
    if len(parts) == 1 and (
        name == "standalone_save.json" or re.fullmatch(r"battle_lab_.*\.json", name)
    ):
        return "根目录本地游戏存档"
    return None


def requires_meta(path: str) -> bool:
    """已确认类型的运行时资源是否需要已跟踪的 .meta。"""
    parts = path.split("/")
    if len(parts) < 2 or parts[0] not in RESOURCE_ROOTS:
        return False
    if parts[-1] in DEVELOPMENT_FILES or path.endswith(".meta"):
        return False
    return PurePosixPath(path).suffix.lower() in RESOURCE_EXTENSIONS


def checks_json(path: str) -> bool:
    """检查运行时 .json 语法，不套用 schema，不解析 JSONC。"""
    return (
        path.split("/")[0] in RESOURCE_ROOTS
        and PurePosixPath(path).suffix.lower() == ".json"
    )


def _reject_json_constant(_value: str) -> None:
    # Python 默认允许 NaN/Infinity，但它们不是合法 JSON。
    raise ValueError("不合法的 JSON 常量")


def _load_json_object(content: bytes) -> dict:
    value = json.loads(content, parse_constant=_reject_json_constant)
    if not isinstance(value, dict):
        raise ValueError("应为 JSON object")
    return value


def _parse_metadata(files: Mapping[str, bytes], issues: list[Issue] | None) -> dict[str, str]:
    uuids = {}
    for path in sorted(files):
        if not path.endswith(".meta"):
            continue
        try:
            data = _load_json_object(files[path])
        except (ValueError, UnicodeError, RecursionError):
            if issues is not None:
                issues.append(Issue("error", "meta-json", path, "元数据必须是合法的 JSON object。"))
            continue
        uuid = data.get("uuid")
        if not isinstance(uuid, str) or not UUID_PATTERN.fullmatch(uuid):
            if issues is not None:
                issues.append(Issue(
                    "error", "meta-uuid", path,
                    "元数据 uuid 必须是非空字符串，且仅含 A-Z、a-z、0-9、'_' 或 '-'。",
                ))
            continue
        uuids[path] = uuid
    return uuids


def _field(config: dict, parts: tuple[str, ...]) -> object:
    value = config
    for part in parts:
        if not isinstance(value, dict) or part not in value:
            return _MISSING
        value = value[part]
    return value


def _same_value(left: object, right: object) -> bool:
    # 区分缺失/null、bool/int，且不输出身份值。
    return type(left) is type(right) and left == right


def validate_repository(
    current: Mapping[str, bytes],
    base: Mapping[str, bytes] | None = None,
    *,
    allow_identity_change: bool = False,
    renames: Mapping[str, str] | None = None,
) -> list[Issue]:
    """校验快照；诊断不包含 UUID 或 JSON 字段值。

    current/base 将仓库相对 POSIX 路径映射为 bytes，非 .meta/JSON
    资源可用 b'' 占位。全量校验 current，不继承或豁免基线违规。
    renames 是 Git 识别的源文件旧路径到新路径映射，不自行猜测删除/新增。
    allow_identity_change 仅供明确批准的本地身份迁移；CLI 在 CI
    环境中另行禁止该覆盖选项。
    """
    base = {} if base is None else base
    issues: list[Issue] = []
    for path in sorted(current):
        reason = forbidden_reason(path)
        if reason is not None:
            issues.append(Issue("error", "forbidden-path", path, f"禁止跟踪{reason}；请移出 index 并添加 ignore 规则。"))
        if path.endswith(".meta") and path[:-5] not in current:
            issues.append(Issue("error", "meta-orphan", path, "元数据的源文件未跟踪；请恢复源文件或移除孤立 sidecar。"))
        if requires_meta(path) and path + ".meta" not in current:
            issues.append(Issue("error", "meta-missing", path, "已跟踪的运行时资源需要已跟踪的 .meta sidecar。"))

    current_uuids = _parse_metadata(current, issues)
    uuid_paths: dict[str, list[str]] = defaultdict(list)
    for path, uuid in current_uuids.items():
        uuid_paths[uuid].append(path)
    for paths in uuid_paths.values():
        if len(paths) > 1:
            for path in paths:
                issues.append(Issue("error", "meta-duplicate", path, "多个已跟踪 sidecar 使用同一个 uuid；每个资源必须拥有唯一 uuid。"))

    # 唯一性仅检查 current，重命名沿用旧 UUID 不会与基线记录误判重复。
    renames = {} if renames is None else renames
    for path, old_uuid in _parse_metadata(base, None).items():
        source = path[:-5]
        # 优先同路径；否则仅跟随 Git 已识别的源文件重命名。
        target_source = source if source in current else renames.get(source)
        if target_source is None or target_source not in current:
            continue
        target_meta = target_source + ".meta"
        if target_meta not in current:
            if not requires_meta(target_source):  # 已确认资源扩展此前已报同类错误。
                issues.append(Issue("error", "meta-missing", target_source, "已有资源必须保留已跟踪的元数据 sidecar。"))
        elif target_meta in current_uuids and current_uuids[target_meta] != old_uuid:
            issues.append(Issue("error", "meta-uuid-changed", target_meta, "已有资源 uuid 被改变；请恢复基线 uuid，重命名源文件及 sidecar 时仍应沿用它。"))

    current_configs = {}
    for path in sorted(current):
        if not checks_json(path):
            continue
        try:
            value = json.loads(current[path], parse_constant=_reject_json_constant)
            if path in SHARED_CONFIG_PATHS:
                if not isinstance(value, dict):
                    raise ValueError("共享配置应为 JSON object")
                current_configs[path] = value
        except (ValueError, UnicodeError, RecursionError):
            if path in SHARED_CONFIG_PATHS:
                issues.append(Issue("error", "config-json", path, "共享项目配置必须是合法的 JSON object；不套用旧引擎 schema。"))
            else:
                issues.append(Issue("error", "resource-json", path, "已跟踪的运行时 JSON 资源必须语法合法；不限制其 schema。"))

    project_path = ".project/project.json"
    if project_path in base and (project_path not in current or project_path in current_configs):
        try:
            old_config = _load_json_object(base[project_path])
        except (ValueError, UnicodeError, RecursionError):
            issues.append(Issue("error", "base-config-json", project_path, "基线项目配置不是合法 JSON object，无法比较身份；请选择有效基线。"))
        else:
            new_config = current_configs.get(project_path, {})
            for field in IDENTITY_FIELDS:
                if _same_value(_field(old_config, field), _field(new_config, field)):
                    continue
                field_name = ".".join(field)
                if allow_identity_change:
                    issues.append(Issue("warning", "identity-change-allowed", project_path, f"已对 {field_name} 使用明确批准的本地身份覆盖；不记录身份值。"))
                else:
                    issues.append(Issue(
                        "error", "identity-change", project_path,
                        f"受保护身份字段 {field_name} 已变化；请恢复基线身份。只有明确批准的正式身份迁移才可在本地使用 --allow-identity-change；禁止在 CI 启用该覆盖选项。",
                    ))
            if not _same_value(_field(old_config, ("metadata", "updated_at")), _field(new_config, ("metadata", "updated_at"))):
                issues.append(Issue("warning", "metadata-updated-at", project_path, "metadata.updated_at 已变化，请检查自动生成的时间戳噪音；此提示不阻止通过。"))
    return sorted(issues, key=lambda issue: (issue.path, issue.severity, issue.code))


def _git(repo: Path, *args: str, check: bool = True) -> subprocess.CompletedProcess:
    try:
        result = subprocess.run(
            ["git", "-C", str(repo), *args],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            check=False,
        )
    except OSError as exc:
        raise GitReadError("无法执行 Git。") from exc
    if check and result.returncode:
        raise GitReadError("无法读取仓库 Git 对象；请确认仓库、index 和已获取的基线提交有效。")
    return result


def _commit_oid(repo: Path, ref: str) -> str:
    result = _git(repo, "rev-parse", "--verify", "--end-of-options", ref + "^{commit}")
    oid = result.stdout.decode("ascii", errors="replace").strip()
    if not OID_PATTERN.fullmatch(oid):
        raise GitReadError("Git 未返回有效的 commit OID。")
    return oid


def _materialize(repo: Path, entries: Mapping[str, str]) -> dict[str, bytes]:
    files = dict.fromkeys(entries, b"")
    selected = {
        path: oid for path, oid in entries.items()
        if path.endswith(".meta") or checks_json(path)
    }
    oids = list(dict.fromkeys(selected.values()))
    if not oids:
        return files
    if any(not OID_PATTERN.fullmatch(oid) for oid in oids):
        raise GitReadError("Git blob OID 不合法。")
    # 文件路径从不传入 Git 对象表达式/pathspec，仅传入验证后的 OID。
    # 所选 blob 是少量 JSON，不加载游戏图片或音频。
    try:
        process = subprocess.run(
            ["git", "-C", str(repo), "cat-file", "--batch"],
            input=("\n".join(oids) + "\n").encode("ascii"),
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            check=False,
        )
    except OSError as exc:
        raise GitReadError("无法执行 Git blob 读取器。") from exc
    if process.returncode:
        raise GitReadError("无法读取已跟踪元数据/JSON blob。")
    contents = {}
    offset = 0
    output = process.stdout
    for oid in oids:
        end = output.find(b"\n", offset)
        if end == -1:
            raise GitReadError("Git blob 响应不完整。")
        header = output[offset:end].split()
        if len(header) != 3 or header[0] != oid.encode("ascii") or header[1] != b"blob":
            raise GitReadError("已跟踪元数据/JSON 必须可作为 Git blob 读取。")
        try:
            size = int(header[2])
        except ValueError as exc:
            raise GitReadError("Git blob 长度不合法。") from exc
        start = end + 1
        if size < 0 or output[start + size:start + size + 1] != b"\n":
            raise GitReadError("Git blob 内容不完整。")
        contents[oid] = output[start:start + size]
        offset = start + size + 1
    for path, oid in selected.items():
        files[path] = contents[oid]
    return files


def read_index(repo: Path) -> dict[str, bytes]:
    """读取 index 中已跟踪路径，仅物化需检查的元数据/JSON blob。"""
    entries = {}
    for record in _git(repo, "ls-files", "--stage", "-z").stdout.split(b"\0"):
        if not record:
            continue
        fields, path_bytes = record.split(b"\t", 1)
        _mode, oid, stage = fields.split()
        if stage != b"0":
            raise GitReadError("index 存在未解决的合并冲突；请解决后再检查规范。")
        if not OID_PATTERN.fullmatch(oid.decode("ascii")) or not oid.strip(b"0"):
            raise GitReadError("index 存在未暂存内容的 intent-to-add 条目；请先暂存文件内容。")
        entries[path_bytes.decode("utf-8", errors="surrogateescape")] = oid.decode("ascii")
    return _materialize(repo, entries)


def read_tree(repo: Path, commit: str) -> dict[str, bytes]:
    """安全读取提交树，将形似命令选项的 ref 也作为数据处理。"""
    oid = _commit_oid(repo, commit)
    entries = {}
    for record in _git(repo, "ls-tree", "-r", "--full-tree", "-z", oid).stdout.split(b"\0"):
        if not record:
            continue
        fields, path_bytes = record.split(b"\t", 1)
        _mode, _kind, blob_oid = fields.split()
        entries[path_bytes.decode("utf-8", errors="surrogateescape")] = blob_oid.decode("ascii")
    return _materialize(repo, entries)


def read_renames(
    repo: Path,
    base_commit: str,
    *,
    staged: bool = False,
    current_commit: str = "HEAD",
) -> dict[str, str]:
    """读取 Git 识别的源文件重命名；OID 参数和 NUL 路径避免注入。"""
    base_oid = _commit_oid(repo, base_commit)
    args = ["diff", "--no-ext-diff", "--no-textconv", "--name-status", "-z", "--find-renames"]
    if staged:
        args.extend(["--cached", base_oid])
    else:
        args.extend([base_oid, _commit_oid(repo, current_commit)])
    args.append("--")
    fields = _git(repo, *args).stdout.split(b"\0")
    renames = {}
    index = 0
    while index < len(fields) - 1:
        status = fields[index]
        index += 1
        path_count = 2 if status.startswith((b"R", b"C")) else 1
        if not status or index + path_count > len(fields) - 1:
            raise GitReadError("Git 文件变更列表不完整。")
        paths = fields[index:index + path_count]
        index += path_count
        if status.startswith(b"R"):
            old, new = (path.decode("utf-8", errors="surrogateescape") for path in paths)
            if not old.endswith(".meta") and not new.endswith(".meta"):
                renames[old] = new
    return renames


def _annotation_escape(value: str, *, property_value: bool = False) -> str:
    value = value.encode("utf-8", errors="backslashreplace").decode("utf-8")
    value = value.replace("%", "%25").replace("\r", "%0D").replace("\n", "%0A")
    if property_value:
        value = value.replace(":", "%3A").replace(",", "%2C")
    return value


def render_issues(issues: Sequence[Issue], *, github_actions: bool = False) -> int:
    """输出安全诊断和汇总；存在规范错误返回 1，否则返回 0。"""
    errors = sum(issue.severity == "error" for issue in issues)
    warnings = sum(issue.severity == "warning" for issue in issues)
    for issue in issues:
        # JSON 转义使带换行/控制字符的恶意文件名无法注入日志指令。
        path_display = json.dumps(issue.path, ensure_ascii=True)
        print(f"{issue.severity.upper()} [{issue.code}] {path_display}: {issue.message}")
        if github_actions:
            properties = f"file={_annotation_escape(issue.path, property_value=True)},title=仓库文件规范"
            print(f"::{issue.severity} {properties}::{_annotation_escape(issue.message)}")
    print(f"仓库文件规范：{errors} 个错误，{warnings} 个警告。")
    return 1 if errors else 0


def _in_ci() -> bool:
    return any(os.environ.get(name, "").lower() not in {"", "0", "false", "no"} for name in ("CI", "GITHUB_ACTIONS"))


def main(argv: Sequence[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument("--staged", action="store_true", help="对比 Git index 与 HEAD（默认模式）。")
    mode.add_argument("--base", metavar="COMMIT", help="对比基线提交树与 HEAD；忽略工作区及 index。")
    parser.add_argument("--github-actions", action="store_true", help="同时输出安全转义的 GitHub Actions 注解。")
    parser.add_argument("--allow-identity-change", action="store_true", help="明确批准的正式身份迁移，仅限人工本地使用，CI 禁用。")
    args = parser.parse_args(argv)
    if args.allow_identity_change and (args.github_actions or _in_ci()):
        return render_issues([Issue("error", "identity-override-in-ci", ".project/project.json", "--allow-identity-change 仅供明确批准的人工本地身份迁移，禁止在 CI 使用。")], github_actions=args.github_actions)
    repo = Path.cwd()
    try:
        root = _git(repo, "rev-parse", "--show-toplevel").stdout.rstrip(b"\n")
        repo = Path(os.fsdecode(root))
        if args.base is not None:
            base = read_tree(repo, args.base)
            current = read_tree(repo, "HEAD")
            renames = read_renames(repo, args.base)
            comparison = "基线提交树对比 HEAD 提交树"
        else:
            current = read_index(repo)
            # 仅刚初始化且尚无提交的仓库允许不存在 HEAD。
            head = _git(repo, "rev-parse", "--verify", "--end-of-options", "HEAD^{commit}", check=False)
            if head.returncode:
                symbolic = _git(repo, "symbolic-ref", "-q", "HEAD", check=False)
                if symbolic.returncode:
                    raise GitReadError("index 对比无法解析 HEAD。")
                branch = symbolic.stdout.decode("utf-8", errors="surrogateescape").strip()
                if _git(repo, "show-ref", "--verify", "--", branch, check=False).returncode == 0:
                    raise GitReadError("HEAD 提交不可用；请先修复或获取该提交。")
                base = {}
                renames = {}
            else:
                base = read_tree(repo, "HEAD")
                renames = read_renames(repo, "HEAD", staged=True)
            comparison = "Git index 对比 HEAD"
    except GitReadError as exc:
        return render_issues([Issue("error", "git-read", "", str(exc))], github_actions=args.github_actions)
    print(f"检查 {len(current)} 个已跟踪路径（{comparison}）；仅加载元数据/运行时 JSON blob。")
    issues = validate_repository(current, base, allow_identity_change=args.allow_identity_change, renames=renames)
    return render_issues(issues, github_actions=args.github_actions)


if __name__ == "__main__":
    sys.exit(main())
