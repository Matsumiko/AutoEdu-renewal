# 🔧 FIX: Double Renewal Issue

## 🐛 Masalah

Script melakukan **double renewal** meskipun paket baru saja di-renew:

```
00:45 - Deteksi kuota rendah ✅
00:46 - Renewal berhasil ✅
00:51 - Deteksi kuota rendah lagi ❌ (FALSE POSITIVE!)
00:51 - Renewal lagi ❌ (DOUBLE RENEWAL!)
```

## 🔍 Root Cause

Script cek keyword `"kurang dari 3GB"` di **3 SMS terakhir** tanpa filter waktu. SMS lama yang sudah di-handle masih ada di inbox, jadi tetap ke-trigger!

### Alur Masalah:

1. Script jalan jam 00:45 → Deteksi SMS "kurang dari 3GB" → Renewal ✅
2. Renewal berhasil → SMS baru masuk: "Paket sudah aktif"
3. Script jalan lagi jam 00:51 (3 menit kemudian via cron)
4. Script baca 3 SMS terakhir:
   - SMS #1: "Paket sudah aktif" (baru)
   - SMS #2: "kurang dari 3GB" (SMS LAMA yang sudah di-handle!) ❌
   - SMS #3: ...
5. Keyword "kurang dari 3GB" ditemukan → Renewal lagi! ❌

## ✅ Solusi

### Fix #1: Deteksi Konfirmasi Aktivasi

Cek apakah SMS terbaru adalah konfirmasi aktivasi paket. Jika ya, **skip renewal**.

```python
# Cek keywords konfirmasi aktivasi
konfirmasi_keywords = [
    'sdh aktif', 
    'sudah aktif', 
    'berhasil diaktifkan', 
    'telah diaktifkan',
    'anda sdh aktif',
    'paket aktif'
]

if any(kw in sms_terbaru for kw in konfirmasi_keywords):
    logger.success("✅ SMS terbaru adalah konfirmasi - Skip renewal")
    return True
```

### Fix #2: Time-Based SMS Filtering

Hanya cek SMS yang **masih fresh** (default: < 15 menit). SMS lama diabaikan.

```python
# Filter berdasarkan waktu
current_time = time.time()
max_age_seconds = SMS_MAX_AGE_MINUTES * 60  # Default: 15 menit

for sms in sms_list:
    sms_age = current_time - sms['timestamp']
    
    # Hanya cek SMS fresh
    if sms_age < max_age_seconds:
        if "kurang dari 3GB" in sms['isi']:
            # Ini SMS fresh, proses renewal
            fresh_kuota_rendah = True
    else:
        # SMS sudah lama, skip!
        logger.info(f"Skip SMS lama (usia: {int(sms_age/60)} menit)")
```

## 🆕 Parameter Baru

Tambahkan di file `.env`:

```bash
# NEW: Max usia SMS yang di-cek (dalam menit)
SMS_MAX_AGE_MINUTES=15
```

- **Default: 15 menit**
- Sesuaikan dengan interval cron Anda
- Contoh: Jika cron setiap 3 menit, bisa set ke 10 menit

## 📊 Hasil Setelah Fix

### Before Fix:
```
00:45 - Renewal ✅
00:51 - Renewal lagi ❌ (double!)
00:54 - Renewal lagi ❌ (triple!)
```

### After Fix:
```
00:45 - Renewal ✅
00:51 - Skip (SMS konfirmasi terdeteksi) ✅
00:54 - Skip (SMS "kurang dari 3GB" sudah lama) ✅
```

## 🚀 Cara Update

### Opsi 1: Download Langsung

```bash
# Backup script lama
cp /root/Auto-Edu/auto_edu.py /root/Auto-Edu/auto_edu.py.backup

# Download versi fixed
curl -fsSL https://raw.githubusercontent.com/Matsumiko/AutoEdu-renewal/main/auto_edu.py \
  -o /root/Auto-Edu/auto_edu.py

chmod +x /root/Auto-Edu/auto_edu.py
```

### Opsi 2: Edit Manual

Tambahkan parameter di `.env`:

```bash
vi /root/Auto-Edu/auto_edu.env
```

Tambahkan baris ini:

```bash
# Anti double-renewal (dalam menit)
SMS_MAX_AGE_MINUTES=15
```

Lalu ganti script dengan versi fixed yang sudah didownload.

### Opsi 3: Reinstall

```bash
# Uninstall
bash <(curl -fsSL https://raw.githubusercontent.com/Matsumiko/AutoEdu-renewal/main/uninstall.sh)

# Install versi terbaru
bash <(curl -fsSL https://raw.githubusercontent.com/Matsumiko/AutoEdu-renewal/main/setup.sh)
```

## 🧪 Testing

```bash
# Test script
python3 /root/Auto-Edu/auto_edu.py

# Monitor log untuk melihat filtering
tail -f /tmp/auto_edu.log
```

Expected output:
```
[INFO] SMS terbaru dari: XL
[INFO] Isi: EduConference 30GB Anda sdh aktif...
[SUCCESS] ✅ SMS terbaru adalah konfirmasi aktivasi paket - Skip renewal
```

Atau:
```
[INFO] SMS terbaru dari: XL
[INFO] Isi: Sisa kuota...kurang dari 3GB...
[INFO] Skip SMS lama (usia: 18 menit)
[SUCCESS] ✅ Kuota masih aman (SMS sudah lama)
```

## 📝 Catatan Penting

1. **Adjust SMS_MAX_AGE_MINUTES** sesuai interval cron:
   - Cron 3 menit → Set 10-15 menit
   - Cron 5 menit → Set 15-20 menit
   - Cron 15 menit → Set 30-45 menit

2. **Konfirmasi keywords** sudah mencakup variasi SMS dari berbagai provider, tapi bisa ditambah sesuai SMS provider Anda.

3. Script tetap aman - notifikasi penting tetap terkirim!

## ✨ Changelog

**Version: FIXED (Nov 2025)**

- ✅ Fix double renewal dengan time-based filtering
- ✅ Deteksi otomatis SMS konfirmasi aktivasi
- ✅ Parameter `SMS_MAX_AGE_MINUTES` yang configurable
- ✅ Logging lebih detail untuk debugging
- ✅ Skip SMS lama secara otomatis

## 🙏 Credits

Fix ini dibuat berdasarkan feedback dari user yang mengalami double renewal issue. Terima kasih!

---

**Edited Version by: Matsumiko**