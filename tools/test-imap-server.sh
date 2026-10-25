#!/bin/sh
# Starts a throwaway Dovecot IMAP server for the engine's integration tests.
#
#   tools/test-imap-server.sh            # listens on 127.0.0.1:31143
#   PIUMA_TEST_IMAP=127.0.0.1:31143 cargo test
#
# Users: any name with password "test" (e.g. alice / test). Mail lives in a
# temporary folder that is deleted when the server stops (Ctrl+C).
# Needs dovecot-imapd (apt install dovecot-imapd) or use Docker:
#   docker run --rm -p 31143:31143 -v "$PWD/tools:/tools" dovecot/dovecot sh /tools/test-imap-server.sh
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
cat > "$DIR/dovecot.conf" <<CONF
protocols = imap
listen = 127.0.0.1
base_dir = $DIR/run
state_dir = $DIR/run
log_path = $DIR/dovecot.log
default_login_user = $RUN_USER
default_internal_user = $RUN_USER
default_internal_group = $(id -gn "$RUN_USER")
ssl = no
disable_plaintext_auth = no
auth_mechanisms = plain login
mail_location = maildir:$DIR/mail/%u
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
passdb {
  driver = static
  args = password=test
}
userdb {
  driver = static
  args = uid=$RUN_UID gid=$RUN_GID home=$DIR/mail/%u
}
service imap-login {
  inet_listener imap {
    address = 127.0.0.1
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
echo "Dovecot on 127.0.0.1:$PORT (log: $DIR/dovecot.log)"
dovecot -F -c "$DIR/dovecot.conf"
