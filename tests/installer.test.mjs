import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { spawnSync } from "node:child_process";
import path from "node:path";
import test from "node:test";
import { projectRoot } from "./helpers/typescript.mjs";

test("Web service installation never takes ownership of Sync data", () => {
  const source = readFileSync(path.join(projectRoot, "scripts/install.sh"), "utf8");
  const install = source.slice(source.indexOf("install_web_service() {"), source.indexOf("\nstart_web_service() {"));
  const commands = spawnSync("bash", ["-s"], {
    encoding: "utf8",
    env: { ...process.env, FIXTURE_CONFIG: path.join(projectRoot, "config/bike.config.example.json") },
    input: `set -euo pipefail
INSTALL_DIR=/fixture/bike
WEB_SERVICE_USER=bike-web
WEB_SERVICE_NAME=bike-web
NODE_BIN=/fixture/node
ensure_node() { :; }
systemd_available() { return 0; }
tty_available() { return 1; }
web_config_path() { printf '%s' "$FIXTURE_CONFIG"; }
id() { if [[ "$1" == -gn ]]; then printf 'bike-web'; fi; }
sudo_cmd() { printf '%s\\n' "$*"; }
mktemp() { printf /dev/null; }
success() { :; }
die() { exit 1; }
${install}
install_web_service
`,
  });
  assert.equal(commands.status, 0, commands.stderr);
  assert.match(commands.stdout, /systemctl enable bike-web\.service/);
  assert.match(commands.stdout, /chown bike-web:bike-web .*bike\.config\.example\.json/);
  assert.doesNotMatch(commands.stdout, /chown[^\n]*\/fixture\/bike\/data/);
});
