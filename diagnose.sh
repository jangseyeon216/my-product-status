#!/bin/bash
# ccusage 온보딩 자동 설정 스크립트
# 사용법: bash <(curl -s https://ccusage.plusxdev.com/install/diagnose.sh)

SERVER="https://ccusage.plusxdev.com"
SCRIPT="$HOME/claude_report.py"
TOKEN_FILE="$HOME/.claude_report_token"
EMAIL_FILE="$HOME/.claude_report_email"
CONSENT_FILE="$HOME/.claude_report_consent"

PASS="✅"; FAIL="❌"; WARN="⚠️ "; FIX="🔧"

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  ccusage 자동 설정  |  $(date '+%Y-%m-%d %H:%M')"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# ── 유틸 함수 ────────────────────────────────────────

ask_yn() {
  # ask_yn "질문" → 0=yes, 1=no
  local prompt="$1"
  while true; do
    printf "  %s [y/n] " "$prompt"
    read -r ans </dev/tty
    case "$ans" in
      [Yy]*) return 0 ;;
      [Nn]*) return 1 ;;
      *) echo "  y 또는 n 으로 답해주세요." ;;
    esac
  done
}

download_script() {
  echo "  ${FIX} 스크립트 다운로드 중..."
  if curl -fsSL -o "$SCRIPT" "$SERVER/install/claude_report.py" 2>/dev/null; then
    echo "  ${PASS} 다운로드 완료"
    return 0
  else
    echo "  ${FAIL} 다운로드 실패 — 네트워크 또는 서버 확인 필요"
    return 1
  fi
}

get_embedded_token() {
  grep '^INGEST_TOKEN' "$SCRIPT" 2>/dev/null \
    | head -1 | sed 's/.*= *"//' | sed 's/".*//' | tr -d '[:space:]'
}

get_effective_token() {
  local t="${CLAUDE_REPORT_INGEST_TOKEN:-}"
  [ -z "$t" ] && [ -f "$TOKEN_FILE" ] && t=$(cat "$TOKEN_FILE" | tr -d '[:space:]')
  [ -z "$t" ] && [ -f "$SCRIPT" ] && t=$(get_embedded_token)
  echo "$t"
}

test_token() {
  local tok="$1"
  [ -z "$tok" ] && return 1
  local code
  code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 8 \
    -X POST "$SERVER/api/usage/report" \
    -H "Content-Type: application/json" \
    -H "X-Ingest-Token: $tok" \
    -d '{"email":"__diag__@plus-ex.com","projects":[]}' 2>/dev/null)
  # 400 = 이메일 검증 단계까지 도달 = 토큰 OK
  [ "$code" = "400" ] && return 0 || return 1
}

test_email() {
  local tok="$1" email="$2"
  [ -z "$tok" ] || [ -z "$email" ] && return 1
  local resp
  resp=$(curl -s --max-time 8 \
    -X POST "$SERVER/api/usage/report" \
    -H "Content-Type: application/json" \
    -H "X-Ingest-Token: $tok" \
    -d "{\"email\":\"$email\",\"projects\":[]}" 2>/dev/null)
  echo "$resp" | grep -q "등록된 멤버" && return 1 || return 0
}

# ═══════════════════════════════════════════════════
# STEP 1 — 서버 연결
# ═══════════════════════════════════════════════════
echo "[1/5] 서버 연결 확인"
HTTP=$(curl -s -o /dev/null -w "%{http_code}" --max-time 6 "$SERVER" 2>/dev/null)
case "$HTTP" in
  200|301|302|307|308)
    echo "  ${PASS} $SERVER 응답 정상 (HTTP $HTTP)" ;;
  ""|000)
    echo "  ${FAIL} 서버에 접속할 수 없습니다."
    echo "       → Wi-Fi / VPN 연결을 확인하고 다시 실행해 주세요."
    exit 1 ;;
  *)
    echo "  ${WARN} HTTP $HTTP — 계속 진행합니다." ;;
esac
echo ""

# ═══════════════════════════════════════════════════
# STEP 2 — 스크립트 & 토큰 확인 (자동 복구)
# ═══════════════════════════════════════════════════
echo "[2/5] 스크립트 & 토큰"

NEED_DOWNLOAD=false

if [ ! -f "$SCRIPT" ]; then
  echo "  ${FAIL} 스크립트 없음"
  NEED_DOWNLOAD=true
else
  VER=$(grep '^VERSION' "$SCRIPT" 2>/dev/null | head -1 | grep -o '"[^"]*"' | tr -d '"')
  EMB=$(get_embedded_token)
  if [ -z "$EMB" ] || [ "$EMB" = "{{INGEST_TOKEN}}" ]; then
    echo "  ${WARN} 스크립트(v${VER:-?}) 있으나 토큰 없음 → 재다운로드"
    NEED_DOWNLOAD=true
  else
    echo "  ${PASS} 스크립트 v${VER:-?}, 토큰 주입됨 (길이: ${#EMB}자)"
  fi
fi

if $NEED_DOWNLOAD; then
  if download_script; then
    EMB=$(get_embedded_token)
    if [ -z "$EMB" ] || [ "$EMB" = "{{INGEST_TOKEN}}" ]; then
      echo "  ${FAIL} 재다운로드했으나 토큰이 여전히 없습니다."
      echo "       → june@plus-ex.com 에 문의해 주세요."
      exit 1
    fi
    echo "  ${PASS} 토큰 주입 확인 (길이: ${#EMB}자)"
  else
    exit 1
  fi
fi
echo ""

# ═══════════════════════════════════════════════════
# STEP 3 — 토큰 인증 테스트 (자동 복구)
# ═══════════════════════════════════════════════════
echo "[3/5] 토큰 인증"

TOKEN=$(get_effective_token)
SOURCE="스크립트 내 토큰"
[ -f "$TOKEN_FILE" ] && [ -n "$(cat "$TOKEN_FILE" | tr -d '[:space:]')" ] && SOURCE="~/.claude_report_token"
[ -n "$CLAUDE_REPORT_INGEST_TOKEN" ] && SOURCE="환경변수"

if test_token "$TOKEN"; then
  echo "  ${PASS} 인증 성공 ($SOURCE 사용)"
else
  echo "  ${FAIL} 인증 실패 — 저장된 토큰이 만료되었을 수 있습니다."
  # 저장 토큰 삭제 후 스크립트 토큰으로 재시도
  if [ -f "$TOKEN_FILE" ]; then
    echo "  ${FIX} 저장된 토큰 초기화 후 재시도..."
    rm -f "$TOKEN_FILE"
    TOKEN=$(get_embedded_token)
    SOURCE="스크립트 내 토큰"
    if test_token "$TOKEN"; then
      echo "  ${PASS} 재시도 성공"
    else
      # 스크립트 자체를 재다운로드
      echo "  ${FIX} 스크립트 재다운로드 후 재시도..."
      rm -f "$SCRIPT"
      if download_script; then
        TOKEN=$(get_embedded_token)
        if test_token "$TOKEN"; then
          echo "  ${PASS} 재다운로드 후 인증 성공"
        else
          echo "  ${FAIL} 모든 복구 시도 실패 — june@plus-ex.com 에 문의해 주세요."
          exit 1
        fi
      else
        exit 1
      fi
    fi
  fi
fi
echo ""

# ═══════════════════════════════════════════════════
# STEP 4 — 이메일 확인 및 등록 테스트
# ═══════════════════════════════════════════════════
echo "[4/5] 이메일 확인"

# 이메일 결정
EMAIL=""
[ -f "$EMAIL_FILE" ] && EMAIL=$(cat "$EMAIL_FILE" | tr -d '[:space:]')

if [ -z "$EMAIL" ]; then
  echo "  저장된 이메일이 없습니다."
  printf "  Plus X 이메일을 입력하세요 (예: name@plus-ex.com): "
  read -r EMAIL </dev/tty
  EMAIL=$(echo "$EMAIL" | tr -d '[:space:]')
fi

if [ -z "$EMAIL" ]; then
  echo "  ${FAIL} 이메일 없이는 진행할 수 없습니다."
  exit 1
fi

echo "  확인 중: $EMAIL"

if test_email "$TOKEN" "$EMAIL"; then
  echo "  ${PASS} $EMAIL 등록 확인됨"
  echo "$EMAIL" > "$EMAIL_FILE"
else
  echo "  ${FAIL} $EMAIL 이 서버에 등록되어 있지 않습니다."
  echo ""
  echo "       등록 방법 2가지 중 선택하세요:"
  echo ""
  echo "       A) june@plus-ex.com 에 Slack / 문자로 이메일 등록 요청"
  echo "          → 등록 완료 후 이 스크립트를 다시 실행"
  echo ""
  echo "       B) 이메일을 변경해서 재시도 (다른 plus-ex.com 계정이 있다면)"
  echo ""
  if ask_yn "B) 다른 이메일로 재시도하시겠습니까?"; then
    printf "  새 이메일 입력: "
    read -r EMAIL </dev/tty
    EMAIL=$(echo "$EMAIL" | tr -d '[:space:]')
    if test_email "$TOKEN" "$EMAIL"; then
      echo "  ${PASS} $EMAIL 등록 확인됨"
      echo "$EMAIL" > "$EMAIL_FILE"
    else
      echo "  ${FAIL} $EMAIL 도 등록되지 않았습니다."
      echo "       → june@plus-ex.com 에 이메일 등록 요청 후 다시 실행해 주세요."
      exit 1
    fi
  else
    echo ""
    echo "  등록 완료 후 다시 실행해 주세요:"
    echo "  bash <(curl -s $SERVER/install/diagnose.sh)"
    exit 0
  fi
fi
echo ""

# ═══════════════════════════════════════════════════
# STEP 5 — Claude Code 데이터 확인 후 실행
# ═══════════════════════════════════════════════════
echo "[5/5] Claude Code 데이터"

CLAUDE_PROJECTS="$HOME/.claude/projects"
if [ -d "$CLAUDE_PROJECTS" ]; then
  JSONL_COUNT=$(find "$CLAUDE_PROJECTS" -name "*.jsonl" 2>/dev/null | wc -l | tr -d ' ')
  if [ "$JSONL_COUNT" = "0" ]; then
    echo "  ${WARN} $CLAUDE_PROJECTS 있지만 JSONL 파일 없음"
    echo "       → Claude Code를 아직 사용하지 않았거나 다른 경로일 수 있습니다."
    echo "       → 전송할 데이터가 없어도 계속 진행은 가능합니다."
  else
    echo "  ${PASS} JSONL 파일 ${JSONL_COUNT}개 발견"
  fi
else
  echo "  ${FAIL} $CLAUDE_PROJECTS 없음"
  echo "       Claude Code가 설치되어 있지 않거나 한 번도 실행하지 않은 상태입니다."
  echo "       Claude Code 설치 후 다시 실행해 주세요."
  echo "       설치: https://claude.ai/download"
  if ! ask_yn "그래도 지금 데이터 전송을 시도하시겠습니까?"; then
    exit 0
  fi
fi
echo ""

# ═══════════════════════════════════════════════════
# 실행
# ═══════════════════════════════════════════════════
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  모든 확인 완료 — 데이터 전송 시작"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# 토큰을 파일에 저장 (다음 실행부터 자동 사용)
echo "$TOKEN" > "$TOKEN_FILE"

# 동의 파일이 없으면 미리 생성 (스크립트 내 프롬프트 생략)
if [ ! -f "$CONSENT_FILE" ]; then
  echo "  수집 항목: 이메일, 프로젝트명, 토큰 사용량(숫자). 대화 내용 수집 안 함."
  if ask_yn "  동의하시겠습니까?"; then
    date -u +"%Y-%m-%dT%H:%M:%SZ" > "$CONSENT_FILE"
    echo "  ${PASS} 동의 완료"
  else
    echo "  전송을 취소합니다."
    exit 0
  fi
  echo ""
fi

python3 "$SCRIPT" --email "$EMAIL" --backfill-2026

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  완료! https://ccusage.plusxdev.com/ccusage 에서 확인하세요."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
