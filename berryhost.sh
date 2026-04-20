#!/bin/bash
# ===== 个人配置（通过 GitHub Secrets 注入，无需修改）=====
: "${DISCORD_TOKEN:?请设置 GitHub Secret: DISCORD_TOKEN}"
: "${SESSION_ID:?请设置 GitHub Secret: SESSION_ID}"

# ===== 公共配置（所有人相同，无需修改）=====
GUILD_ID="1453168143865352374"
CHANNEL_ID="1453169471681200293"
CUSTOM_ID="daily_claim_button"

# ===== 代理配置（有 GOST_PROXY 时使用，否则直连）=====
if [ -n "$GOST_PROXY" ]; then
  PROXY="-x http://127.0.0.1:1080"
  echo "🛡️ 使用代理模式"
else
  PROXY=""
  echo "🌐 直连模式（GitHub Actions IP）"
fi

echo "🕐 运行时间: $(date '+%Y-%m-%d %H:%M:%S')"
echo "🎮 TheBerryHost 每日领取"
echo "========================================"

# ===== 动态获取 MESSAGE_ID / APPLICATION_ID =====
echo "🔍 正在获取最新签到消息..."

read MESSAGE_ID APPLICATION_ID < <(curl -s $PROXY \
  "https://discord.com/api/v9/channels/${CHANNEL_ID}/messages?limit=20" \
  -H "authorization: ${DISCORD_TOKEN}" \
  -H "user-agent: Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/145.0.0.0 Safari/537.36" \
  | python3 -c "
import json, sys
try:
    msgs = json.load(sys.stdin)
    for m in msgs:
        if m.get('components'):
            print(m['id'], m['author']['id'])
            exit()
    print('NOT_FOUND NOT_FOUND')
except:
    print('NOT_FOUND NOT_FOUND')
")

if [ "$MESSAGE_ID" = "NOT_FOUND" ]; then
  echo "❌ 未找到签到消息，请检查 Token 是否有效"
  RESULT="❌ 未找到签到消息"
else
  echo "📌 MESSAGE_ID:     $MESSAGE_ID"
  echo "🤖 APPLICATION_ID: $APPLICATION_ID"

  # ===== 生成 nonce =====
  NONCE=$(python3 -c "import time; print(str(int((int(time.time()*1000) - 1420070400000) << 22)))")

  # ===== 发送交互请求 =====
  echo "🚀 正在提交签到..."

  RESPONSE=$(curl -s -w "\n%{http_code}" $PROXY \
    -X POST "https://discord.com/api/v9/interactions" \
    -H "authorization: ${DISCORD_TOKEN}" \
    -H "content-type: application/json" \
    -H "user-agent: Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/145.0.0.0 Safari/537.36" \
    -H "x-discord-locale: zh-CN" \
    -H "x-discord-timezone: Asia/Shanghai" \
    -H "origin: https://discord.com" \
    -H "referer: https://discord.com/channels/${GUILD_ID}/${CHANNEL_ID}" \
    -d "{\"type\":3,\"nonce\":\"${NONCE}\",\"guild_id\":\"${GUILD_ID}\",\"channel_id\":\"${CHANNEL_ID}\",\"message_flags\":0,\"message_id\":\"${MESSAGE_ID}\",\"application_id\":\"${APPLICATION_ID}\",\"session_id\":\"${SESSION_ID}\",\"data\":{\"component_type\":2,\"custom_id\":\"${CUSTOM_ID}\"}}")

  HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
  BODY=$(echo "$RESPONSE" | head -n-1)

  if [ "$HTTP_CODE" = "204" ]; then
    echo "✅ 成功！状态码: 204"
    echo "🎉 已成功点击 Claim Daily Reward！"
    RESULT="✅ 领取成功！"
  else
    echo "❌ 失败！状态码: ${HTTP_CODE}"
    echo "   响应: ${BODY}"
    case "$HTTP_CODE" in
      429) RESULT="❌ 失败！触发频率限制（rate limit）" ;;
      401) RESULT="❌ 失败！Token 失效，需要重新获取" ;;
      403) RESULT="❌ 失败！无权限" ;;
      *)   RESULT="❌ 失败！状态码: ${HTTP_CODE}" ;;
    esac
  fi
fi

# ===== TG 通知 =====
if [ -n "$TG_BOT" ]; then
  TG_CHAT_ID=$(echo "$TG_BOT" | cut -d',' -f1)
  TG_TOKEN=$(echo "$TG_BOT" | cut -d',' -f2)
  RUN_TIME=$(date '+%Y-%m-%d %H:%M:%S')

  if [[ "$RESULT" == ✅* ]]; then
    REWARD_LINE="🎉 今日奖励: 💰 5 BerryCoins"
  else
    REWARD_LINE="🎉 今日奖励: 💰 0 BerryCoins"
  fi

  MESSAGE="🍇 TheBerryHost 每日领取
🕐 运行时间: ${RUN_TIME}
🎮 服务器: 🇬🇧 TheBerryHost
📊 领取结果: ${RESULT}
${REWARD_LINE}"

  curl -s -X POST "https://api.telegram.org/bot${TG_TOKEN}/sendMessage" \
    -d chat_id="${TG_CHAT_ID}" \
    -d text="${MESSAGE}" > /dev/null
  echo "📬 TG 通知已发送"
fi

# ===== 最终退出码 =====
if [[ "$RESULT" == ✅* ]]; then
  exit 0
else
  exit 1
fi
