# Audit kesiapan penggunaan

**Sasaran:** SD Negeri Klumprit 04 Nusawungu, Kecamatan Nusawungu, Kabupaten Cilacap
**Tanggal audit kode:** 6 Oktober 2026
**Keputusan:** **BELUM BOLEH DIANGGAP SIAP PRODUKSI.** Perubahan teknis di repositori menutup beberapa celah penting dan menambahkan jalur manual, tetapi peluncuran masih bergantung pada persetujuan pimpinan/dinas, pemeriksaan kepatuhan, konfigurasi project yang benar, dan uji lapangan.

> Ini audit rekayasa perangkat lunak, bukan pendapat hukum atau persetujuan pemrosesan biometrik. Sekolah/dinas perlu menetapkan pengendali data, dasar pemrosesan, pemberitahuan, persetujuan, masa simpan, dan penanggung jawab insiden sebelum mengumpulkan data anak.

## Ringkasan temuan dan perubahan kode

| Area | Temuan sebelum audit | Perubahan pada kode/SQL | Status |
|---|---|---|---|
| Akses database | SQL demo memberi hak anon membaca descriptor, menambah siswa/absensi, dan membaca foto publik. Satu key dapat disalin siapa pun. | `supabase.sql` baru menolak akses `anon`, mewajibkan Supabase Auth + allowlist `school_staff`, RLS kelas, dan bucket privat. | Diperbaiki pada baseline baru; wajib uji di project aktual. |
| Penyimpanan biometrik | Descriptor ada di tabel roster bersama identitas. Foto memakai URL publik. | Template dipisah ke `student_face_templates`; foto memakai path privat dan signed URL terbatas. Siswa manual tidak memiliki template/foto. | Diperbaiki secara teknis. |
| Persetujuan anak | Tidak ada pencatatan pemeriksaan izin orang tua/wali atau cara opt-out. | Form pendaftaran wajah meminta petugas memastikan persetujuan tertulis telah diterima; SQL menyimpan waktu dan akun petugas yang mengonfirmasi. Tersedia roster manual tanpa biometrik. | Sebagian: checkbox **bukan** formulir persetujuan dan tidak membuktikan dokumen. SOP persetujuan sekolah tetap wajib. |
| Salah identifikasi | Kecocokan langsung menulis absensi; tidak ada pemeriksaan manusia. | Wajah hanya membuat kandidat; petugas harus memeriksa siswa dan menekan **Konfirmasi hadir**. Satu wajah per verifikasi; catat manual juga tersedia. | Mitigasi, bukan penghapusan risiko. |
| Pemalsuan wajah | Tidak ada liveness atau anti-spoof. | Tidak ditambahkan; setiap orang bisa mencoba foto cetak/layar. | Risiko tinggi yang tersisa; jangan jadikan biometrik satu-satunya bukti kehadiran. |
| Jam/tanggal | Jam browser dapat salah; zona DB dapat berbeda. | Trigger DB memberi cap waktu `Asia/Jakarta` dan mengambil kelas dari data siswa. | Diperbaiki; uji batas pergantian hari di server aktual. |
| Pemisahan kelas | Guru berpotensi mengunduh semua kelas. | RLS `can_access_class`: admin seluruh kelas; guru hanya kelas di `school_staff.class_names`. | Diperbaiki di SQL; uji positif/negatif setelah bootstrap. |
| Sesi petugas | Tidak ada login. | Email/password Supabase Auth; pendaftaran mandiri tidak dipakai; sesi tidak dipersist ke LocalStorage. | Diperbaiki; MFA, kebijakan kata sandi, dan reset akun tetap harus dikonfigurasi. |
| Penghapusan/retensi | Tidak ada workflow untuk pembatalan consent, penghapusan foto/template, koreksi absensi, atau arsip. | SQL memakai cascade pada template dan absensi saat siswa dihapus, tetapi aplikasi belum memiliki UI admin untuk penghapusan/koreksi. | **Penghambat go-live** sampai SOP/admin workflow ditetapkan dan diuji. |
| Ketergantungan eksternal | Library dan bobot model berasal dari CDN. | Versi face-api dan Supabase JS dipatok; video tidak diunggah sebagai stream. | Risiko supply-chain tetap ada; pertimbangkan self-host aset/CDN yang disetujui. |
| Ketersediaan | Tidak ada backend lokal/offline; operasi butuh internet, CDN, Auth, API, Storage, dan Realtime. | UI memberi status koneksi dan menyediakan input presensi manual saat sistem bekerja. | Tetap perlu prosedur daftar manual kertas saat jaringan/server mati. |

## Risiko khusus karena siswa adalah anak

UU No. 27 Tahun 2022 tentang Pelindungan Data Pribadi memasukkan **data biometrik dan data anak** sebagai Data Pribadi yang bersifat spesifik (Pasal 4 ayat (2)). Pasal 25 mengatur pemrosesan Data Pribadi anak secara khusus dan mensyaratkan persetujuan orang tua dan/atau wali sesuai ketentuan. Pasal 35 memasukkan pemrosesan Data Pribadi spesifik dalam pemrosesan berisiko tinggi yang perlu penilaian dampak pelindungan data. Kegagalan pelindungan data memiliki kewajiban pemberitahuan tertulis paling lambat 3 × 24 jam menurut Pasal 46; transfer ke luar Indonesia perlu dikaji menurut Pasal 56.

Implikasi sebelum mendaftarkan seorang siswa:

1. Pimpinan sekolah/dinas menetapkan **tujuan yang spesifik**, siapa pengendali/prosesor, dasar pemrosesan, dan siapa yang dapat mengakses data.
2. Orang tua/wali menerima pemberitahuan yang jelas: data apa yang dikumpulkan (foto, template biometrik, NISN/nama/kelas, log waktu), tujuan, lokasi/penyedia penyimpanan, masa simpan, penerima, risiko, cara menarik persetujuan, serta kontak untuk akses/koreksi/penghapusan.
3. Simpan bukti persetujuan tertulis/terekam sesuai kebijakan sekolah. Checkbox aplikasi hanya mencatat bahwa petugas menyatakan bukti sudah ada; checkbox **tidak menggantikan bukti**.
4. Jangan memberikan konsekuensi akademik atau disipliner kepada siswa yang tidak ikut biometrik. Gunakan roster manual dan prosedur yang setara.
5. Tentukan masa simpan yang proporsional, jadwal penghapusan descriptor/foto/log, dan proses untuk menindaklanjuti penarikan persetujuan. Jangan menyimpan foto/descriptor “untuk berjaga-jaga”.
6. Tinjau region project Supabase, subprosesor, backup, kontrak/ketentuan layanan, serta apakah pemrosesan/transfer lintas batas memenuhi persyaratan yang berlaku. Jangan menganggap server berada di Indonesia tanpa memeriksa region project.
7. Lakukan penilaian dampak/DPIA dan konsultasi dengan Dinas Pendidikan/pejabat hukum atau petugas pelindungan data yang berwenang sebelum memakai data siswa nyata.

Rujukan utama: [UU 27/2022 pada JDIH Kemkomdigi](https://jdih.komdigi.go.id/produk_hukum/view/id/832/t/undangundang+nomor+27+tahun+2022).

## Risiko teknis yang masih tersisa

- **False accept/false reject dan bias:** nilai ambang `0.48` adalah parameter awal, bukan sertifikasi akurasi. Kamera, cahaya, jarak, perubahan penampilan, dan karakteristik kelompok memengaruhi hasil. Uji lintas kondisi tanpa menjadikan skor sebagai keputusan otomatis.
- **Tidak ada liveness:** sistem tidak mendeteksi topeng, foto, video, atau layar. Petugas harus melihat siswa secara langsung. Jangan gunakan sebagai kontrol akses atau penentu sanksi.
- **Tidak ada audit event lengkap:** kolom `created_by`/`recorded_by` menyimpan actor untuk data utama, tetapi belum ada riwayat siapa mengubah konfigurasi, perubahan roster, koreksi/penghapusan, kegagalan akses, atau keputusan verifikasi kandidat. Tambahkan audit log yang dikelola admin sebelum penggunaan luas.
- **Belum ada workflow admin di UI:** penonaktifan petugas, koreksi absensi, penghapusan data siswa dan file Storage dilakukan melalui Supabase Dashboard/SQL. Batasi akses dashboard ke admin sekolah/dinas dan dokumentasikan langkahnya.
- **Data lama saat upgrade:** skrip menjatuhkan `students.face_descriptor` versi lama dan mengosongkan path foto yang tidak punya status consent. File Storage lama dan attendance lama tetap ada; foto lama harus dihapus melalui Storage Dashboard. Baris `method='Legacy'` wajib ditinjau/dihapus atau dimigrasikan secara eksplisit sebelum go-live.
- **Supply-chain/CDN:** JavaScript pihak ketiga berjalan di origin aplikasi dan secara teknis dapat mengakses DOM/kamera. Library utama dipatok versinya, namun Tailwind, ikon, font, dan model tetap diambil dari layanan eksternal. Untuk perangkat sekolah, setujui sumber CDN, gunakan HTTPS, pertimbangkan self-hosting aset/bobot dan Content Security Policy setelah pengujian.
- **Shared device:** sesi Auth hanya disimpan dalam memori, tetapi petugas tetap harus menekan Keluar, mengunci perangkat, tidak memakai akun bersama, dan menghapus cache/browser profile sesuai kebijakan sekolah.
- **Koreksi harian:** constraint satu absensi/siswa/hari mencegah duplikasi, tetapi belum ada tombol koreksi. Petugas harus punya mekanisme eskalasi koreksi yang dapat diaudit; jangan mengubah tabel langsung tanpa prosedur.
- **Backup/pemulihan:** belum ada backup/restore yang diuji. Tetapkan backup yang tidak memperpanjang masa simpan secara tak terkendali; uji pemulihan pada project terpisah.

Supabase menyebut bucket privat tunduk pada kebijakan akses dan dapat diunduh melalui signed URL dengan masa berlaku; aplikasi memakai pendekatan itu untuk foto. Periksa kebijakan/storage project aktual, bukan hanya skrip: [Supabase Storage buckets](https://supabase.com/docs/guides/storage/buckets/fundamentals), [signed URL](https://supabase.com/docs/guides/storage/serving/downloads).

## Gate sebelum go-live

### A. Tata kelola dan hukum

- [ ] Persetujuan tertulis pimpinan sekolah dan pihak Dinas/otoritas terkait.
- [ ] Tentukan pengendali data dan penanggung jawab operasional/insiden.
- [ ] Selesaikan DPIA/penilaian dampak, tujuan dan dasar pemrosesan, pemberitahuan privasi, persetujuan orang tua/wali, hak siswa/orang tua, retensi, serta kebijakan opt-out.
- [ ] Tentukan lokasi data Supabase dan tinjau kewajiban transfer/subprosesor.
- [ ] Tetapkan jalur manual yang setara dan tanpa hukuman bagi siswa yang menolak.

### B. Konfigurasi database dan akun

- [ ] Gunakan Supabase project terpisah untuk sekolah; jangan memakai SQL/policy demo.
- [ ] Jalankan `supabase.sql`; periksa ulang `anon` gagal membaca/menulis `students`, `student_face_templates`, `attendances`, `school_staff`, dan Storage.
- [ ] Buat akun personal per petugas; public sign-up dimatikan; aktifkan verifikasi email dan MFA bila tersedia.
- [ ] Bootstrap satu admin, lalu tetapkan `class_names` sekecil mungkin untuk guru.
- [ ] Uji bahwa guru IV-A tidak dapat membaca/mengubah siswa IV-B, akun yang dinonaktifkan langsung kehilangan akses, dan anon ditolak.
- [ ] Hapus seluruh data uji/objek Storage lama yang tidak diperlukan; periksa tidak ada `method='Legacy'` tersisa untuk tanggal operasional.
- [ ] Pastikan hanya anon/publishable key berada di browser; `service_role` tidak pernah dipakai di HTML, LocalStorage, atau chat.

### C. Uji kelas dan keamanan

- [ ] Jalankan minimal satu minggu uji dengan data dummy, lalu uji dengan prosedur persetujuan dan persetujuan pihak berwenang sebelum data nyata.
- [ ] Uji enrollment wajah, siswa manual-only, persetujuan belum ada, penarikan persetujuan, kelas tidak diotorisasi, dan NISN duplikat.
- [ ] Uji foto cetak/layar untuk memastikan petugas memahami tidak adanya liveness.
- [ ] Uji kamera depan/belakang, pencahayaan pagi/siang, jaringan putus, Supabase Auth habis, realtime putus, restart browser, dua petugas bersamaan, dan batas pergantian tanggal `Asia/Jakarta`.
- [ ] Cocokkan hasil daftar wajah dengan daftar manual; ukur false accept/reject secara terdokumentasi. Jika hasil tidak andal, matikan mode wajah dan gunakan manual.
- [ ] Siapkan prosedur koreksi, penghapusan, pergantian petugas, backup/restore, dan respons insiden termasuk kontak pemroses data.
- [ ] Pastikan perangkat sekolah terkunci, HTTPS, browser didukung, izin kamera hanya diberikan pada perangkat yang dikendalikan sekolah, dan petugas tahu cara logout.

## Verifikasi yang dilakukan pada repositori

- Sintaks JavaScript ES module diperiksa dengan `node --check`.
- ID HTML duplikat/missing literal selector dan whitespace Git diperiksa.
- Uji autentikasi nyata, RLS di Supabase, database DDL, storage privat, Realtime, webcam, kinerja model, dan akurasi **belum dapat dijalankan** karena kredensial/project Supabase dan perangkat kamera sekolah tidak tersedia pada audit ini.
