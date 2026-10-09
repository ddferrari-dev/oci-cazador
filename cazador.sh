#!/bin/bash
export SUPPRESS_LABEL_WARNING=True
SSH_KEY="$HOME/.oci/ssh.pub"

notify() {
  [ -z "$DISCORD_WEBHOOK" ] && return
  curl -s -H "Content-Type: application/json" \
    -d "$(jq -n --arg c "$1" '{content:$c}')" \
    "$DISCORD_WEBHOOK" > /dev/null
}
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
[ -z "$IMAGE_ID" ] && { echo "No pude obtener la imagen"; exit 1; }

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

ESTADO="desconocido"

if [[ $RC -eq 0 && "$SALIDA" == *"ocid1.instance"* ]]; then
  echo "ÉXITO"
  notify "✅ @everyone ¡Instancia A1 creada en Oracle Santiago! Revisa la consola."
  exit 0
elif [[ "${SALIDA,,}" == *"capacity"* ]]; then
  ESTADO="sin stock"
elif [[ "$SALIDA" == *"TooManyRequests"* ]]; then
  ESTADO="rate limit"
else
  echo "Error distinto:"; echo "$SALIDA"
  notify "⚠️ Cazador OCI: error inesperado. Revisa los logs: $GITHUB_SERVER_URL/$GITHUB_REPOSITORY/actions/runs/$GITHUB_RUN_ID"
  exit 1
fi

echo "$ESTADO"

# Resumen de progreso cada 72 ejecuciones
if [ $((GITHUB_RUN_NUMBER % 72)) -eq 0 ]; then
  notify "🔎 Cazador OCI sigue activo. Ejecución #$GITHUB_RUN_NUMBER, último resultado: $ESTADO."
fi
