#!/bin/sh

# =============================================================================
# Auto Edu - Uninstall Script
# =============================================================================
# Script untuk uninstall Auto Edu dari OpenWrt router
#
# Usage:
#   sh uninstall.sh                  # Interactive uninstall
#   sh uninstall.sh --force          # Force uninstall tanpa konfirmasi
#   sh uninstall.sh --keep-backup    # Uninstall dengan backup
# =============================================================================

set -e

INSTALL_DIR="/root/Auto-Edu"
LOG_FILE="/tmp/auto_edu.log"
BACKUP_DIR="$HOME"

print_success() { echo "✓ $1"; }
print_error() { echo "✗ $1"; }
print_warning() { echo "⚠ $1"; }
print_info() { echo "ℹ $1"; }

print_banner() {
    clear
    cat << 'EOF'
════════════════════════════════════════════
     AUTO EDU - UNINSTALL SCRIPT
════════════════════════════════════════════
EOF
    echo ""
}

# Parse arguments
FORCE=false
KEEP_BACKUP=false
for arg in "$@"; do
    case $arg in
        --force) FORCE=true ;;
        --keep-backup) KEEP_BACKUP=true ;;
    esac
done

print_banner

# Check if installed
if [ ! -d "$INSTALL_DIR" ]; then
    print_warning "Auto Edu tidak terinstall di $INSTALL_DIR"
    
    # Check old installation
    if [ -f "/root/auto_edu.py" ] || [ -f "/root/.auto_edu.env" ]; then
        print_info "Ditemukan instalasi lama di /root/"
        read -p "Remove old files? (y/n) [y]: " remove_old
        remove_old=${remove_old:-y}
        
        if [ "$remove_old" = "y" ]; then
            rm -f /root/auto_edu.py /root/.auto_edu.env
            print_success "Old files removed"
        fi
    fi
    
    exit 0
fi

echo "⚠ WARNING: This will remove Auto Edu from your system"
echo ""
echo "Installation found at: $INSTALL_DIR"
echo ""

if [ "$FORCE" = false ]; then
    read -p "Continue with uninstall? (y/n) [n]: " confirm
    confirm=${confirm:-n}
    
    if [ "$confirm" != "y" ] && [ "$confirm" != "Y" ]; then
        print_warning "Uninstall cancelled"
        exit 0
    fi
fi

echo ""
print_info "Starting uninstall process..."
echo ""

# Step 1: Backup (if requested)
if [ "$KEEP_BACKUP" = true ] || [ "$FORCE" = false ]; then
    if [ "$FORCE" = false ]; then
        read -p "Create backup before uninstall? (y/n) [y]: " do_backup
        do_backup=${do_backup:-y}
    else
        do_backup=y
    fi
    
    if [ "$do_backup" = "y" ]; then
        BACKUP_FILE="$BACKUP_DIR/Auto-Edu-backup-$(date +%Y%m%d_%H%M%S).tar.gz"
        print_info "Creating backup..."
        
        if tar -czf "$BACKUP_FILE" "$INSTALL_DIR" 2>/dev/null; then
            print_success "Backup saved: $BACKUP_FILE"
        else
            print_warning "Backup failed, continuing..."
        fi
        echo ""
    fi
fi

# Step 2: Stop cron job
print_info "Removing cron job..."
if crontab -l 2>/dev/null | grep -q "auto_edu.py"; then
    crontab -l 2>/dev/null | grep -v "auto_edu.py" | crontab - 2>/dev/null || true
    print_success "Cron job removed"
else
    print_info "No cron job found"
fi
echo ""

# Step 3: Kill running processes
print_info "Stopping running processes..."
if pgrep -f "auto_edu.py" > /dev/null; then
    pkill -f "auto_edu.py" 2>/dev/null || true
    sleep 2
    print_success "Processes stopped"
else
    print_info "No running processes"
fi
echo ""

# Step 4: Remove files
print_info "Removing installation directory..."
if [ -d "$INSTALL_DIR" ]; then
    rm -rf "$INSTALL_DIR"
    print_success "Directory removed: $INSTALL_DIR"
else
    print_info "Directory not found"
fi
echo ""

print_info "Removing log file..."
if [ -f "$LOG_FILE" ]; then
    rm -f "$LOG_FILE"
    print_success "Log removed: $LOG_FILE"
else
    print_info "Log file not found"
fi
echo ""

# Step 5: Clean old installations
print_info "Cleaning old files..."
OLD_FILES="/root/auto_edu.py /root/.auto_edu.env"
CLEANED=0
for file in $OLD_FILES; do
    if [ -f "$file" ]; then
        rm -f "$file"
        CLEANED=$((CLEANED + 1))
    fi
done

if [ $CLEANED -gt 0 ]; then
    print_success "Cleaned $CLEANED old file(s)"
else
    print_info "No old files found"
fi
echo ""

# Step 6: Clean backup directories
print_info "Cleaning old backups..."
if ls "$INSTALL_DIR".backup.* 1> /dev/null 2>&1; then
    rm -rf "$INSTALL_DIR".backup.*
    print_success "Old backups removed"
else
    print_info "No old backups found"
fi
echo ""

# Step 7: Verify
print_info "Verifying uninstall..."
ERRORS=0

if [ -d "$INSTALL_DIR" ]; then
    print_error "Directory still exists: $INSTALL_DIR"
    ERRORS=$((ERRORS + 1))
fi

if [ -f "$LOG_FILE" ]; then
    print_error "Log file still exists: $LOG_FILE"
    ERRORS=$((ERRORS + 1))
fi

if crontab -l 2>/dev/null | grep -q "auto_edu.py"; then
    print_error "Cron job still exists"
    ERRORS=$((ERRORS + 1))
fi

if [ $ERRORS -eq 0 ]; then
    print_success "Verification passed"
else
    print_warning "$ERRORS error(s) found"
fi
echo ""

# Final summary
echo ""
cat << 'EOF'
════════════════════════════════════════════
     ✓ UNINSTALL COMPLETE ✓
════════════════════════════════════════════
EOF
echo ""

echo "════════════════════════════════════════════"
print_success "Auto Edu has been removed from your system"
echo "════════════════════════════════════════════"
echo ""

if [ -n "$BACKUP_FILE" ] && [ -f "$BACKUP_FILE" ]; then
    echo "📦 Backup saved:"
    echo "   $BACKUP_FILE"
    echo ""
    echo "To restore:"
    echo "   tar -xzf $BACKUP_FILE -C /"
    echo "   (crontab -l; echo '*/3 * * * * AUTO_EDU_ENV=/root/Auto-Edu/auto_edu.env python3 /root/Auto-Edu/auto_edu.py') | crontab -"
    echo ""
fi

echo "To reinstall:"
echo "   bash <(curl -fsSL https://raw.githubusercontent.com/Matsumiko/AutoEdu-renewal/main/setup.sh)"
echo ""

echo "Thank you for using Auto Edu! 👋"
echo ""

exit 0