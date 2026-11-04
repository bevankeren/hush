# hush

Ruang kerja skrip Roblox. Fondasi aturan supaya siapa pun — manusia atau AI —
yang masuk ke folder ini tidak mulai dari nol dan tidak menghilangkan jejak
keputusan.

## Urutan baca

1. `history.md` — baca dari **paling bawah**, itu yang terbaru
2. `rules.md` — aturan kerjanya (14 bagian)
3. `structure.md` — peta arsitektur (masih kerangka)
4. `TOOLING.md` — cara memegang MCP dan Cua Driver
5. `UI_GUIDE.md` — panduan library UI (Alexandria + Airflow)

## Isi folder

| File | Isi |
|---|---|
| `rules.md` | 14 aturan: logging, format entri, alur scripting, keandalan tooling, git, konvensi kode, definition of done |
| `history.md` | garis waktu proyek, tambah-terus, dimulai dari nol |
| `structure.md` | peta arsitektur & cetak biru teknis |
| `TOOLING.md` | SOP jalur utama (MCP) dan jalur cadangan (Cua Driver) |
| `UI_GUIDE.md` | panduan Alexandria/Obsidian & Airflow, sama dengan library eliteclass |
| `scripts/` | kode skrip Luau |
| `docs/` | dokumen temuan per topik |
| `.gitignore` | menjaga file lokal tidak ikut ter-push |

## Empat aturan yang paling sering dilanggar

1. **Setiap perubahan wajib masuk `history.md` pada kesempatan yang sama.**
   Bukan nanti. Bukan menyusul.
2. **Bedakan terbukti, dugaan, gagal.** Jangan mengarang hasil.
3. **Jangan hapus entri lama.** Batal berarti tambah entri baru, bukan sunting.
4. **Tooling gagal bukan alasan berhenti.** Ada jalur kedua: Cua Driver.

## Alur scripting

Baca history → nyatakan target → cek state nyata di client → tulis modular →
uji satu fitur satu kali → catat → bersihkan. Detail di `rules.md` Bagian 13.

## Definition of done

Kode jalan dan sudah dicoba → `history.md` diperbarui → `structure.md`
diperbarui bila struktural → yang gagal/ditunda tertulis dengan alasan.


## Versi publik: ESP + Super Potato

Entry point rilis: `scripts/hush.esp.luau`.

```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/bevankeren/hush/main/scripts/hush.esp.luau"))()
```

- Fresh execute: semua toggle OFF; config lama tidak dimuat otomatis.
- Aktifkan fitur yang dibutuhkan secara manual. Preset `System & Hop → Super Potato`
  menurunkan efek grafis dan kepadatan ESP; tidak menyalakan ESP/aimbot secara otomatis.
- Container memakai indeks event-driven, bukan scan seluruh Workspace setiap 3 detik.
- Discovery target dipisah dari render, dengan cache rig dan penyaringan jarak/FOV awal.
  Pencarian dibatasi maksimal 6,7 Hz (4 Hz pada Potato); tracking tetap per-frame.
  Mode kamera/look menunggu tombol aktivasi sebelum mencari target.
- Flat scenery hanya mengubah properti visual di `Town.Details`/`Town.Wild`.
  Material, collision, prompt, karakter dan geometri tidak dihapus/diubah.
- Mematikan preset mengembalikan nilai yang tersimpan. Efek baru ikut ditangani.
- Skrip membutuhkan runtime executor Roblox dan memuat UI Alexandria dari GitHub.

### Batas verifikasi

Syntax dikompilasi memakai Luau resmi. Cold-start OFF, target acquisition pada fixture,
penolakan target mati, penghentian worker, cache container dinamis dan restore grafis
sudah diuji pada client. Tidak ada jaminan FPS tertentu, bebas anticheat, atau hasil
peluru/loot di server; pengujian tersebut tidak dilakukan untuk rilis ini.


### FOV dan outline per kategori

Aimbot ON otomatis menyalakan Show FOV Circle; checkbox FOV tetap bisa dimatikan
manual. Fresh execute tetap semua toggle OFF.

Di Visuals, aktifkan ESP kategori yang dibutuhkan lalu toggle Outline di kategori
tersebut: creature, player, container, ground loot/bag, atau trap. Outline menembus
dinding tanpa fill solid, mengikuti jarak/filter ESP, dan independen dari label.
ESP kategori OFF juga membersihkan outline-nya. Super Potato mematikan kelima
outline sementara; ketika preset OFF, pilihan sebelumnya dikembalikan.


### Perbaikan equip saat Aimbot aktif

Hook senjata v2 meneruskan paket lewat native `FireServer`, sehingga pengecekan
input/raycast di dalam hook tidak mengubah metode equip/reload. Hanya aksi `Fire`
yang boleh dipatch; jumlah argumen dan trailing nil dipertahankan. Dispatch state
selalu diperbarui saat re-execute tanpa memasang wrapper v2 berulang.


### Budget kerja (revisi ringan)

- Maksimal 8 rig baru per pass aim, roster di-cache 1 detik dan dijelajahi
  round-robin. Target lama dicek lagi. Pemilihan target dapat lebih lambat pada
  server ramai; tidak semua rig diperiksa serentak.
- Maksimal 16 visibility raycasts per pass. Target yang belum lolos tes visibilitas
  tidak dianggap terlihat; pencarian dilanjutkan pada pass berikutnya.
- Maksimal 48 label yang masuk layar dan 24 outline terdekat; kedua batas normal
  tersedia di ESP Layout. Potato memakai 20 objek label / 12 outline dan declutter.
  Karena budget, tidak semua objek dalam radius akan tampil sekaligus.
- Tick ESP 0,35 detik normal / 0,6 detik Potato, dibagi antar-frame.
- Per-model event listeners dan query bounding box dihilangkan dari discovery.
  Worker aim/graphics tidak ditambahkan terus-menerus ke registry ketika toggle diulang.
- Potato tidak lagi otomatis menjalankan scan Flat scenery. Flat masih opt-in terpisah.
- Sampel foreground singkat di satu sesi: tanpa hub 23,7 FPS; hub OFF 22,6;
  aim aktif terus 21,7; Potato 25,5. Bukan benchmark panjang atau bukti penyebab
  force-close, dan bukan jaminan FPS/ketahanan untuk semua perangkat/server.
