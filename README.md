# Chrome Lite Flutter — v1 + batch 1

Rebuild Flutter dari browser Chrome Lite (Java). Paket Android:
`com.modol.chrome_lite_flutter`. Dibuat dengan Flutter 3.27.0.

## Yang ada (v1 + batch 1)

- **Beranda ala Chrome**: wordmark Google (teks berwarna), kapsul cari
  (teks hint berputar tiap 4 detik), grid pintasan (Google, YouTube,
  Facebook, Instagram, Wikipedia), dan bagian **Trending** (6 berita
  teratas dari RSS Google News Indonesia; bila gagal dimuat, beranda
  tetap jalan tanpa berita).
- **WebView**: bilah URL di atas (bisa diedit, menampilkan URL aktif),
  tombol kembali / maju / muat ulang, bilah progres loading. WebView
  selalu menempel di tree sejak awal (perbaikan bug `ERR_CACHE_MISS`).
- **Tab**: banyak tab, tombol tab baru (+), halaman pengalih tab
  (daftar tab + tombol tutup X), badge jumlah tab di bilah atas.
- **Cari**: ketikan yang bukan URL otomatis dicari di Google.
- **Samaran**: tab samaran terpisah (tampilan gelap), tidak menyimpan riwayat.
- **Riwayat**: halaman Riwayat (judul + URL, ketuk untuk buka, hapus per
  item, hapus semua) — riwayat di memori, maks 100 entri.
- **Bookmark**: simpan halaman aktif dari menu (otomatis jadi "Hapus
  bookmark" bila sudah tersimpan), halaman Daftar Bookmark (buka + hapus),
  tersimpan permanen (SharedPreferences).
- **AdBlock**: saklar di Setelan (default ON, bisa dimatikan, tersimpan
  permanen). Bila ON: blokir navigasi ke host iklan (doubleclick,
  googlesyndication, googleadservices, ads.youtube.com, dsb. — googlevideo
  TIDAK diblokir) + sembunyikan elemen iklan via JavaScript tiap halaman
  selesai dimuat.
- **Unduhan**: tautan berkas umum (apk, zip, pdf, mp3, mp4, gambar, dsb.)
  ditangkap dari WebView lalu diunduh via paket `http` (ada progres),
  halaman Daftar Unduhan, nama berkas anti-tabrakan (`nama (1).ext`).
- **Menu (⋮)**: Tab baru, Tab samaran baru, Riwayat, Bookmark, Simpan/
  Hapus bookmark, Unduhan, Bagikan (lembar berbagi sistem; jatuh ke salin
  tautan bila gagal), Muat ulang, Situs desktop (ganti user agent ke
  desktop + muat ulang), Setelan, Tentang Chrome Lite.
- **Setelan**: saklar AdBlock, hapus riwayat, hapus cookie, hapus cache,
  Tentang Chrome Lite.
- **Tentang Chrome Lite**: nama aplikasi, versi 1.0.0 (Flutter),
  deskripsi, tautan GitHub / Facebook / Instagram (diketuk membuka situs
  di browser).
- **Tombol kembali Android**: kembali di WebView dulu; bila sudah di
  halaman pertama, kembali ke beranda aplikasi (bukan keluar aplikasi);
  bila sudah di beranda, baru keluar aplikasi.
- Label aplikasi Android: **Chrome Lite Flutter**.

## Dependensi (pubspec.yaml)

- `webview_flutter: ^4.10.0` → ter-resolve **4.13.0** (versi 4.14.x butuh
  Flutter ≥ 3.38, tidak cocok untuk 3.27).
- `http: ^1.2.0` → ter-resolve 1.6.0 (unduhan + RSS trending).
- `path_provider: ^2.1.5` → (folder unduhan; versi 2.1.6 butuh
  Flutter ≥ 3.38, tidak cocok untuk 3.27).
- `shared_preferences: ^2.4.0` → ter-resolve **2.5.3** (sdk ^3.5.0,
  flutter ≥ 3.24 — cocok untuk 3.27). Dipakai AdBlock + bookmark.
- `share_plus: ^10.1.4` → (lembar berbagi sistem; sdk ≥ 3.4, flutter
  ≥ 3.22 — cocok untuk 3.27).

Tidak ada plugin berat lain. `flutter analyze` dan `dart analyze`:
**No issues found.** `flutter build bundle --release`: OK.

## Yang belum ada (batch berikut)

- Unduh jeda/lanjut (saat ini sekali jalan).
- Grup tab, pratinjau tab, tab tersimpan (tab hilang saat aplikasi ditutup).
- Posisi bilah URL atas/bawah.
- Terjemah halaman.
- Menu tekan-lama pada gambar.
- Halaman DataUsage (pemakaian data per situs).
- Tarik-untuk-muat-ulang (pull-to-refresh).
- Tidak ada halaman error khusus bila situs gagal dimuat (WebView tampil
  apa adanya).
- Ikon aplikasi masih ikon default Flutter (belum diganti).
- Riwayat masih di memori (hilang saat aplikasi ditutup); bookmark sudah
  permanen.
- AdBlock memblokir navigasi/iframe iklan + menyembunyikan elemen iklan;
  sebagian gambar/skrip iklan masih bisa termuat (hanya disembunyikan),
  tidak sekuat `shouldInterceptRequest` di versi Java.

## Batasan unduhan (penting)

- Tujuan pertama folder Download publik perangkat. Di Android 11+ dengan
  targetSdk 34, tulis langsung ke folder publik itu dibatasi sistem
  (scoped storage) — bila gagal, unduhan otomatis jatuh ke folder
  eksternal aplikasi (`Android/data/com.modol.chrome_lite_flutter/files`),
  lalu ke dokumen aplikasi. Lokasi akhir berkas selalu ditampilkan di
  halaman Unduhan.
- `android:requestLegacyExternalStorage="true"` dipasang di manifest
  (membantu Android 10 ke bawah).
- Unduhan tidak memakai DownloadManager sistem; progres dihitung dari
  `content-length` bila server mengirimnya.

## Build cloud (GitHub Actions)

Perintah yang dipakai workflow (sama seperti proyek `coba_flutter_cloud`):
`flutter pub get` lalu `flutter build apk --release` (ubuntu-latest,
Flutter 3.27.0, Java 17). Build APK **tidak bisa** dites lokal di VM ini
(Gradle lokal rusak) — hanya `flutter analyze` yang diverifikasi.

**PERHATIAN SEBELUM PUSH:** file `android/gradle/wrapper/gradle-wrapper.jar`
ada di disk (hasil `flutter create`, 53.636 byte) tapi diabaikan oleh
`android/.gitignore`. Tanpa file itu, `flutter build apk` di cloud GAGAL
(`gradlew` butuh jar-nya). Sertakan dengan `git add -f` saat push, dan
JANGAN pakai langkah "Regenerate Gradle wrapper" di workflow (langkah itu
terbukti gagal di build 1 `coba_flutter_cloud`).
