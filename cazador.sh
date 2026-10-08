#!/bin/bash
export SUPPRESS_LABEL_WARNING=True
SSH_KEY="$HOME/.oci/ssh.pub"

notify() {
  [ -n "$DISCORD_WEBHOOK" ] && curl -s -H "Content-Type: application/json" \
    -d "{\"content\":\"$1\"}" "$DISCORD_WEBHOOK" > /dev/null
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

if [[ $RC -eq 0 && "$SALIDA" == *"ocid1.instance"* ]]; then
  echo "ÉXITO"
  notify "✅ ¡Instancia A1 creada en Oracle Santiago! Revisa la consola."
elif [[ "${SALIDA,,}" == *"capacity"* ]]; then
  echo "Sin stock."
elif [[ "$SALIDA" == *"TooManyRequests"* ]]; then
  echo "Rate limit, se reintenta en la próxima ejecución."
else
  echo "Error distinto:"; echo "$SALIDA"
  notify "⚠️ Cazador OCI: error inesperado, revisa los logs de Actions."
  exit 1
fi
