#!/bin/sh

# =============================================================================
# Auto Edu - One-Liner Installer for OpenWrt
# =============================================================================
# Original script by: @zifahx
# Source: https://pastebin.com/ZbXMvX4D
#
# Quick Install:
# bash <(curl -fsSL https://raw.githubusercontent.com/Matsumiko/AutoEdu-renewal/main/setup.sh)
# =============================================================================

set -e

INSTALL_DIR="/root/Auto-Edu"
SCRIPT_FILE="$INSTALL_DIR/auto_edu.py"
ENV_FILE="$INSTALL_DIR/auto_edu.env"
LOG_FILE="/tmp/auto_edu.log"
REPO_RAW="https://raw.githubusercontent.com/Matsumiko/AutoEdu-renewal/main"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; MAGENTA='\033[0;35m'; NC='\033[0m'

print_success() { echo "${GREEN}✓ $1${NC}"; }
print_error() { echo "${RED}✗ $1${NC}"; }
print_warning() { echo "${YELLOW}⚠ $1${NC}"; }
print_info() { echo "${BLUE}ℹ $1${NC}"; }

clear
echo "${MAGENTA}"
cat << 'EOF'
╔════════════════════════════════════════════╗
║     AUTO EDU - ONE-LINER INSTALLER        ║
║         Edited by: Matsumiko              ║
╚════════════════════════════════════════════╝
EOF
echo "${NC}"

[ "$(id -u)" != "0" ] && { print_error "Run as root!"; exit 1; }

# STEP 1: Install dependencies
echo "${CYAN}▶ STEP 1/7: Installing Dependencies${NC}"
opkg update > /dev/null 2>&1 && print_success "Updated" || print_warning "Skip update"
for pkg in python3 curl; do
    opkg list-installed 2>/dev/null | grep -q "^$pkg " && print_success "$pkg OK" || {
        print_info "Installing $pkg..."
        opkg install $pkg > /dev/null 2>&1 && print_success "$pkg installed" || { print_error "Failed $pkg"; exit 1; }
    }
done
command -v adb > /dev/null 2>&1 && print_success "ADB: $(command -v adb)" || print_warning "ADB not found"
echo ""

# STEP 2: Create directory
echo "${CYAN}▶ STEP 2/7: Creating Directory${NC}"
if [ -d "$INSTALL_DIR" ]; then
    print_warning "$INSTALL_DIR exists"
    read -p "Backup and recreate? (y/n) [n]: " recreate
    if [ "$recreate" = "y" ]; then
        mv "$INSTALL_DIR" "${INSTALL_DIR}.backup.$(date +%Y%m%d_%H%M%S)"
        mkdir -p "$INSTALL_DIR"
        print_success "Recreated with backup"
    fi
else
    mkdir -p "$INSTALL_DIR"
    print_success "Created: $INSTALL_DIR"
fi
echo ""

# STEP 3: Download script
echo "${CYAN}▶ STEP 3/7: Downloading Script${NC}"
if curl -fsSL "$REPO_RAW/auto_edu.py" -o "$SCRIPT_FILE" 2>/dev/null; then
    chmod +x "$SCRIPT_FILE"
    print_success "Downloaded: $SCRIPT_FILE"
else
    print_error "Download failed! Check connection"
    exit 1
fi
echo ""

# STEP 4: Configure
echo "${CYAN}▶ STEP 4/7: Configuration${NC}"
if [ -f "$ENV_FILE" ]; then
    read -p "Config exists. Use old? (y/n) [y]: " use_old
    use_old=${use_old:-y}
    [ "$use_old" = "y" ] && { print_success "Using existing config"; echo ""; } && SKIP_CONFIG=1
fi

if [ "$SKIP_CONFIG" != "1" ]; then
    echo "${YELLOW}PANDUAN:${NC}"
    echo "📱 Bot Token: @BotFather → /newbot"
    echo "🆔 Chat ID: @userinfobot → Copy ID"
    echo ""
    
    while true; do
        printf "${CYAN}Bot Token:${NC} "; read BOT_TOKEN
        [ -n "$BOT_TOKEN" ] && break || print_error "Required!"
    done
    
    while true; do
        printf "${CYAN}Chat ID:${NC} "; read CHAT_ID
        [ -n "$CHAT_ID" ] && break || print_error "Required!"
    done
    
    printf "${CYAN}USSD Unreg [*808*5*2*1*1#]:${NC} "; read KODE_UNREG
    KODE_UNREG=${KODE_UNREG:-"*808*5*2*1*1#"}
    
    printf "${CYAN}USSD Beli [*808*4*1*1*1*1#]:${NC} "; read KODE_BELI
    KODE_BELI=${KODE_BELI:-"*808*4*1*1*1*1#"}
    
    printf "${CYAN}Threshold GB [3]:${NC} "; read THRESHOLD
    THRESHOLD=${THRESHOLD:-3}
    
    cat > "$ENV_FILE" << EOF
# Auto Edu Config - $(date)
# Edited by: Matsumiko
BOT_TOKEN=$BOT_TOKEN
CHAT_ID=$CHAT_ID
KODE_UNREG=$KODE_UNREG
KODE_BELI=$KODE_BELI
THRESHOLD_KUOTA_GB=$THRESHOLD
JEDA_USSD=10
TIMEOUT_ADB=15
JUMLAH_SMS_CEK=3
NOTIF_KUOTA_AMAN=false
NOTIF_STARTUP=true
NOTIF_DETAIL=true
LOG_FILE=$LOG_FILE
MAX_LOG_SIZE=102400
EOF
    chmod 600 "$ENV_FILE"
    print_success "Config saved"
fi
echo ""

# STEP 5: Test
echo "${CYAN}▶ STEP 5/7: Testing${NC}"
read -p "Run test? (y/n) [y]: " test
test=${test:-y}
if [ "$test" = "y" ]; then
    print_info "Testing..."
    echo "══════════════════════"
    AUTO_EDU_ENV="$ENV_FILE" python3 "$SCRIPT_FILE" && print_success "Test OK!" || print_warning "Check errors"
    echo "══════════════════════"
fi
echo ""

# STEP 6: Cron
echo "${CYAN}▶ STEP 6/7: Setup Cron${NC}"
echo "1) Every 3 min (recommended)"
echo "2) Every 5 min"
echo "3) Every 15 min"
echo "4) Skip"
printf "Choice [1]: "; read cron_choice
cron_choice=${cron_choice:-1}

case $cron_choice in
    1) CRON="*/3 * * * *" ;;
    2) CRON="*/5 * * * *" ;;
    3) CRON="*/15 * * * *" ;;
    *) CRON="" ;;
esac

if [ -n "$CRON" ]; then
    crontab -l 2>/dev/null | grep -v "auto_edu.py" | crontab - 2>/dev/null || true
    (crontab -l 2>/dev/null; echo "$CRON AUTO_EDU_ENV=$ENV_FILE python3 $SCRIPT_FILE") | crontab -
    /etc/init.d/cron restart > /dev/null 2>&1 || true
    print_success "Cron: $CRON"
fi
echo ""

# STEP 7: Summary
echo "${CYAN}▶ STEP 7/7: Done!${NC}"
echo ""
echo "${GREEN}✓ INSTALLATION COMPLETE!${NC}"
echo ""
echo "📂 Directory: $INSTALL_DIR"
echo "   ├── auto_edu.py"
echo "   └── auto_edu.env"
echo ""
echo "📝 Log: $LOG_FILE"
[ -n "$CRON" ] && echo "⏰ Cron: $CRON"
echo ""
echo "${YELLOW}Commands:${NC}"
echo "  Test: ${GREEN}python3 $SCRIPT_FILE${NC}"
echo "  Logs: ${GREEN}tail -f $LOG_FILE${NC}"
echo "  Edit: ${GREEN}vi $ENV_FILE${NC}"
echo ""
print_success "Auto Edu running! 🚀"
echo ""
echo "${MAGENTA}Edited by: Matsumiko${NC}"