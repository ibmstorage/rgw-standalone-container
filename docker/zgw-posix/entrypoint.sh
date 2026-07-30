#!/bin/bash
set -euo pipefail

# Default component if none supplied
COMPONENT=${COMPONENT:-zgw-posix}

# Writable config location (for OpenShift/restricted environments)
CEPH_CONF_DIR="/var/lib/ceph/radosgw"
CEPH_CONF="${CEPH_CONF_DIR}/ceph.conf"

########################################
# Helpers                              #
########################################
ensure_paths() {
  # Create POSIX driver directories so LMDB init won't abort
  mkdir -p "${RGW_POSIX_BASE_PATH}" \
           "${RGW_POSIX_DATABASE_ROOT}" \
           "${RGW_POSIX_DATABASE_ROOT}/rgw_posix_lmdbs" \
           "${CEPH_CONF_DIR}"
  chown -R ceph:ceph "${RGW_POSIX_BASE_PATH}" "${RGW_POSIX_DATABASE_ROOT}" "${CEPH_CONF_DIR}" 2>/dev/null || true
}

create_ceph_conf() {
  # Create ceph.conf in writable location with all required settings.
  # NOTE: rgw_frontends is NOT set here — it is passed as a CLI argument to
  # radosgw so it takes highest priority and cannot be overridden by the
  # config store (which would replace cert paths with config:// URIs).
  cat > "${CEPH_CONF}" <<EOF
[client]
    rgw backend store = posix
    rgw config store = dbstore
    rgw_posix_base_path = ${RGW_POSIX_BASE_PATH}
    rgw_posix_database_root = ${RGW_POSIX_DATABASE_ROOT}
EOF

  chown ceph:ceph "${CEPH_CONF}" 2>/dev/null || true
}

apply_quotas() {
  local uid="$1"

  # User quota — total across all buckets for this user
  if [[ -n "${RGW_USER_QUOTA_MAX_SIZE:-}" || "${RGW_USER_QUOTA_MAX_OBJECTS:-}" != "" ]]; then
    echo "Applying user quota for ${uid}..."
    local args=(quota set --uid="${uid}" --quota-scope=user)
    [[ -n "${RGW_USER_QUOTA_MAX_SIZE:-}" ]]    && args+=(--max-size="${RGW_USER_QUOTA_MAX_SIZE}")
    [[ -n "${RGW_USER_QUOTA_MAX_OBJECTS:-}" ]] && args+=(--max-objects="${RGW_USER_QUOTA_MAX_OBJECTS}")
    rgw-standalone-admin -c "${CEPH_CONF}" "${args[@]}"
    rgw-standalone-admin -c "${CEPH_CONF}" quota enable --uid="${uid}" --quota-scope=user
  fi

  # Bucket quota — per bucket
  if [[ -n "${RGW_BUCKET_QUOTA_MAX_SIZE:-}" || "${RGW_BUCKET_QUOTA_MAX_OBJECTS:-}" != "" ]]; then
    echo "Applying bucket quota for ${uid}..."
    local args=(quota set --uid="${uid}" --quota-scope=bucket)
    [[ -n "${RGW_BUCKET_QUOTA_MAX_SIZE:-}" ]]    && args+=(--max-size="${RGW_BUCKET_QUOTA_MAX_SIZE}")
    [[ -n "${RGW_BUCKET_QUOTA_MAX_OBJECTS:-}" ]] && args+=(--max-objects="${RGW_BUCKET_QUOTA_MAX_OBJECTS}")
    rgw-standalone-admin -c "${CEPH_CONF}" "${args[@]}"
    rgw-standalone-admin -c "${CEPH_CONF}" quota enable --uid="${uid}" --quota-scope=bucket
  fi
}

create_default_user() {
  ensure_paths
  create_ceph_conf

  local desired_access="${AWS_ACCESS_KEY_ID:-zippy}"
  local desired_secret="${AWS_SECRET_ACCESS_KEY:-zippy}"

  if ! rgw-standalone-admin -c "${CEPH_CONF}" user info --uid=zippy &>/dev/null; then
    # User doesn't exist — create it fresh
    set +e
    rgw-standalone-admin -c "${CEPH_CONF}" user create \
      --uid zippy \
      --display-name zippy \
      --access-key "${desired_access}" \
      --secret-key "${desired_secret}"
    set -e
  else
    # User exists — check if keys need updating.
    # IMPORTANT: We never delete the user, only rotate keys, to preserve all
    # bucket data when PVs are reused or the container is restarted.
    local user_info current_access current_secret
    user_info=$(rgw-standalone-admin -c "${CEPH_CONF}" user info --uid=zippy 2>/dev/null)

    current_access=$(echo "${user_info}" \
      | python3 -c "import sys,json; keys=json.load(sys.stdin).get('keys',[]); print(keys[0]['access_key'] if keys else '')" \
      2>/dev/null || echo "")
    current_secret=$(echo "${user_info}" \
      | python3 -c "import sys,json; keys=json.load(sys.stdin).get('keys',[]); print(keys[0]['secret_key'] if keys else '')" \
      2>/dev/null || echo "")

    if [[ "${current_access}" != "${desired_access}" || "${current_secret}" != "${desired_secret}" ]]; then
      echo "Updating S3 credentials for user zippy..."
      set +e
      # Add/update the desired key pair (key create is idempotent: updates secret
      # if the access key already exists, or adds a new key pair if it doesn't).
      rgw-standalone-admin -c "${CEPH_CONF}" key create \
        --uid zippy \
        --access-key "${desired_access}" \
        --secret-key "${desired_secret}"

      # If the access key itself changed, remove the old one so only the new
      # key is active. The user and all their bucket data remain intact.
      if [[ "${current_access}" != "${desired_access}" && -n "${current_access}" ]]; then
        rgw-standalone-admin -c "${CEPH_CONF}" key rm \
          --uid zippy \
          --access-key "${current_access}"
      fi
      set -e
    fi
  fi

  # Apply quotas if configured via environment variables
  apply_quotas zippy

  # Fix ownership of LMDB files created by rgw-standalone-admin (runs as root).
  # Without this, radosgw (running as ceph) cannot access the POSIX filter's
  # LMDB databases and the filter silently fails to load.
  chown -R ceph:ceph "${RGW_POSIX_BASE_PATH}" "${RGW_POSIX_DATABASE_ROOT}" 2>/dev/null || true
}

########################################
# Component dispatch                   #
########################################
case "${COMPONENT}" in
  zgw-posix|zgw-dbstore)
    create_default_user

    # Build the beast frontend string. Passing it as a CLI arg gives it the
    # highest priority in Ceph's config hierarchy, preventing the config store
    # from overriding our cert paths with config:// URIs.
    RGW_FRONTEND="beast port=7480"
    if [[ "${RGW_TLS_ENABLED:-false}" == "true" ]]; then
      RGW_FRONTEND="${RGW_FRONTEND} ssl_port=7443 ssl_certificate=${RGW_TLS_CERT_PATH:-/etc/ceph/tls/tls.crt} ssl_private_key=${RGW_TLS_KEY_PATH:-/etc/ceph/tls/tls.key}"
      echo "RGW frontend: HTTP on 7480, HTTPS on 7443 (cert: ${RGW_TLS_CERT_PATH:-/etc/ceph/tls/tls.crt})"
    fi

    exec /usr/bin/rgw-standalone \
      -c "${CEPH_CONF}" \
      --cluster ceph \
      --setuser ceph \
      --setgroup ceph \
      --default-log-to-stderr=true \
      --err-to-stderr=true \
      --default-log-to-file=false \
      --foreground \
      -n client.rgw \
      --no-mon-config \
      --rgw-frontends "${RGW_FRONTEND}"
    ;;
  zgw-toolbox)
    echo "Toolbox container — sleeping indefinitely"
    exec sleep infinity
    ;;
  *)
    # Any other command: just run it
    exec "$@"
    ;;
esac
