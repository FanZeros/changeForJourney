"""repository_policy.py 的黑盒进程回归测试，仅使用 Python 标准库。

执行 ``python -m unittest discover -s .github/scripts -p 'test_*.py'``。
每例从已提交的临时仓库基线开始，不修改开发者的真实仓库。
"""

import base64
import copy
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
import uuid


POLICY = Path(__file__).with_name("repository_policy.py").resolve()
PROJECT_PATH = ".project/project.json"
SECRET = "fixture-secret-NOT-FOR-OUTPUT-7f619b"
IDENTITIES = (
    ("project_id",),
    ("author", "id"),
    ("taptap_publish", "app_id"),
    ("taptap_publish", "developer_id"),
    ("taptap_publish", "client_id"),
    ("taptap_publish", "miniapp_id"),
)


def new_uuid():
    return base64.urlsafe_b64encode(uuid.uuid4().bytes).decode("ascii").rstrip("=")


class RepositoryPolicyTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        if not POLICY.is_file():
            raise RuntimeError(f"Validator is not available: {POLICY}")

    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="repository-policy-")
        self.addCleanup(self.temp.cleanup)
        self.repo = Path(self.temp.name) / "repo"
        self.repo.mkdir()
        self.env = os.environ.copy()
        for key in tuple(self.env):
            if key.startswith("GIT_") or key in ("CI", "GITHUB_ACTIONS"):
                self.env.pop(key)
        self.env.update({
            "GIT_CONFIG_NOSYSTEM": "1",
            "GIT_CONFIG_GLOBAL": os.devnull,
            "GIT_CONFIG_SYSTEM": os.devnull,
            "GIT_TERMINAL_PROMPT": "0",
            "PYTHONDONTWRITEBYTECODE": "1",
        })
        self.git("init", "--quiet")
        self.git("config", "user.name", "Policy Fixture")
        self.git("config", "user.email", "policy-fixture@example.invalid")
        self.git("config", "core.autocrlf", "false")
        self.git("config", "core.quotePath", "false")
        self.project = {
            "$schema": "../schemas/project.schema.json",
            "project_id": "m_fixture",
            "author": {"id": "123456789"},
            "entry": "main.lua",
            "version": "1.0.0",
            "taptap_publish": {
                "title": "仓库规范测试",
                "category": "card",
                "screen_orientation": "landscape",
                "collection_type": "card",
                "app_id": 101,
                "developer_id": 202,
                "client_id": "fixture-client",
                "miniapp_id": "fixture-miniapp",
            },
            "assets": {"icon": "", "screenshots": []},
        }
        self.resource("scripts/main.lua", "function Start()\nend\n")
        self.resource("assets/image/中文角色 卡面.png", b"fixture-png")
        self.resource(PROJECT_PATH, self.project)
        self.resource(".project/settings.json", {
            "$schema": "../schemas/settings.schema.json",
            "sources": {"engine": {"tag": "stable"}},
            "build": {"asset_dirs": ["../assets", "../scripts"]},
            "@runtime": {"multiplayer": {"enabled": False}},
        })
        self.resource(".project/resources.json", {
            "$schema": "../schemas/resources.schema.json",
            "preload_groups": [], "groups": {"default": ["**"]},
        })
        self.resource(".project/i18n.json", {
            "$schema": "../schemas/i18n.schema.json",
            "enabled": False, "source_lang": "zh_CN", "target_langs": ["en"],
        })
        self.write(".gitignore", "\n".join((
            ".env", ".env.*", ".build/", "dist/", ".cli/", ".tmp/",
            "logs/", "*.log", "__pycache__/", "node_modules/",
            "electron-shell/game/", "electron-shell/game_engine/",
            "electron-shell/release/", "screenshots/",
            "/standalone_save.json", "/battle_lab_*.json", "",
        )))
        self.git("add", "--all")
        self.commit("baseline")
        self.baseline = self.git("rev-parse", "HEAD").strip()

    def git(self, *args):
        result = subprocess.run(
            ["git", *args], cwd=self.repo, env=self.env,
            stdin=subprocess.DEVNULL, stdout=subprocess.PIPE,
            stderr=subprocess.PIPE, text=True, encoding="utf-8", timeout=20,
        )
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        return result.stdout

    def commit(self, message):
        self.git("commit", "--quiet", "-m", message)

    def write(self, path, content):
        target = self.repo / path
        target.parent.mkdir(parents=True, exist_ok=True)
        if isinstance(content, (dict, list)):
            content = json.dumps(content, ensure_ascii=False, indent=2) + "\n"
        if isinstance(content, bytes):
            target.write_bytes(content)
        else:
            target.write_text(content, encoding="utf-8")

    def resource(self, path, content, resource_uuid=None):
        self.write(path, content)
        self.write(path + ".meta", {"uuid": resource_uuid or new_uuid()})

    def stage(self, *paths):
        self.git("add", "--force", "--", *paths)

    def restore(self):
        self.git("reset", "--hard", "--quiet", self.baseline)
        self.git("clean", "-fdx", "--quiet")

    def policy(self, *args, cwd=None):
        return subprocess.run(
            [sys.executable, str(POLICY), *args],
            cwd=cwd or self.repo, env=self.env, stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True,
            encoding="utf-8", timeout=20,
        )

    def assert_policy(self, allowed, *args, cwd=None):
        result = self.policy(*args, cwd=cwd)
        output = result.stdout + result.stderr
        self.assertNotIn(SECRET, output, "Validator must not disclose file contents")
        if allowed:
            self.assertEqual(result.returncode, 0, output)
        else:
            self.assertNotEqual(result.returncode, 0, output)
        return result

    def change_identity(self, identity, delete=False):
        project = copy.deepcopy(self.project)
        parent = project
        for part in identity[:-1]:
            parent = parent[part]
        if delete:
            del parent[identity[-1]]
        else:
            value = parent[identity[-1]]
            parent[identity[-1]] = value + 1 if isinstance(value, int) else value + "-changed"
        self.write(PROJECT_PATH, project)
        self.stage(PROJECT_PATH)

    def test_clean_baseline(self):
        self.assert_policy(True)

    def test_lua_content_change_keeps_metadata(self):
        self.write("scripts/main.lua", "function Start()\n    print('updated')\nend\n")
        self.stage("scripts/main.lua")
        self.assert_policy(True)
        self.assert_policy(True, "--staged")

    def test_new_source_and_metadata_pair(self):
        self.resource("scripts/战斗 新模块.lua", "return {}\n")
        self.stage("scripts/战斗 新模块.lua", "scripts/战斗 新模块.lua.meta")
        self.assert_policy(True)

    def test_source_and_metadata_deleted_together(self):
        self.git("rm", "--", "scripts/main.lua", "scripts/main.lua.meta")
        self.assert_policy(True)

    def test_source_and_metadata_renamed_with_uuid_preserved(self):
        self.git("mv", "scripts/main.lua", "scripts/重命名 模块.lua")
        self.git("mv", "scripts/main.lua.meta", "scripts/重命名 模块.lua.meta")
        self.assert_policy(True)
        self.commit("rename with stable uuid")
        self.assert_policy(True, "--base", self.baseline)

    def test_source_rename_with_regenerated_uuid_is_rejected(self):
        self.git("mv", "scripts/main.lua", "scripts/重命名 模块.lua")
        self.git("mv", "scripts/main.lua.meta", "scripts/重命名 模块.lua.meta")
        self.write("scripts/重命名 模块.lua.meta", {"uuid": new_uuid()})
        self.stage("scripts/重命名 模块.lua.meta")
        self.assert_policy(False, "--staged")
        self.commit("rename with changed uuid")
        self.assert_policy(False, "--base", self.baseline)

    def test_duplicate_uuid_is_rejected(self):
        meta = json.loads((self.repo / "scripts/main.lua.meta").read_text(encoding="utf-8"))
        self.resource("scripts/duplicate.lua", "return {}\n", meta["uuid"])
        self.stage("scripts/duplicate.lua", "scripts/duplicate.lua.meta")
        self.assert_policy(False)

    def test_orphan_metadata_is_rejected(self):
        self.write("scripts/orphan.lua.meta", {"uuid": new_uuid()})
        self.stage("scripts/orphan.lua.meta")
        self.assert_policy(False)

    def test_missing_lua_metadata_is_rejected(self):
        self.write("scripts/missing.lua", "return {}\n")
        self.stage("scripts/missing.lua")
        self.assert_policy(False)

    def test_deleting_only_metadata_is_rejected(self):
        self.git("rm", "--", "scripts/main.lua.meta")
        self.assert_policy(False)

    def test_deleting_only_source_is_rejected(self):
        self.git("rm", "--", "scripts/main.lua")
        self.assert_policy(False)

    def test_invalid_json_is_rejected(self):
        for path in (
            "scripts/main.lua.meta", PROJECT_PATH, ".project/settings.json",
            ".project/resources.json", ".project/i18n.json", "scripts/data.json",
        ):
            with self.subTest(path=path):
                self.restore()
                if path == "scripts/data.json":
                    self.resource(path, {})
                    self.stage(path + ".meta")
                self.write(path, "{ invalid json " + SECRET)
                self.stage(path)
                self.assert_policy(False)

    def test_empty_uuid_is_rejected(self):
        for value in ("", new_uuid()):
            with self.subTest(uuid=value):
                self.restore()
                self.write("scripts/main.lua.meta", {"uuid": value})
                self.stage("scripts/main.lua.meta")
                self.assert_policy(False, "--staged")
                self.commit("metadata uuid changed")
                self.assert_policy(False, "--base", self.baseline)

    def test_force_added_private_and_build_files_are_rejected(self):
        for path in (
            ".env", ".env.local", ".build/package.bin", "dist/package.bin",
            ".cli/state.json", ".tmp/scratch.json", "logs/runtime.log",
            "electron-shell/game/package.bin", "electron-shell/game_engine/engine.bin",
            "electron-shell/release/bundle.zip", "electron-shell/node_modules/pkg/index.js",
            "electron-shell/__pycache__/builder.pyc", "scripts/builder.pyc",
            "scripts/builder.pyo", "schemas/spec.json", "dist.meta", ".build.meta",
            "scripts/cache/logs.meta",
        ):
            with self.subTest(path=path):
                self.restore()
                if path.endswith((".json", ".pyc", ".pyo")):
                    self.resource(path, {"fixture": SECRET})
                    self.stage(path, path + ".meta")
                elif path.endswith(".meta"):
                    self.write(path, {"uuid": new_uuid()})
                    (self.repo / path[:-5]).mkdir(parents=True, exist_ok=True)
                    self.write(path[:-5] + "/.keep", "fixture")
                    self.stage(path[:-5] + "/.keep")
                    self.commit("existing output directory")
                    self.stage(path)
                else:
                    self.write(path, SECRET)
                    self.stage(path)
                self.assert_policy(False)

    def test_root_runtime_outputs_and_sidecars_are_rejected(self):
        for source in ("standalone_save.json", "battle_lab_report.json", "battle_lab_new.json"):
            for path in (source, source + ".meta"):
                with self.subTest(path=path):
                    self.restore()
                    self.resource(source, {"fixture": SECRET})
                    if path == source:
                        self.stage(source, source + ".meta")
                    else:
                        self.stage(path)
                    self.assert_policy(False)

    def test_root_screenshots_and_directory_sidecar_are_rejected(self):
        for path in ("screenshots/游戏 截图.png", "screenshots.meta"):
            with self.subTest(path=path):
                self.restore()
                self.resource("screenshots/游戏 截图.png", b"screenshot")
                self.write("screenshots.meta", {"uuid": new_uuid()})
                if path.endswith(".png"):
                    self.stage(path, path + ".meta")
                else:
                    self.stage(path)
                self.assert_policy(False)

    def test_formal_assets_and_game_material_are_allowed(self):
        for path in (
            "assets/image/review/中文 角色.png", "assets/image/screenshots/游戏 截图.png",
            "game_material/ICON_测试.png", "assets/data/save.json", "assets/data/battle.json",
            "save.json", "battle_campaign.json", "scripts/shared/schemas/spec.json",
        ):
            with self.subTest(path=path):
                self.restore()
                self.resource(path, {} if path.endswith(".json") else b"fixture-image")
                self.stage(path, path + ".meta")
                self.assert_policy(True)

    def test_game_material_image_without_metadata_is_allowed(self):
        self.write("game_material/ICON_无元数据.png", b"fixture-image")
        self.stage("game_material/ICON_无元数据.png")
        self.assert_policy(True)
        self.commit("formal material without metadata")
        self.assert_policy(True, "--base", self.baseline)

    def test_identity_value_changes_are_rejected(self):
        for identity in IDENTITIES:
            with self.subTest(identity=".".join(identity)):
                self.restore()
                self.change_identity(identity)
                self.assert_policy(False)

    def test_identity_deletions_are_rejected(self):
        for identity in IDENTITIES:
            with self.subTest(identity=".".join(identity)):
                self.restore()
                self.change_identity(identity, delete=True)
                self.assert_policy(False)

    def test_version_and_entry_changes_are_allowed(self):
        project = copy.deepcopy(self.project)
        project.update({"version": "1.0.1", "entry": "alternate.lua"})
        self.write(PROJECT_PATH, project)
        self.resource("scripts/alternate.lua", "function Start()\nend\n")
        self.stage(PROJECT_PATH, "scripts/alternate.lua", "scripts/alternate.lua.meta")
        self.assert_policy(True)

    def test_identity_override_allows_identity_changes(self):
        self.change_identity(("taptap_publish", "developer_id"), delete=True)
        self.assert_policy(True, "--allow-identity-change")

    def test_identity_override_does_not_allow_artifacts(self):
        self.change_identity(("project_id",))
        self.write("dist/fixture.bin", SECRET)
        self.stage("dist/fixture.bin")
        self.assert_policy(False, "--allow-identity-change")

    def test_identity_override_is_rejected_in_ci(self):
        self.change_identity(("project_id",))
        self.assert_policy(False, "--github-actions", "--allow-identity-change")
        for name in ("GITHUB_ACTIONS", "CI"):
            with self.subTest(environment=name):
                self.env[name] = "true"
                try:
                    self.assert_policy(False, "--allow-identity-change")
                finally:
                    self.env.pop(name)

    def test_staged_snapshot_ignores_unstaged_identity_changes(self):
        project = copy.deepcopy(self.project)
        project["version"] = "1.0.2"
        self.write(PROJECT_PATH, project)
        self.stage(PROJECT_PATH)
        project["taptap_publish"]["developer_id"] = 999
        self.write(PROJECT_PATH, project)
        self.assert_policy(True, "--staged")
        self.assert_policy(True)

    def test_staged_violation_survives_worktree_repair(self):
        self.change_identity(("taptap_publish", "developer_id"))
        self.write(PROJECT_PATH, self.project)
        self.assert_policy(False, "--staged")

    def test_base_head_ignores_index_and_worktree_violations(self):
        self.write("dist/fixture.bin", SECRET)
        self.stage("dist/fixture.bin")
        self.change_identity(("project_id",))
        self.write(PROJECT_PATH, "{ broken " + SECRET)
        self.assert_policy(True, "--base", "HEAD")
        self.assert_policy(False, "--staged")

    def test_base_compares_committed_head_to_selected_commit(self):
        self.change_identity(("taptap_publish", "developer_id"))
        self.commit("identity change")
        self.assert_policy(False, "--base", self.baseline)
        self.assert_policy(True, "--base", "HEAD")
        self.assert_policy(True, "--base", self.baseline, "--allow-identity-change")

    def test_base_detects_committed_output(self):
        self.write("dist/fixture.bin", SECRET)
        self.stage("dist/fixture.bin")
        self.commit("invalid output")
        self.assert_policy(False, "--base", self.baseline)

    def test_base_allows_committed_source_change(self):
        self.write("scripts/main.lua", "function Start()\n    print('committed')\nend\n")
        self.stage("scripts/main.lua")
        self.commit("source update")
        self.assert_policy(True, "--base", self.baseline)

    def test_environment_templates_are_allowed(self):
        for path in (".env.example", ".env.sample", ".env.template"):
            with self.subTest(path=path):
                self.restore()
                self.write(path, "API_KEY=replace-me\n")
                self.stage(path)
                self.assert_policy(True)

    def test_lua_developer_configs_do_not_require_metadata(self):
        self.write(".luarc.json", {"runtime.version": "Lua 5.4"})
        self.write(".luarc.jsonc", '{\n // 开发者配置\n "runtime.version": "Lua 5.4"\n}\n')
        self.stage(".luarc.json", ".luarc.jsonc")
        self.assert_policy(True)

    def test_github_actions_mode_preserves_exit_status_and_secret_privacy(self):
        self.assert_policy(True, "--github-actions")
        self.write(".env", "API_KEY=" + SECRET)
        self.stage(".env")
        self.assert_policy(False, "--github-actions")

    def test_unknown_cli_argument_is_rejected(self):
        self.assert_policy(False, "--not-a-policy-option")

    def test_invalid_base_commit_is_rejected(self):
        self.assert_policy(False, "--base", "does-not-exist-fixture-ref")

    def test_non_git_cwd_is_rejected(self):
        plain = Path(self.temp.name) / "not-a-repository"
        plain.mkdir()
        self.assert_policy(False, cwd=plain)


if __name__ == "__main__":
    unittest.main()
