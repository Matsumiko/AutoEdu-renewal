#!/usr/bin/env python3
# -*- coding: utf-8 -*-

"""
Auto Edu - Automatic Quota Management System
Sistem otomatis untuk monitoring dan perpanjangan kuota Edu
Optimized for OpenWrt environment

Setup:
1. opkg update && opkg install python3 curl
2. Edit konfigurasi di bawah (BOT_TOKEN, CHAT_ID, dll)
3. chmod +x /root/auto_edu.py
4. Test manual: python3 /root/auto_edu.py
5. Setup crontab: */3 * * * * python3 /root/auto_edu.py

"""

import re
import time
import subprocess
import urllib.parse
import sys
from datetime import datetime
from pathlib import Path

# ============================================================================
# KONFIGURASI - EDIT SESUAI KEBUTUHAN
# ============================================================================

BOT_TOKEN = 'BOT_TOKEN'  # Token dari @BotFather
CHAT_ID = 'CHAT_ID'      # Chat ID dari @MissRose_bot atau @userinfobot

# Kode USSD (sesuaikan dengan provider Anda)
KODE_UNREG = '*808*5*2*1*1#'  # Kode unreg Edu Rp10
KODE_BELI = '*808*4*1*1*1*1#'  # Kode beli Edu Rp10

# Pengaturan timing (dalam detik)
JEDA_USSD = 10           # Jeda antar perintah USSD
TIMEOUT_ADB = 15         # Timeout untuk perintah ADB

# Pengaturan threshold kuota
THRESHOLD_KUOTA_GB = 3   # Batas minimal kuota sebelum auto-renewal
JUMLAH_SMS_CEK = 3       # Jumlah SMS yang dicek setiap run

# Pengaturan notifikasi
NOTIF_KUOTA_AMAN = False  # Set True untuk notif saat kuota masih cukup
NOTIF_STARTUP = True      # Notifikasi saat script dimulai
NOTIF_DETAIL = True       # Notifikasi detail proses

# File log (opsional, set None untuk disable)
LOG_FILE = '/tmp/auto_edu.log'  # None untuk disable logging
MAX_LOG_SIZE = 1024 * 100  # 100KB max log size

# ============================================================================
# KELAS HELPER
# ============================================================================

class Logger:
    """Simple logger untuk debugging dan monitoring"""
    
    def __init__(self, log_file=None):
        self.log_file = log_file
        self._check_log_size()
    
    def _check_log_size(self):
        """Rotasi log jika terlalu besar"""
        if self.log_file and Path(self.log_file).exists():
            if Path(self.log_file).stat().st_size > MAX_LOG_SIZE:
                Path(self.log_file).unlink()
    
    def log(self, level, message):
        """Write log dengan timestamp"""
        timestamp = datetime.now().strftime('%Y-%m-%d %H:%M:%S')
        log_msg = f"[{timestamp}] [{level}] {message}"
        
        # Print ke console
        print(log_msg)
        
        # Write ke file jika diaktifkan
        if self.log_file:
            try:
                with open(self.log_file, 'a', encoding='utf-8') as f:
                    f.write(log_msg + '\n')
            except Exception as e:
                print(f"Warning: Gagal write log: {e}")
    
    def info(self, message):
        self.log('INFO', message)
    
    def warning(self, message):
        self.log('WARN', message)
    
    def error(self, message):
        self.log('ERROR', message)
    
    def success(self, message):
        self.log('SUCCESS', message)


class TelegramBot:
    """Handler untuk Telegram Bot API"""
    
    def __init__(self, token, chat_id, logger):
        self.token = token
        self.chat_id = chat_id
        self.logger = logger
        self.base_url = f"https://api.telegram.org/bot{token}"
    
    def kirim_pesan(self, pesan, parse_mode='HTML', silent=False):
        """Kirim pesan ke Telegram dengan retry mechanism"""
        if not self.chat_id or self.chat_id == 'CHAT_ID':
            self.logger.error("CHAT_ID belum dikonfigurasi!")
            return False
        
        url = f"{self.base_url}/sendMessage"
        params = {
            'chat_id': self.chat_id,
            'text': pesan,
            'parse_mode': parse_mode,
            'disable_notification': silent
        }
        
        data = urllib.parse.urlencode(params)
        
        for attempt in range(3):
            try:
                result = subprocess.run(
                    f'curl -s -X POST "{url}" -d "{data}"',
                    shell=True,
                    capture_output=True,
                    text=True,
                    timeout=10
                )
                
                if result.returncode == 0:
                    self.logger.info("Pesan Telegram terkirim")
                    return True
                else:
                    self.logger.warning(f"Attempt {attempt + 1}: Gagal kirim ({result.returncode})")
                    
            except subprocess.TimeoutExpired:
                self.logger.warning(f"Attempt {attempt + 1}: Timeout")
            except Exception as e:
                self.logger.error(f"Attempt {attempt + 1}: {str(e)}")
            
            if attempt < 2:
                time.sleep(2)
        
        return False
    
    def kirim_pesan_format(self, emoji, judul, konten, tingkat='info'):
        """Kirim pesan dengan format HTML yang rapi"""
        template = f"""
{emoji} <b>{judul}</b>

{konten}

<i>⏱ {datetime.now().strftime('%d/%m/%Y %H:%M:%S')}</i>
"""
        return self.kirim_pesan(template.strip())


class ADBManager:
    """Manager untuk komunikasi dengan Android via ADB"""
    
    def __init__(self, logger):
        self.logger = logger
    
    def cek_koneksi(self):
        """Cek apakah ADB terhubung dengan device"""
        try:
            result = subprocess.run(
                "adb devices",
                shell=True,
                capture_output=True,
                text=True,
                timeout=5
            )
            
            # Cek apakah ada device yang terhubung
            lines = result.stdout.strip().split('\n')
            if len(lines) > 1 and 'device' in lines[1]:
                self.logger.success("ADB terhubung dengan device")
                return True
            else:
                self.logger.error("Tidak ada device ADB yang terhubung")
                return False
                
        except Exception as e:
            self.logger.error(f"Gagal cek koneksi ADB: {str(e)}")
            return False
    
    def kirim_ussd(self, kode_ussd):
        """Kirim kode USSD ke device"""
        try:
            self.logger.info(f"Mengirim USSD: {kode_ussd}")
            
            # Encode # menjadi %23
            kode_encoded = kode_ussd.replace('#', '%23')
            
            # Kirim USSD
            result = subprocess.run(
                f"adb shell am start -a android.intent.action.CALL -d tel:{kode_encoded}",
                shell=True,
                capture_output=True,
                timeout=TIMEOUT_ADB
            )
            
            if result.returncode != 0:
                raise Exception(f"ADB error: {result.stderr.decode()}")
            
            # Tunggu proses USSD
            time.sleep(JEDA_USSD)
            
            # Tutup dialog USSD
            subprocess.run(
                "adb shell input keyevent KEYCODE_BACK",
                shell=True,
                capture_output=True,
                timeout=5
            )
            time.sleep(1)
            
            self.logger.success(f"USSD '{kode_ussd}' berhasil dikirim")
            return True, f"✅ USSD '{kode_ussd}' terkirim"
            
        except subprocess.TimeoutExpired:
            msg = f"❌ Timeout saat kirim USSD '{kode_ussd}'"
            self.logger.error(msg)
            return False, msg
        except Exception as e:
            msg = f"❌ Gagal kirim USSD: {str(e)}"
            self.logger.error(msg)
            return False, msg
    
    def baca_sms(self, limit=5, keyword=None):
        """Baca SMS dari inbox dengan filter opsional"""
        try:
            self.logger.info(f"Membaca {limit} SMS terbaru...")
            
            cmd = 'content query --uri content://sms/inbox --projection address:date:body --sort "date DESC"'
            result = subprocess.run(
                f"adb shell {cmd}",
                shell=True,
                capture_output=True,
                text=True,
                timeout=TIMEOUT_ADB
            )
            
            if result.returncode != 0:
                raise Exception("Gagal query SMS database")
            
            pesan_list = []
            found_keyword = False
            
            for baris in result.stdout.splitlines():
                if not baris.strip().startswith('Row:'):
                    continue
                
                # Parse SMS data
                alamat = re.search(r'address=([^,]+),', baris)
                tanggal = re.search(r'date=(\d+),', baris)
                isi = re.search(r'body=(.+)$', baris)
                
                if not (alamat and tanggal and isi):
                    continue
                
                # Format data
                pengirim = alamat.group(1).strip()
                timestamp = int(tanggal.group(1)) / 1000
                tanggal_str = datetime.fromtimestamp(timestamp).strftime('%d/%m/%Y %H:%M')
                isi_pesan = isi.group(1).strip()
                
                # Cek keyword jika ada
                if keyword and keyword.lower() in isi_pesan.lower():
                    found_keyword = True
                
                pesan_list.append({
                    'pengirim': pengirim,
                    'tanggal': tanggal_str,
                    'isi': isi_pesan,
                    'timestamp': timestamp
                })
                
                if len(pesan_list) >= limit:
                    break
            
            self.logger.success(f"Berhasil baca {len(pesan_list)} SMS")
            return pesan_list, found_keyword
            
        except subprocess.TimeoutExpired:
            self.logger.error("Timeout saat baca SMS")
            return [], False
        except Exception as e:
            self.logger.error(f"Gagal baca SMS: {str(e)}")
            return [], False


# ============================================================================
# FUNGSI UTAMA
# ============================================================================

def format_sms_untuk_telegram(sms_list, max_tampil=3):
    """Format list SMS menjadi text untuk Telegram"""
    if not sms_list:
        return "❌ Tidak ada SMS ditemukan"
    
    result = []
    for i, sms in enumerate(sms_list[:max_tampil], 1):
        result.append(
            f"<b>SMS #{i}</b>\n"
            f"📤 <code>{sms['pengirim']}</code>\n"
            f"🕐 {sms['tanggal']}\n"
            f"💬 {sms['isi'][:200]}{'...' if len(sms['isi']) > 200 else ''}"
        )
    
    return "\n\n".join(result)


def proses_renewal(adb, telegram, logger):
    """Proses unreg dan beli paket baru"""
    logger.info("=" * 50)
    logger.info("MEMULAI PROSES RENEWAL")
    logger.info("=" * 50)
    
    hasil = []
    
    # Step 1: Unreg paket lama
    telegram.kirim_pesan_format(
        "🔄", "Memulai Proses Renewal",
        "Sedang melakukan unregister paket lama..."
    )
    
    success_unreg, msg_unreg = adb.kirim_ussd(KODE_UNREG)
    hasil.append(msg_unreg)
    
    if not success_unreg:
        telegram.kirim_pesan_format(
            "⚠️", "Peringatan",
            f"Unreg gagal, tapi akan lanjut beli paket baru.\n\n{msg_unreg}"
        )
    
    # Jeda sebentar
    time.sleep(2)
    
    # Step 2: Beli paket baru
    success_beli, msg_beli = adb.kirim_ussd(KODE_BELI)
    hasil.append(msg_beli)
    
    # Step 3: Baca SMS konfirmasi
    time.sleep(3)
    sms_list, _ = adb.baca_sms(limit=2)
    
    # Kirim notifikasi hasil
    status = "✅ Berhasil" if (success_unreg or success_beli) else "❌ Gagal"
    
    konten = "\n".join(hasil)
    if sms_list:
        konten += f"\n\n<b>📱 SMS Terbaru:</b>\n\n{format_sms_untuk_telegram(sms_list, 2)}"
    
    telegram.kirim_pesan_format(
        "🎉" if success_beli else "❌",
        f"Renewal {status}",
        konten
    )
    
    logger.info("=" * 50)
    logger.success("PROSES RENEWAL SELESAI")
    logger.info("=" * 50)
    
    return success_beli


def cek_kuota_dan_proses(adb, telegram, logger):
    """Fungsi utama untuk cek kuota dan proses renewal jika perlu"""
    
    # Baca SMS untuk cek notifikasi kuota
    keyword = f"kurang dari {THRESHOLD_KUOTA_GB}GB"
    sms_list, kuota_rendah = adb.baca_sms(limit=JUMLAH_SMS_CEK, keyword=keyword)
    
    if not sms_list:
        logger.warning("Tidak ada SMS ditemukan")
        telegram.kirim_pesan_format(
            "⚠️", "Peringatan",
            "Tidak dapat membaca SMS. Pastikan device terhubung dengan baik."
        )
        return False
    
    # Log SMS terbaru
    logger.info(f"SMS terbaru dari: {sms_list[0]['pengirim']}")
    logger.info(f"Isi: {sms_list[0]['isi'][:100]}...")
    
    if kuota_rendah:
        logger.warning(f"⚠️ KUOTA RENDAH TERDETEKSI! (< {THRESHOLD_KUOTA_GB}GB)")
        
        # Kirim notifikasi dan mulai renewal
        telegram.kirim_pesan_format(
            "⚠️", "Kuota Hampir Habis!",
            f"Kuota Edu Anda kurang dari {THRESHOLD_KUOTA_GB}GB.\n"
            f"Memulai proses renewal otomatis...\n\n"
            f"<b>SMS Terakhir:</b>\n{sms_list[0]['isi'][:200]}"
        )
        
        # Proses renewal
        return proses_renewal(adb, telegram, logger)
    
    else:
        logger.success(f"✅ Kuota masih aman (≥ {THRESHOLD_KUOTA_GB}GB)")
        
        if NOTIF_KUOTA_AMAN:
            telegram.kirim_pesan_format(
                "✅", "Status Kuota",
                f"Kuota masih aman (≥ {THRESHOLD_KUOTA_GB}GB)\n\n"
                f"<b>SMS Terakhir:</b>\n{format_sms_untuk_telegram([sms_list[0]], 1)}",
                tingkat='info'
            )
        
        return True


def validasi_konfigurasi(logger):
    """Validasi konfigurasi sebelum menjalankan script"""
    errors = []
    
    if BOT_TOKEN == 'BOT_TOKEN' or not BOT_TOKEN:
        errors.append("❌ BOT_TOKEN belum dikonfigurasi")
    
    if CHAT_ID == 'CHAT_ID' or not CHAT_ID:
        errors.append("❌ CHAT_ID belum dikonfigurasi")
    
    if not KODE_UNREG or not KODE_BELI:
        errors.append("❌ Kode USSD belum dikonfigurasi")
    
    if errors:
        for error in errors:
            logger.error(error)
        return False
    
    return True


def main():
    """Fungsi utama"""
    # Inisialisasi
    logger = Logger(LOG_FILE)
    telegram = TelegramBot(BOT_TOKEN, CHAT_ID, logger)
    adb = ADBManager(logger)
    
    logger.info("=" * 60)
    logger.info("AUTO EDU - AUTOMATIC QUOTA MANAGEMENT SYSTEM")
    logger.info("=" * 60)
    
    try:
        # Validasi konfigurasi
        if not validasi_konfigurasi(logger):
            telegram.kirim_pesan_format(
                "❌", "Konfigurasi Error",
                "Script belum dikonfigurasi dengan benar!\n\n"
                "Silakan edit file dan isi:\n"
                "• BOT_TOKEN (dari @BotFather)\n"
                "• CHAT_ID (dari @MissRose_bot atau @userinfobot)\n"
                "• KODE_UNREG dan KODE_BELI"
            )
            return 1
        
        # Notifikasi startup (opsional)
        if NOTIF_STARTUP:
            telegram.kirim_pesan_format(
                "🚀", "Script Started",
                f"Auto Edu monitoring dimulai\n"
                f"Threshold: {THRESHOLD_KUOTA_GB}GB",
                tingkat='info'
            )
        
        # Cek koneksi ADB
        if not adb.cek_koneksi():
            telegram.kirim_pesan_format(
                "❌", "ADB Error",
                "Tidak dapat terhubung ke device!\n\n"
                "Pastikan:\n"
                "• USB debugging aktif\n"
                "• Device terhubung ke router\n"
                "• ADB sudah terinstall"
            )
            return 1
        
        # Proses utama
        success = cek_kuota_dan_proses(adb, telegram, logger)
        
        logger.info("=" * 60)
        logger.success("SCRIPT SELESAI - Status: " + ("OK" if success else "WARNING"))
        logger.info("=" * 60)
        
        return 0 if success else 1
        
    except KeyboardInterrupt:
        logger.warning("Script dihentikan oleh user")
        return 130
        
    except Exception as e:
        logger.error(f"FATAL ERROR: {str(e)}")
        telegram.kirim_pesan_format(
            "💥", "Fatal Error",
            f"Script error:\n<code>{str(e)}</code>\n\n"
            f"Periksa log untuk detail lebih lanjut."
        )
        return 1


if __name__ == '__main__':
    sys.exit(main())