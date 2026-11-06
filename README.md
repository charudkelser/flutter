# Chrome Lite Flutter — v1

Rebuild Flutter dari browser Chrome Lite (Java). Paket Android:
`com.modol.chrome_lite_flutter`. Dibuat dengan Flutter 3.27.0.

## Yang ada di v1

- **Beranda ala Chrome**: wordmark Google (teks berwarna), kapsul cari,
  grid pintasan (Google, YouTube, Facebook, Instagram, Wikipedia).
- **WebView**: bilah URL di atas (bisa diedit, menampilkan URL aktif),
  tombol kembali / maju / muat ulang, bilah progres loading.
- **Tab**: banyak tab, tombol tab baru (+), halaman pengalih tab
  (daftar tab + tombol tutup X), badge jumlah tab di bilah atas.
- **Cari**: ketikan yang bukan URL otomatis dicari di Google.
- **Samaran**: tab samaran terpisah (tampilan gelap), tidak menyimpan riwayat.
- **Unduhan**: tautan berkas umum (apk, zip, pdf, mp3, mp4, gambar, dsb.)
  ditangkap dari WebView lalu diunduh via paket `http` (ada progres),
  halaman Daftar Unduhan, nama berkas anti-tabrakan (`nama (1).ext`).
- **Menu (⋮)**: Tab baru, Tab samaran baru, Unduhan, Bagikan
  (salin tautan ke clipboard), Muat ulang, Situs desktop (ganti user agent
  ke desktop + muat ulang), Setelan.
- **Setelan**: hapus riwayat, hapus cookie, hapus cache.
- **Tombol kembali Android**: kembali di WebView dulu, baru keluar aplikasi.
- Label aplikasi Android: **Chrome Lite Flutter**.

## Dependensi (pubspec.yaml)

- `webview_flutter: ^4.10.0` → ter-resolve **4.13.0** (versi 4.14.x butuh
  Flutter ≥ 3.38, tidak cocok untuk 3.27).
- `http: ^1.2.0` → ter-resolve 1.6.0 (unduhan).
- `path_provider: ^2.1.5` → (folder unduhan; versi 2.1.6 butuh
  Flutter ≥ 3.38, tidak cocok untuk 3.27).

Tidak ada plugin berat lain. `flutter analyze` dan `dart analyze`:
**No issues found.**

## Yang belum ada di v1

- Riwayat hanya disimpan di memori (maks 100 entri) dan belum ada halaman
  Riwayat; Setelan hanya bisa menghapusnya.
- "Bagikan" baru menyalin tautan ke clipboard (belum lembar berbagi sistem
  — butuh plugin `share_plus`).
- Tidak ada blokir iklan, tidak ada bookmark, tidak ada grup tab,
  tidak ada pratinjau tab, tidak ada unduh jeda/lanjut (sekali jalan).
- Tidak ada halaman error khusus bila situs gagal dimuat (WebView tampil
  apa adanya).
- Ikon aplikasi masih ikon default Flutter (belum diganti).

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
