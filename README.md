# hush

> **Kontrol terbaru:** satu Camera Aimbot ON/OFF, aktivasi selalu **tahan klik kanan**.
> Tidak ada Always On/keypicker. Profil **Humanize / Blatant**, FOV default35°.
> ESP memproses semua arah dalam1000 stud (tetap memakai budget objek terdekat).
> Fullbright kini dijaga terhadap overwrite game; Healthbars tersedia di ESP Layout.


> **Build saat ini: camera-only compatibility.** Silent/Look Aim, No Recoil,
> No Spread dan voice blocking dikarantina setelah laporan force-close saat
> tembakan pertama. Tidak ada hook namecall/sight/spread atau penulisan upvalue
> senjata. Jika pernah memuat versi hook lama, restart Roblox terlebih dahulu.
> Isolasi native pipeline sudah dicek; kestabilan saat tembakan nyata belum diuji.


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
  Pencarian dibatasi sesuai profil: Humanize jeda0,12s, Blatant0,08s, Potato0,18s; tracking tetap per-frame.
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

Aimbot ON otomatis mencakup FOV circle; tidak ada checkbox FOV terpisah lagi.
Fresh execute tetap semua toggle OFF.

Di Visuals, aktifkan ESP kategori yang dibutuhkan lalu toggle Outline di kategori
tersebut: creature, player, container, ground loot/bag, atau trap. Outline menembus
dinding tanpa fill solid, mengikuti jarak/filter ESP, dan independen dari label.
ESP kategori OFF juga membersihkan outline-nya. Super Potato mematikan kelima
outline sementara; ketika preset OFF, pilihan sebelumnya dikembalikan.


### Riwayat: hook equip v2 (sekarang dikarantina)

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


### Verifikasi build camera-only

Fresh execute: 31 toggle OFF. Saat camera aim ON, pointer `__namecall`, fungsi
`equip`/`shoot`, `sight` dan fungsi spread game teramati identik dengan sebelum
load. Compile Luau dan tes guard sesi lama lulus. Tidak ada tembakan otomatis
atau klaim native crash telah terselesaikan. ESP, outline per kategori dan Potato
tetap tersedia. Riwayat penjelasan hook v2 di atas bukan fitur aktif build ini.


### Player LOS dan keybind aktivasi

Player ESP mewarnai nama, accent dan outline hijau bila ray kamera ke head/root
terbuka; kuning bila terhalang atau belum diperiksa. Maksimal 8 rays per pass ESP,
cache 0,4 detik dengan traversal round-robin. Saat budget habis, hasil terakhir
bisa dipakai hingga 2 detik; tanpa hasil valid, tampil kuning. Ini LOS raycast,
bukan pengukuran photometric; perubahan warna bisa terlambat pada server ramai.

Dropdown Activation Key dihapus. Kotak keybind di samping Enable Aimbot bisa
diklik untuk mengganti tombol; klik kanan memilih Hold / Toggle. Default MB2 Hold
(tahan klik kanan). Keybind menyinkronkan checkbox master, bukan tombol kedua yang
harus diaktifkan terpisah. Aim berhenti bergerak saat mengetik di text box. Fresh
execution tetap OFF. Tetap camera-only, tanpa native weapon hooks.


### UI ringkas

Combat kini hanya satu toggle Camera Aimbot + keybind (default MB2 Hold,
klik kanan untuk Toggle), target/hitbox, dan tiga slider FOV/smoothness/distance.
FOV circle, sticky lock, visible-only, fallback hitbox terlihat dan ballistic lead
ikut master aim; OFF juga membersihkan bundle. Cek ray tetap maksimal16/pass.
Dropdown mode satu-pilihan dan tombol diagnostik dihapus dari tampilan.

Anti-overlap ESP otomatis; outline per kategori tetap terpisah sesuai permintaan.
Combat6->1 toggle; total definisi toggle31->25. Silent Aim tetap tidak tersedia,
tidak ada toggle untuk mencobanya, dan belum terbukti aman setelah first-shot crash.
Tidak ada native weapon hooks yang diaktifkan ulang. Revisi ini lolos compile/tes
unit bundle; belum diverifikasi live karena client tidak tersambung saat pengujian.


### Tema Orchid

Palet default mengikuti referensi purple/magenta: background `#210C30`, panel
plum `#4A1B58`, accent pink-magenta `#D65EC8`, outline lilac `#9962B2`, teks
`#F8E9FB`. Preset **Hush Orchid** tersedia di Config → Themes. Mengubah warna/tone,
bukan menyalin ilustrasi papan kayu/jaring. Tidak menambah gambar atau animasi.
Warna semantik ESP, termasuk Player LOS kuning/hijau, tidak berubah. Compile dan
fixture penerapan tema lulus; tampilan live belum dicek karena client belum tersambung.


### Riwayat: Always On (sudah dihapus; kini fixed hold RMB)

Di Combat, aktifkan **Always On (no hold)** untuk sekaligus menyalakan Camera
Aimbot tanpa menahan tombol. Key release tidak mematikannya. Master Camera Aimbot
OFF tetap menghentikan aim; mengetik juga menjeda tracking. Nonaktifkan Always On
untuk menghentikan aim dan kembali ke kontrol keybind Hold/Toggle. Ini setting mode,
bukan auto-start: fresh execute tetap semua toggle OFF. Camera-only tetap berlaku.


### Fullbright, healthbars, 360 ESP dan profil hold-RMB

- Fullbright: Ambient/OutdoorAmbient210, Brightness2,5, Exposure0,35. Empat property
  guards menahan overwrite game; OFF mengembalikan nilai terakhir dari siklus game.
  ClockTime, fog dan efek game tidak ditimpa oleh fitur ini. Guard dilepas saat OFF/unload.
- Healthbars (players / creatures): aktifkan di ESP Layout bersama ESP kategori.
  HP/MaxHP dari Humanoid atau atribut terverifikasi, tidak mengarang HP maksimum;
  bar disembunyikan bila datanya tidak ada. Tidak berlaku untuk loot biasa.
- ESP tidak lagi menolak objek karena arah kamera; data/health tetap diperbarui di
  belakang kamera. Billboard belakang di-clip oleh renderer Roblox, bukan muncul
  di tengah layar sebagai penanda palsu. Angka default/batas jarak1000 stud.
  Budget normal48 label/24 outline dan Potato20/12 tetap memilih objek terdekat;
  tidak semua objek dalam radius dijamin tampil jika budget penuh.
- Satu master aim + fixed hold RMB. Lepas RMB berhenti tracking, mengetik menjeda.
  Humanize cepat dengan smoothing eksponensial18/s; Blatant direct camera look.
  Tidak ada jitter acak. Tetap camera-only; akurasi kamera bukan jaminan hit server
  atau lolos anticheat. FOV35° default, bisa10..120; range aim maksimal1000 stud.
- Local camera/viewmodel dikecualikan dari aim visibility; first visible hitbox,
  prioritas arah crosshair saat mencari target, tanpa holdoff1,4 detik lama.
  Target harus hidup, terlihat, dalam jarak dan FOV agar lock/ring hijau.
- Fail-safe: NaN/extreme vector dan arah vertikal dijaga, error render/scan dibatasi
  dan aim OFF setelah3 error berturut-turut. Library UI di-unload dengan benar;
  callback Hush keypicker lama dikarantina secara spesifik saat boot. Bukan jaminan
  tidak pernah ada error/native crash; tidak ada tembakan otomatis dalam tes ini.
