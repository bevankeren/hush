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
  Pencarian dibatasi maksimal 10 Hz (6,7 Hz pada Potato); tracking tetap per-frame.
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
