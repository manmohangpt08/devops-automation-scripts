#!/bin/bash

MAIL_RC="/etc/mail.rc"
BACKUP_FILE="/etc/mail.rc.bak"
SMTP_MARKER="set smtp-auth-user="

# Function to prompt for user input with confirmation
prompt_credentials() {
  echo "Enter your Gmail address (smtp-auth-user):"
  read -r smtp_user

  while true; do
    echo -n "Enter your Gmail app password: "
    read -s smtp_pass1
    echo
    echo -n "Confirm your Gmail app password: "
    read -s smtp_pass2
    echo

    if [[ "$smtp_pass1" == "$smtp_pass2" ]]; then
      smtp_pass="$smtp_pass1"
      break
    else
      echo "❌ Passwords do not match. Please try again."
    fi
  done
}

# Function to append SMTP configuration to mail.rc
append_config() {
  echo "🔁 Backing up $MAIL_RC to $BACKUP_FILE"
  cp "$MAIL_RC" "$BACKUP_FILE"

  cat <<EOF >> "$MAIL_RC"

# SMTP configuration for Gmail (Appended by configure_smtp.sh)
set smtp-use-starttls
set ssl-verify=ignore
set nss-config-dir=/etc/pki/nssdb
set smtp=smtp://smtp.gmail.com:587
set smtp-auth=login
set smtp-auth-user=$smtp_user
set smtp-auth-password=$smtp_pass
set from="$smtp_user"
EOF

  echo "✅ SMTP configuration appended at the end of $MAIL_RC"
}

# Main logic
if [[ "$1" == "--reconfigure" ]]; then
  echo "🔧 Reconfiguring SMTP settings..."
  prompt_credentials
  append_config
  exit 0
fi

if grep -q "$SMTP_MARKER" "$MAIL_RC"; then
  echo "✅ SMTP configuration already exists in $MAIL_RC"
  echo "👉 If you want to reconfigure it, run: sudo ./configure_smtp.sh --reconfigure"
else
  echo "📩 No SMTP configuration found. Starting setup..."
  prompt_credentials
  append_config
fi