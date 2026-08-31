#!/usr/bin/env bash
# tools/update-cargo-vendor-hashes.sh
# Rust专用：仅更新 pkgs/third-party.nix 中 vaultix / pam-fido-remote 的 fetchCargoVendor hash
# 通过 Nix 的 fixed-output 校验（lib.fakeHash）获取真实 hash，不使用 cargo vendor / prefetch-cargo
# 显式处理两个包，不做自动扫描；尽量只触发 fetchCargoVendor，不完整构建 Rust 包
set -euo pipefail

FILE="pkgs/third-party.nix"
FAKE_HASH="sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA="
PACKAGES=("vaultix" "pam-fido-remote")

# 检查必要命令
for cmd in nix python3 git mktemp; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    # 尝试 nix shell 中的 python3
    if [[ "$cmd" == "python3" ]] && command -v python >/dev/null 2>&1; then
      continue
    fi
    echo "error: required command '$cmd' not found" >&2
    exit 1
  fi
done

# 选择可用的 python 解释器
PYTHON="python3"
if ! command -v "$PYTHON" >/dev/null 2>&1; then
  PYTHON="python"
fi

# 确保在仓库根目录
if [[ ! -f "$FILE" ]]; then
  if git_root=$(git rev-parse --show-toplevel 2>/dev/null); then
    cd "$git_root"
  fi
fi
if [[ ! -f "$FILE" ]]; then
  echo "error: $FILE not found (run from repo root: ./tools/update-cargo-vendor-hashes.sh)" >&2
  exit 1
fi

REPO_ROOT="$(pwd)"

# 清理临时文件
TMP_FILES=()
cleanup() {
  for f in "${TMP_FILES[@]}"; do
    if [[ -f "$f" ]]; then
      rm -f "$f" 2>/dev/null || true
    fi
  done
}
trap cleanup EXIT

# 获取当前 hash（严格定位）
get_current_hash() {
  local pkg="$1"
  "$PYTHON" - "$FILE" "$pkg" <<'PY'
import re, sys
path, pkg = sys.argv[1], sys.argv[2]
text = open(path).read()
pattern = re.compile(r'pname\s*=\s*"' + re.escape(pkg) + r'".*?fetchCargoVendor\s*\{[^}]*?hash\s*=\s*"([^"]+)"', re.S)
m = pattern.search(text)
if not m:
    print(f"error: could not locate hash for {pkg}", file=sys.stderr)
    sys.exit(1)
all_matches = pattern.findall(text)
if len(all_matches) != 1:
    print(f"error: found {len(all_matches)} hashes for {pkg}, expected 1", file=sys.stderr)
    sys.exit(1)
print(m.group(1))
PY
}

# 通过 fixed-output mismatch 获取预期 hash（仅触发 fetchCargoVendor）
get_expected_hash() {
  local pkg="$1"
  local tmp_out
  tmp_out=$(mktemp)
  TMP_FILES+=("$tmp_out")
  local tmp_nix
  tmp_nix=$(mktemp --suffix=.nix)
  TMP_FILES+=("$tmp_nix")

  # 构造仅构建 fetchCargoVendor 的 Nix 表达式（使用 fake hash 触发 mismatch）
  case "$pkg" in
    vaultix)
      cat > "$tmp_nix" <<NIX
let
  sources = import $REPO_ROOT/npins;
  pkgs = import sources.nixpkgs { system = "x86_64-linux"; };
in pkgs.rustPlatform.fetchCargoVendor {
  src = sources.vaultix.outPath;
  hash = "$FAKE_HASH";
}
NIX
      ;;
    pam-fido-remote)
      cat > "$tmp_nix" <<NIX
let
  sources = import $REPO_ROOT/npins;
  pkgs = import sources.nixpkgs { system = "x86_64-linux"; };
in pkgs.rustPlatform.fetchCargoVendor {
  src = sources.pam-fido-remote.outPath;
  hash = "$FAKE_HASH";
}
NIX
      ;;
    *)
      echo "error: unknown package '$pkg'" >&2
      return 1
      ;;
  esac

  echo "Fetching expected Cargo vendor hash for $pkg (via Nix fixed-output)..." >&2

  local exit_code=0
  # 预期失败：hash mismatch
  set +e
  nix build --impure --file "$tmp_nix" --no-link >"$tmp_out" 2>&1
  exit_code=$?
  set -e

  if [[ $exit_code -eq 0 ]]; then
    echo "error: expected nix build to fail with hash mismatch for $pkg, but it succeeded" >&2
    cat "$tmp_out" >&2
    return 1
  fi

  if ! grep -q "hash mismatch" "$tmp_out"; then
    echo "error: nix build for $pkg failed, but not due to hash mismatch" >&2
    cat "$tmp_out" >&2
    return 1
  fi
  if ! grep -qF "$FAKE_HASH" "$tmp_out"; then
    echo "error: hash mismatch for $pkg does not mention specified fake hash" >&2
    cat "$tmp_out" >&2
    return 1
  fi

  # 严格提取 got hash（必须恰好一个且合法）
  local got_hash
  got_hash=$("$PYTHON" - "$tmp_out" <<'PY'
import re, sys
path = sys.argv[1]
text = open(path, errors="ignore").read()
candidates = re.findall(r'got:\s+(sha256-[A-Za-z0-9+/=]+)', text)
if len(candidates) == 0:
    print("error: no got: sha256- found", file=sys.stderr)
    sys.exit(1)
uniq = set(candidates)
if len(uniq) != 1:
    print(f"error: multiple distinct got hashes found: {uniq}", file=sys.stderr)
    sys.exit(1)
cand = uniq.pop()
if not re.fullmatch(r'sha256-[A-Za-z0-9+/=]+', cand):
    print(f"error: invalid SRI hash format: {cand}", file=sys.stderr)
    sys.exit(1)
if len(cand) < 44 or len(cand) > 120:
    print(f"error: suspicious hash length: {cand}", file=sys.stderr)
    sys.exit(1)
# 基础 SRI 格式与长度检查（仅校验字符集与长度范围）
print(cand)
PY
)
  local py_exit=$?
  if [[ $py_exit -ne 0 ]]; then
    echo "error: failed to extract got hash for $pkg" >&2
    cat "$tmp_out" >&2
    return 1
  fi
  if [[ -z "$got_hash" ]]; then
    echo "error: extracted empty hash for $pkg" >&2
    return 1
  fi
  echo "$got_hash"
}

# 保守回写（精确修改对应 package 的 hash）
patch_hash() {
  local pkg="$1"
  local new_hash="$2"
  "$PYTHON" - "$FILE" "$pkg" "$new_hash" <<'PY'
import re, sys
path, pkg, new_hash = sys.argv[1], sys.argv[2], sys.argv[3]
text = open(path).read()
if not re.fullmatch(r'sha256-[A-Za-z0-9+/=]+', new_hash):
    print(f"error: invalid new hash SRI format: {new_hash}", file=sys.stderr)
    sys.exit(1)
pattern = re.compile(r'(pname\s*=\s*"' + re.escape(pkg) + r'".*?fetchCargoVendor\s*\{[^}]*?hash\s*=\s*")([^"]+)(")', re.S)
matches = list(pattern.finditer(text))
if len(matches) != 1:
    print(f"error: could not uniquely locate hash for {pkg} (found {len(matches)} matches)", file=sys.stderr)
    sys.exit(1)
old_hash = matches[0].group(2)
if old_hash == new_hash:
    sys.exit(0)
new_text = pattern.sub(r'\g<1>' + new_hash + r'\g<3>', text, count=1)
open(path, 'w').write(new_text)
print(f"Updated {pkg}: {old_hash} -> {new_hash}")
PY
}

echo "Checking Cargo vendor hashes in $FILE..."
needs_update=false
for pkg in "${PACKAGES[@]}"; do
  echo "=== Processing $pkg ==="
  expected=$(get_expected_hash "$pkg")
  echo "Expected hash for $pkg: $expected"
  current=$(get_current_hash "$pkg")
  echo "Current hash for $pkg: $current"
  if [[ "$expected" == "$current" ]]; then
    echo "$pkg is already up to date"
  else
    echo "Patching $pkg..."
    patch_hash "$pkg" "$expected"
    needs_update=true
  fi
done

if [[ "$needs_update" == true ]]; then
  echo "Verifying patched hashes..."
  for pkg in "${PACKAGES[@]}"; do
    echo "Verifying $pkg..."
    current_after=$(get_current_hash "$pkg")
    tmp_verify=$(mktemp --suffix=.nix)
    TMP_FILES+=("$tmp_verify")
    tmp_out_verify=$(mktemp)
    TMP_FILES+=("$tmp_out_verify")
    case "$pkg" in
      vaultix)
        cat > "$tmp_verify" <<NIX
let
  sources = import $REPO_ROOT/npins;
  pkgs = import sources.nixpkgs { system = "x86_64-linux"; };
in pkgs.rustPlatform.fetchCargoVendor {
  src = sources.vaultix.outPath;
  hash = "$current_after";
}
NIX
        ;;
      pam-fido-remote)
        cat > "$tmp_verify" <<NIX
let
  sources = import $REPO_ROOT/npins;
  pkgs = import sources.nixpkgs { system = "x86_64-linux"; };
in pkgs.rustPlatform.fetchCargoVendor {
  src = sources.pam-fido-remote.outPath;
  hash = "$current_after";
}
NIX
        ;;
    esac
    if ! nix build --impure --file "$tmp_verify" --no-link >"$tmp_out_verify" 2>&1; then
      echo "error: verification build for $pkg with hash $current_after failed" >&2
      cat "$tmp_out_verify" >&2
      exit 1
    fi
    echo "$pkg verification succeeded"
  done
fi

# 最终校验：git diff --check
if ! git diff --check -- "$FILE" 2>&1; then
  echo "warning: git diff --check found whitespace errors" >&2
fi

echo "Done. Changes:"
git diff --stat 2>&1 || true
git diff -- "$FILE" 2>&1 || true
