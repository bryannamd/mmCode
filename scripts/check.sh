#!/usr/bin/env bash
# mmCode 불변식 검사. 스킬 문서·스크립트가 스스로 정한 규칙을 어겼는지 본다.
# 사용: scripts/check.sh   (저장소 어느 위치에서 불러도 된다)
# 종료 코드: 0 = 전부 통과 · 1 = 실패 있음 · 2 = 실행 환경 문제
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
command -v python3 >/dev/null 2>&1 || { echo "python3 이 없다" >&2; exit 2; }
exec python3 -I - "$root" <<'PY'
import json, os, re, subprocess, sys, unicodedata

ROOT = sys.argv[1]
PLUGIN = os.path.join(ROOT, "plugins", "mmcode")
SKILLS = os.path.join(PLUGIN, "skills")

# 한도. 값을 바꾸면 이유를 커밋 본문에 적는다.
DESC_EACH_MAX = 400     # description 한 개. 매 세션 로드되는 문장이라 짧게 유지한다.
DESC_TOTAL_MAX = 3000   # description 합계.
PLAYBOOK_MAX = 30       # go/playbooks/*.md 줄 수 (go/references/DESIGN.md 5절)
GO_SKILL_MAX = 150      # go/SKILL.md 줄 수 (같은 곳)
PRINCIPLES_MAX = 60     # go/references/principles.md 줄 수 (같은 곳)
RULE_WIDTH = 50         # 화면 예시의 굵은 선·구역 제목 줄 폭 (explain·plan 화면 규칙)

# 금칙어. 실측·배선은 전역 문체 규칙. 나머지는 Cursor 이식 잔재 (DESIGN.md 5절·8절).
FORBIDDEN = [r"실측", r"배선", r"(?i)cursor", r"AskQuestion", r"grok", r"deslop", r"(?i)bugbot", r"pr merge"]
# 기록용 문서(references/DESIGN*.md). 금칙어 목록·옛 경로·아직 없는 제안 경로를 적으므로 금칙어·경로 검사에서 뺀다.
HISTORY_DOCS = {p for d in os.listdir(SKILLS) if os.path.isdir(os.path.join(SKILLS, d, "references"))
                for f in os.listdir(os.path.join(SKILLS, d, "references")) if re.match(r"DESIGN.*\.md$", f)
                for p in [os.path.join(SKILLS, d, "references", f)]}

fails = []
current = ""

def fail(msg):
    fails.append(f"FAIL {current}: {msg}")

def run(name, fn):
    # 검사 하나를 돌리고, 새 실패가 없으면 PASS 한 줄을 찍는다.
    global current
    current = name
    before = len(fails)
    info = fn()
    new = fails[before:]
    if new:
        print("\n".join(new))
    else:
        print(f"PASS {name}" + (f" ({info})" if info else ""))

def rel(path):
    return os.path.relpath(path, ROOT)

def read(path):
    with open(path, encoding="utf-8") as f:
        return f.read()

def md_files(base, skip=()):
    for dp, _, fs in os.walk(base):
        for f in sorted(fs):
            p = os.path.join(dp, f)
            if f.endswith(".md") and p not in skip:
                yield p

def width(s):
    # 터미널 표시 폭. 한글·이모지는 2칸, 결합 문자는 0칸.
    w = 0
    for c in s:
        if unicodedata.combining(c):
            continue
        w += 2 if unicodedata.east_asian_width(c) in "WF" else 1
    return w

def frontmatter(path):
    lines = read(path).split("\n")
    if not lines or lines[0] != "---":
        return None, "첫 줄이 --- 가 아니다"
    try:
        end = lines.index("---", 1)
    except ValueError:
        return None, "닫는 --- 가 없다"
    fm, key = {}, None
    for line in lines[1:end]:
        m = re.match(r"^([A-Za-z_-]+):\s*(.*)$", line)
        if m:
            key, val = m.group(1), m.group(2)
            # 접힌 값(>, |)은 다음 들여쓴 줄들을 이어 붙인다.
            fm[key] = "" if val in (">", "|", ">-", "|-") else val
        elif key and line[:1] in (" ", "\t"):
            fm[key] = (fm[key] + " " + line.strip()).strip()
    return fm, None

def skill_dirs():
    return sorted(d for d in os.listdir(SKILLS) if os.path.isdir(os.path.join(SKILLS, d)))

def check_structure():
    n = 0
    for d in skill_dirs():
        n += 1
        sk = os.path.join(SKILLS, d, "SKILL.md")
        if not os.path.isfile(sk):
            fail(f"{rel(sk)} 없음")
            continue
        fm, err = frontmatter(sk)
        if err:
            fail(f"{rel(sk)}: {err}")
            continue
        if fm.get("name") != d:
            fail(f"{rel(sk)}: name '{fm.get('name')}' 가 폴더명 '{d}' 와 다르다")
        if not fm.get("description"):
            fail(f"{rel(sk)}: description 이 비어 있다")
        oy = os.path.join(SKILLS, d, "agents", "openai.yaml")
        if not os.path.isfile(oy):
            fail(f"{rel(oy)} 없음")
            continue
        txt = read(oy)
        for k in ("display_name", "short_description", "default_prompt"):
            if not re.search(rf"^\s*{k}:", txt, re.M):
                fail(f"{rel(oy)}: {k} 없음")
    return f"스킬 {n}개"

def check_description():
    total = 0
    for d in skill_dirs():
        fm, err = frontmatter(os.path.join(SKILLS, d, "SKILL.md"))
        if err or not fm:
            continue
        n = len(fm.get("description", ""))
        total += n
        if n > DESC_EACH_MAX:
            fail(f"skills/{d}: description {n}자 > {DESC_EACH_MAX}자")
    if total > DESC_TOTAL_MAX:
        fail(f"description 합계 {total}자 > {DESC_TOTAL_MAX}자")
    return f"합계 {total}자 ≤ {DESC_TOTAL_MAX}자"

def check_forbidden():
    targets = [os.path.join(ROOT, "README.md")]
    for dp, _, fs in os.walk(PLUGIN):
        for f in fs:
            if f.endswith((".md", ".yaml", ".sh", ".json")):
                targets.append(os.path.join(dp, f))
    n = 0
    for p in sorted(targets):
        if p in HISTORY_DOCS or not os.path.isfile(p):
            continue
        n += 1
        for i, line in enumerate(read(p).split("\n"), 1):
            for pat in FORBIDDEN:
                if re.search(pat, line):
                    fail(f"{rel(p)}:{i}: 금칙어 /{pat}/ → {line.strip()[:60]}")
    return f"파일 {n}개"

def check_paths():
    n = 0
    for p in md_files(SKILLS, HISTORY_DOCS):
        skill_dir = os.path.join(SKILLS, rel(p).split(os.sep)[3])
        txt = read(p)
        refs = []
        # 스킬 폴더 기준 참조: `playbooks/x.md`, `templates/X.md`, "$S/scripts/x.sh"
        for m in re.finditer(r"`((?:playbooks|templates|references|scripts)/[^`\s]+)`", txt):
            refs.append((skill_dir, m.group(1)))
        for m in re.finditer(r"\$S/([^\s\"'`]+)", txt):
            refs.append((skill_dir, m.group(1)))
        # 파일 위치 기준 참조: 마크다운 링크 [..](path)
        for m in re.finditer(r"\]\(([^)\s]+)\)", txt):
            t = m.group(1).split("#")[0]
            if t and not re.match(r"^(https?:|mailto:)", t):
                refs.append((os.path.dirname(p), t))
        for base, r in refs:
            n += 1
            if not os.path.exists(os.path.join(base, r)):
                fail(f"{rel(p)}: 참조 '{r}' 가 없다")
    return f"참조 {n}개"

def check_scripts():
    paths = []
    for base in (SKILLS, ROOT):
        for dp, _, fs in os.walk(base):
            if os.path.basename(dp) != "scripts":
                continue
            paths += [os.path.join(dp, f) for f in fs if f.endswith(".sh")]
    paths = sorted(set(paths))
    for p in paths:
        if not os.access(p, os.X_OK):
            fail(f"{rel(p)}: 실행 비트 없음")
        r = subprocess.run(["bash", "-n", p], capture_output=True, text=True)
        if r.returncode != 0:
            fail(f"{rel(p)}: bash -n 실패 → {r.stderr.strip().splitlines()[-1] if r.stderr.strip() else ''}")
    return f"스크립트 {len(paths)}개"

def check_screens():
    n = 0
    for p in md_files(SKILLS, HISTORY_DOCS):
        for i, line in enumerate(read(p).split("\n"), 1):
            s = line.rstrip()
            if len(s) >= 10 and set(s) <= {"━"}:
                n += 1
                if len(s) != RULE_WIDTH:
                    fail(f"{rel(p)}:{i}: 굵은 선 {len(s)}칸 ≠ {RULE_WIDTH}칸")
            elif s.count("─") >= 6 and not s.lstrip().startswith("|"):
                n += 1
                w = width(s.strip())
                if w != RULE_WIDTH:
                    fail(f"{rel(p)}:{i}: 구역 제목 줄 표시 폭 {w}칸 ≠ {RULE_WIDTH}칸")
    return f"선 {n}개"

def check_lengths():
    limits = [(os.path.join(SKILLS, "go", "SKILL.md"), GO_SKILL_MAX),
              (os.path.join(SKILLS, "go", "references", "principles.md"), PRINCIPLES_MAX)]
    pb = os.path.join(SKILLS, "go", "playbooks")
    if os.path.isdir(pb):
        limits += [(os.path.join(pb, f), PLAYBOOK_MAX) for f in sorted(os.listdir(pb)) if f.endswith(".md")]
    for p, mx in limits:
        if not os.path.isfile(p):
            fail(f"{rel(p)} 없음")
            continue
        n = len(read(p).splitlines())
        if n > mx:
            fail(f"{rel(p)}: {n}줄 > {mx}줄")
    return f"파일 {len(limits)}개"

def check_versions():
    files = {
        os.path.join(PLUGIN, "plugin.json"): ("version",),
        os.path.join(PLUGIN, ".claude-plugin", "plugin.json"): ("version",),
        os.path.join(ROOT, ".claude-plugin", "marketplace.json"): ("metadata", "version"),
    }
    seen = {}
    for p, keys in files.items():
        try:
            v = json.loads(read(p))
            for k in keys:
                v = v[k]
            seen[rel(p)] = v
        except (OSError, ValueError, KeyError, TypeError) as e:
            fail(f"{rel(p)}: version 을 읽지 못함 ({e})")
    if len(set(seen.values())) > 1:
        fail("version 불일치 → " + ", ".join(f"{k}={v}" for k, v in seen.items()))
    return f"v{next(iter(seen.values()), '?')} · 파일 {len(seen)}개"

def check_readme():
    names = set(re.findall(r"^\| `([a-z-]+)` \|", read(os.path.join(ROOT, "README.md")), re.M))
    missing = [d for d in skill_dirs() if d not in names]
    if missing:
        fail("README.md 스킬 표에 없음: " + ", ".join(missing))
    return f"스킬 {len(skill_dirs())}개"

if not os.path.isdir(SKILLS):
    print(f"스킬 폴더가 없다: {rel(SKILLS)}", file=sys.stderr)
    sys.exit(2)

checks = [
    ("구조·frontmatter", check_structure),
    ("description 한도", check_description),
    ("금칙어", check_forbidden),
    ("경로 참조", check_paths),
    ("스크립트", check_scripts),
    ("화면 선 폭", check_screens),
    ("분량 한도", check_lengths),
    ("버전 일치", check_versions),
    ("README 목록", check_readme),
]
for name, fn in checks:
    run(name, fn)
print(f"검사 {len(checks)}개 · 실패 {len(fails)}개")
sys.exit(1 if fails else 0)
PY
