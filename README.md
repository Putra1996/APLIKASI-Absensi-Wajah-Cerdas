# Sistem Absensi Siswa — SD Negeri Klumprit 04 Nusawungu

SPA berbantuan pengenalan wajah. Aplikasi **tidak menetapkan kehadiran otomatis**: kecocokan hanya menampilkan kandidat, lalu petugas harus memeriksa siswa dan mengonfirmasi. Roster mode manual tersedia bagi semua siswa, termasuk yang tidak ikut pemrosesan biometrik.

## Berkas

- `index.html` — aplikasi satu file, JavaScript di browser.
- `supabase.sql` — baseline Supabase dengan login petugas, RLS berdasarkan kelas, template biometrik terpisah, bucket foto privat, cap waktu `Asia/Jakarta`, dan Realtime.
- `AUDIT.md` — penilaian risiko dan checklist sebelum penggunaan di sekolah.

## Deploy gratis dengan GitHub Pages

Repo ini public. Aktifkan hosting statis sekali melalui **GitHub → Settings → Pages → Build and deployment → Source: Deploy from a branch**, pilih branch `arena/71cb18e2-aplikasi-absensi-wajah-cerdas` dan folder `/(root)`, lalu simpan. GitHub Pages akan menerbitkan `index.html` melalui HTTPS; push berikutnya ke branch tersebut akan memperbarui situs. URL biasanya `https://putra1996.github.io/APLIKASI-Absensi-Wajah-Cerdas/`.

GitHub Pages hanya menyajikan file statis; ia tidak membuat database atau akun petugas. Kode/SQL dapat dilihat publik. Jangan taruh kredensial rahasia di repo; anon/publishable key memang publik dan harus dibatasi RLS. Aplikasi belum bisa mencatat apa pun sampai Supabase dikonfigurasi dan akun petugas diotorisasi.

## Setup teknis

Gunakan project Supabase **khusus sekolah**. Jangan gunakan project yang sama untuk aplikasi lain karena skrip membatasi akses `anon` pada tabel/storage.

1. Tinjau lokasi region Supabase dan syarat pemrosesan data sebelum membuat project.
2. Jalankan `supabase.sql` melalui Supabase Dashboard → SQL Editor.
3. Buat akun petugas di **Authentication → Users**. Nonaktifkan public sign-up; akun tidak dibuat oleh aplikasi.
4. Tambahkan UUID admin pertama ke `public.school_staff` melalui SQL Editor, memakai contoh bootstrap di bagian akhir `supabase.sql`. Tambahkan guru dengan daftar kelas yang ditugaskan, misalnya `array['IV-A','IV-B']`.
5. Sajikan `index.html` melalui HTTPS atau localhost. Untuk uji lokal: `python3 -m http.server 8000 --bind 0.0.0.0`, kemudian buka `http://localhost:8000`.
6. Buka tab Konfigurasi, masukkan Project URL dan **anon/publishable key**, lalu login. Konfigurasi URL/key disimpan di LocalStorage; password tidak disimpan, dan sesi Auth hanya hidup di memori halaman.
7. Tambahkan roster. Pilih **presensi manual saja** untuk siswa yang tidak memiliki persetujuan pemrosesan wajah. Untuk pendaftaran wajah, petugas harus memastikan persetujuan tertulis orang tua/wali tersimpan sesuai prosedur sekolah.
8. Uji mode manual, webcam, verifikasi kandidat, Supabase Auth/RLS, Realtime, serta pemulihan setelah jaringan putus sebelum operasional.

### Aturan akses

- `anon` tidak mendapat akses data. Semua pemanggilan data memerlukan sesi Supabase Auth aktif.
- Akun harus ada di `school_staff`; admin dapat mengakses semua kelas, guru hanya kelas di `class_names`.
- Template wajah disimpan di `student_face_templates`, terpisah dari roster. Siswa mode manual tidak memiliki descriptor maupun foto.
- Foto berada di bucket privat; URL bertanda tangan berdurasi terbatas dibuat hanya bagi petugas berhak.
- Tanggal/jam absensi dicap database dalam zona `Asia/Jakarta`; satu baris per siswa per tanggal.
- Tombol **Tandai manual** menyediakan jalur operasional jika kamera/model/jaringan gagal atau siswa memilih tidak ikut biometrik.

## Model, browser, dan batasan

- Webcam hanya bekerja pada HTTPS atau `localhost`; video diproses lokal di browser dan tidak dikirim sebagai stream. Foto enrollment yang disetujui diunggah ke Supabase Storage privat, sedangkan template 128 angka dikirim ke database.
- `face-api.js` dan bobot model dimuat dari CDN publik (internet wajib); versi library utama dipatok. Untuk perangkat operasional, tinjau kebijakan CDN dan pertimbangkan self-hosting aset setelah pemeriksaan lisensi/supply-chain.
- Pengenalan wajah tidak memiliki liveness/anti-spoofing. Foto cetak atau layar dapat menipu deteksi; ambang 0.48 bukan jaminan identitas. Petugas harus memeriksa langsung dan mengonfirmasi secara manual.
- Ini bukan sistem offline: bila internet/Supabase tidak tersedia, log sinkron tidak tersimpan. Gunakan daftar manual kertas atau prosedur cadangan sekolah.

## Upgrade dari demo lama

Skrip baru menutup akses anon, menghapus kolom descriptor lama yang belum memiliki status persetujuan, dan mengosongkan path foto lama yang belum terverifikasi. Data `attendances` lama tetap disimpan dengan `method='Legacy'` dan tidak boleh diasumsikan sebagai presensi terverifikasi. Tinjau/buat backup, audit log tersebut, dan hapus data uji serta objek foto lama di Storage sebelum go-live. Objek lama di Storage tidak dihapus otomatis.

## Penting

Checklist hukum, persetujuan orang tua/wali, DPIA, masa simpan/penghapusan, pengelolaan insiden, dan region data ada di `AUDIT.md`. Implementasi teknis ini **belum cukup untuk menyatakan aplikasi siap produksi** tanpa persetujuan pimpinan/dinas, pemeriksaan kepatuhan, uji perangkat/jaringan sekolah, serta prosedur koreksi dan penghapusan data.
