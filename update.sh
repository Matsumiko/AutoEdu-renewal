#!/bin/sh

# =============================================================================
# Auto Edu - Update Script (Fix Double Renewal)
# =============================================================================
# Edited Version by: Matsumiko
#
# Quick Update:
# bash <(curl -fsSL https://raw.githubusercontent.com/Matsumiko/AutoEdu-renewal/main/update.sh)
# =============================================================================

set -e

INSTALL_DIR="/root/Auto-Edu"
SCRIPT_FILE="$INSTALL_DIR/auto_edu.py"
ENV_FILE="$INSTALL_DIR/auto_edu.env"
BACKUP_DIR="$INSTALL_DIR/backup"
REPO_RAW="https://raw.githubusercontent.com/Matsumiko/AutoEdu-renewal/main"

print_success() { echo "✓ $1"; }
print_error() { echo "✗ $1"; }
print_warning() { echo "⚠ $1"; }
print_info() { echo "ℹ $1"; }

clear
cat << 'EOF'
════════════════════════════════════════════
   AUTO EDU - UPDATE SCRIPT
   Fix: Double Renewal Issue
     Edited Version by: Matsumiko
════════════════════════════════════════════
EOF
echo ""

[ "$(id -u)" != "0" ] && { print_error "Run as root!"; exit 1; }

# Check if already installed
if [ ! -f "$SCRIPT_FILE" ]; then
    print_error "Auto Edu not found! Install first:"
    echo "bash <(curl -fsSL https://raw.githubusercontent.com/Matsumiko/AutoEdu-renewal/main/setup.sh)"
    exit 1
fi

echo "▶ STEP 1/4: Backup"
read -p "Backup script lama? (y/n) [y]: " backup_choice
backup_choice=${backup_choice:-y}

if [ "$backup_choice" = "y" ] || [ "$backup_choice" = "Y" ]; then
    mkdir -p "$BACKUP_DIR"
    BACKUP_FILE="$BACKUP_DIR/auto_edu_$(date +%Y%m%d_%H%M%S).py"
    cp "$SCRIPT_FILE" "$BACKUP_FILE"
    
    # Backup .env juga (optional tapi recommended)
    if [ -f "$ENV_FILE" ]; then
        BACKUP_ENV="$BACKUP_DIR/auto_edu_$(date +%Y%m%d_%H%M%S).env"
        cp "$ENV_FILE" "$BACKUP_ENV"
        print_success "Backup: $BACKUP_FILE & $BACKUP_ENV"
    else
        print_success "Backup: $BACKUP_FILE"
    fi
else
    print_warning "Skip backup (not recommended!)"
    BACKUP_FILE=""
fi
echo ""

echo "▶ STEP 2/4: Download Fixed Script"
if curl -fsSL "$REPO_RAW/auto_edu.py" -o "$SCRIPT_FILE" 2>/dev/null; then
    chmod +x "$SCRIPT_FILE"
    print_success "Downloaded fixed version"
else
    print_error "Download failed!"
    
    # Rollback jika ada backup
    if [ -n "$BACKUP_FILE" ] && [ -f "$BACKUP_FILE" ]; then
        print_info "Restoring backup..."
        cp "$BACKUP_FILE" "$SCRIPT_FILE"
        print_success "Backup restored"
    fi
    
    exit 1
fi
echo ""

echo "▶ STEP 3/4: Update Configuration"

# Check if SMS_MAX_AGE_MINUTES already exists
if grep -q "SMS_MAX_AGE_MINUTES" "$ENV_FILE" 2>/dev/null; then
    print_success "Config already has SMS_MAX_AGE_MINUTES"
else
    print_info "Adding SMS_MAX_AGE_MINUTES to config..."
    
    # Add parameter after TIMEOUT_ADB line
    sed -i '/^TIMEOUT_ADB=/a\\n# Anti Double-Renewal (minutes)\n# Hanya cek SMS yang lebih baru dari X menit\n# Recommended: 10-15 menit untuk cron 3-5 menit\nSMS_MAX_AGE_MINUTES=15' "$ENV_FILE"
    
    print_success "Added SMS_MAX_AGE_MINUTES=15"
fi
echo ""

echo "▶ STEP 4/4: Test"
read -p "Run test? (y/n) [y]: " test
test=${test:-y}
if [ "$test" = "y" ] || [ "$test" = "Y" ]; then
    print_info "Testing fixed script..."
    echo "══════════════════════"
    AUTO_EDU_ENV="$ENV_FILE" python3 "$SCRIPT_FILE" && print_success "Test OK!" || print_warning "Check errors"
    echo "══════════════════════"
else
    print_info "Skipped test"
fi
echo ""

echo "✓ UPDATE COMPLETE!"
echo ""
echo "What's Fixed:"
echo "  ✅ Double renewal prevention"
echo "  ✅ SMS time-based filtering"
echo "  ✅ Auto-detect activation SMS"
echo "  ✅ Heavy usage protection"
echo ""

# Show backup info
if [ -n "$BACKUP_FILE" ]; then
    echo "📂 Backup: $BACKUP_DIR"
    echo "   $(basename $BACKUP_FILE)"
    [ -n "$BACKUP_ENV" ] && echo "   $(basename $BACKUP_ENV)"
    echo ""
fi

echo "📝 Log: tail -f /tmp/auto_edu.log"
echo ""
print_success "Auto Edu updated! 🚀"
echo ""
echo "Changes:"
echo "  • Added SMS_MAX_AGE_MINUTES=15 to config"
echo "  • Script now ignores old SMS (>15 min)"
echo "  • Auto-detects 'paket aktif' confirmation"
echo "  • Tracks renewal timestamp for heavy usage"
echo ""
print_info "No cron changes needed - it will work automatically!"
echo ""

# Rollback instructions
if [ -n "$BACKUP_FILE" ]; then
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "Rollback (jika ada masalah):"
    echo "  cp $BACKUP_FILE $SCRIPT_FILE"
    [ -n "$BACKUP_ENV" ] && echo "  cp $BACKUP_ENV $ENV_FILE"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
fi

echo "Verification:"
echo "  grep SMS_MAX_AGE_MINUTES $ENV_FILE"
echo "  tail -f /tmp/auto_edu.log"
echo ""
echo "Edited Version by: Matsumiko"