#!/bin/bash
export SUPPRESS_LABEL_WARNING=True
SSH_KEY="$HOME/.oci/ssh.pub"
RUN_URL="$GITHUB_SERVER_URL/$GITHUB_REPOSITORY/actions/runs/$GITHUB_RUN_ID"

# Mensaje al canal (progreso)
notify() {
  if [ -n "$DISCORD_WEBHOOK" ]; then
    curl -s -H "Content-Type: application/json" \
      -d "$(jq -n --arg c "$1" '{content:$c}')" \
      "$DISCORD_WEBHOOK" > /dev/null || true
  fi
  return 0
}

# Mensaje directo (solo éxito)
notify_dm() {
  if [ -n "$DISCORD_BOT_TOKEN" ] && [ -n "$DISCORD_USER_ID" ]; then
    CH=$(curl -s -X POST "https://discord.com/api/v10/users/@me/channels" \
      -H "Authorization: Bot $DISCORD_BOT_TOKEN" \
      -H "Content-Type: application/json" \
      -d "{\"recipient_id\":\"$DISCORD_USER_ID\"}" | jq -r '.id // empty')
    if [ -n "$CH" ]; then
      curl -s -X POST "https://discord.com/api/v10/channels/$CH/messages" \
        -H "Authorization: Bot $DISCORD_BOT_TOKEN" \
        -H "Content-Type: application/json" \
        -d "$(jq -n --arg c "$1" '{content:$c}')" > /dev/null || true
    fi
  fi
  return 0
}

HORA=$(TZ="America/Santiago" date '+%H:%M')

EXISTE=$(oci compute instance list --compartment-id "$TENANCY" \
  --display-name homelab-a1 \
  --query "data[?\"lifecycle-state\"!='TERMINATED'] | length(@)" \
  --raw-output 2>/dev/null)
if [ "${EXISTE:-0}" != "0" ]; then
  echo "La instancia ya existe, nada que hacer."
  exit 0
fi

IMAGE_ID=$(oci compute image list --compartment-id "$TENANCY" \
  --operating-system "Canonical Ubuntu" --operating-system-version "24.04" \
  --shape VM.Standard.A1.Flex --sort-by TIMECREATED --sort-order DESC \
  --query 'data[0].id' --raw-output 2>/dev/null)
if [ -z "$IMAGE_ID" ]; then
  echo "No pude obtener la imagen"
  notify "⚠️ [$HORA] No pude obtener la imagen: $RUN_URL"
  exit 1
fi

set +e
SALIDA=$(oci compute instance launch \
  --availability-domain "$AD" \
  --compartment-id "$TENANCY" \
  --display-name "homelab-a1" \
  --shape "VM.Standard.A1.Flex" \
  --shape-config '{"ocpus":1,"memoryInGB":6}' \
  --image-id "$IMAGE_ID" \
  --subnet-id "$SUBNET_ID" \
  --assign-public-ip true \
  --ssh-authorized-keys-file "$SSH_KEY" 2>&1)
RC=$?
set -e

if [[ $RC -eq 0 && "$SALIDA" == *"ocid1.instance"* ]]; then
  echo "ÉXITO"
  notify "✅ [$HORA] Intento #$GITHUB_RUN_NUMBER: ¡instancia creada!"
  notify_dm "🎉 ¡Tu instancia A1 en Oracle Santiago fue creada! Revisa la consola. Run #$GITHUB_RUN_NUMBER: $RUN_URL"
  exit 0
elif [[ "${SALIDA,,}" == *"capacity"* ]]; then
  echo "Sin stock."
  notify "❌ [$HORA] Intento #$GITHUB_RUN_NUMBER: sin stock"
elif [[ "$SALIDA" == *"TooManyRequests"* ]]; then
  echo "Rate limit, se reintenta en la próxima ejecución."
  notify "⏳ [$HORA] Intento #$GITHUB_RUN_NUMBER: rate limit"
else
  echo "Error distinto:"; echo "$SALIDA"
  notify "⚠️ [$HORA] Intento #$GITHUB_RUN_NUMBER: error inesperado: $RUN_URL"
  exit 1
fi
