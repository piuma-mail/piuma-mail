#!/bin/sh
# Starts a throwaway Dovecot IMAP server for the engine's integration tests.
#
#   tools/test-imap-server.sh            # listens on 127.0.0.1:31143
#   PIUMA_TEST_IMAP=127.0.0.1:31143 cargo test
#
# Users: any name with password "test" (e.g. alice / test). Mail lives in a
# temporary folder that is deleted when the server stops (Ctrl+C).
# Needs Dovecot 2.3 or 2.4 (apt install dovecot-imapd), or Docker:
#   docker run --rm --network host -v "$PWD/tools:/tools:ro" --entrypoint sh \
#     dovecot/dovecot:2.3.21.1 /tools/test-imap-server.sh
# (host network: it listens on 127.0.0.1 only).
set -eu
PORT="${PORT:-31143}"
DIR="$(mktemp -d)"
trap 'kill "$(cat "$DIR/run/master.pid" 2>/dev/null)" 2>/dev/null; rm -rf "$DIR"' EXIT INT TERM
mkdir -p "$DIR/run" "$DIR/mail"
# Dovecot refuses to run its workers as root: borrow its own user then.
if [ "$(id -u)" = 0 ]; then
  RUN_USER=dovecot
  chown -R dovecot "$DIR"
else
  RUN_USER="$(id -un)"
fi
RUN_UID="$(id -u "$RUN_USER")"
RUN_GID="$(id -g "$RUN_USER")"
# Dovecot 2.4 renamed most of these settings and wants its configuration
# version first; 2.3 (Debian 12, Ubuntu 24.04 and older, the 2.3 image)
# refuses the new names. Both get the same server.
VERSION="$(dovecot --version | cut -d' ' -f1)"
case "$VERSION" in
  2.[0-3].*) NEW=no ;;
  *) NEW=yes ;;
esac
{
  if [ "$NEW" = yes ]; then
    cat <<CONF
dovecot_config_version = 2.4.0
dovecot_storage_version = 2.4.0
CONF
  fi
  cat <<CONF
protocols = imap
listen = 127.0.0.1
base_dir = $DIR/run
state_dir = $DIR/run
log_path = $DIR/dovecot.log
default_login_user = $RUN_USER
default_internal_user = $RUN_USER
default_internal_group = $(id -gn "$RUN_USER")
ssl = no
auth_mechanisms = plain login
mail_uid = $RUN_UID
mail_gid = $RUN_GID
first_valid_uid = 0
# "Still here" every second during IDLE, as servers do every few minutes:
# the engine must still give up waiting on time.
imap_idle_notify_interval = 1 secs
namespace inbox {
  inbox = yes
  mailbox Sent {
    special_use = \\Sent
    auto = subscribe
  }
}
service imap-login {
  inet_listener imap {
    port = $PORT
  }
  inet_listener imaps {
    port = 0
  }
}
service anvil {
  chroot =
}
service imap-login {
  chroot =
}
CONF
  if [ "$NEW" = yes ]; then
    cat <<CONF
auth_allow_cleartext = yes
mail_driver = maildir
mail_path = $DIR/mail/%{user}
mail_home = $DIR/mail/%{user}
passdb static {
  password = test
}
userdb static {
  fields {
    uid = $RUN_UID
    gid = $RUN_GID
    home = $DIR/mail/%{user}
  }
}
CONF
  else
    cat <<CONF
disable_plaintext_auth = no
mail_location = maildir:$DIR/mail/%u
passdb {
  driver = static
  args = password=test
}
userdb {
  driver = static
  args = uid=$RUN_UID gid=$RUN_GID home=$DIR/mail/%u
}
CONF
  fi
} > "$DIR/dovecot.conf"
echo "Dovecot $VERSION on 127.0.0.1:$PORT (log: $DIR/dovecot.log)"
dovecot -F -c "$DIR/dovecot.conf"
