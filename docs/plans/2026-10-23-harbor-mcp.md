# Harbor 1.1 · Ajanın kullanabildiği dev server yöneticisi — uygulama planı

> **For agentic workers:** Implement this plan task-by-task — a fresh subagent per task where tasks are independent, otherwise inline with a review checkpoint per batch. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Claude Code ve Codex, Harbor'a kayıtlı servisleri bir MCP sunucusu üzerinden listeleyip başlatabilsin, durdurabilsin ve loglarını okuyabilsin. Ajan hiçbir zaman komut uydurmaz, süreç öldürmez: yalnız insanın Harbor'a kaydettiği servisleri, Harbor'ın tmux oturumları üzerinden yönetir.

**Neden:** Ajanlar dev server'ı arka planda başlatıyor, PID'i kaybediyor, sonra `pkill`/`killall` ile desenle öldürmeye çalışıp alakasız uygulamaları kapatabiliyor; logları okumak için terminali tahmin ediyor. Harbor bunu zaten doğru yapıyor (tmux, sabit oturum adları, port ve sağlık kontrolü) ama ajana açık bir arayüzü yok. Kaynak: Idea Radar, fikir #10.

**Rakip:** "dev server mcp", "mcp process manager logs", "tmux mcp dev server" aramalarında yalnız 1–3★ repolar var (23 Ekim). En yakın yerleşik karşılık Claude Code'un arka planda komut çalıştırması; ama o süreç oturumla ölür, başka ajanla ya da insanla paylaşılmaz, portu ve sağlığı bilinmez. Harbor'ın farkı: servisler tmux'ta yaşar, aynı servisi insan da ajan da aynı yerden görür.

**Architecture:** Ayrı hedef ya da bağımlılık yok. Aynı ikili dosya `Harbor mcp` argümanıyla AppKit'i hiç başlatmadan stdio üzerinde MCP sunucusu olarak çalışır (`main.swift` dallanır). Durum hesabı `Runner.poll`'dan saf bir `Snapshot`'a çıkarılır; uygulama ve MCP aynı kodu kullanır. MCP `projects.json`'u yalnız okur, servisleri `Tmux.start` ile uygulamanın kullandığı oturum adlarıyla başlatır; uygulama açıksa 2 saniyelik poll yeni oturumu kendiliğinden görür ve sahiplenir (`start` canlı paneli zaten sahipleniyor).

**Tech Stack:** Swift 6, SwiftUI + AppKit, tmux. JSON-RPC elle (Foundation `JSONSerialization`), MCP SDK yok.

## Bugün olan (koddan doğrulandı)

- Servisler `tmux -S /tmp/harbor-<uid>.sock` üzerinde, oturum adı `hb-<shortID>-<serviceID ilk 8>` (`Project.session(for:)`); uygulama kapansa da yaşıyor.
- Başlatma `Tmux.start`: `remain-on-exit` panenin içinden, `zsh -l -i -c`, `Shell.userPath` enjekte. Durdurma `Tmux.interrupt` (C-c) + 1,2 sn sonra `Tmux.kill`.
- Durum, port ve sağlık `Runner.poll` içinde: tek `list-panes -a`, tek `ps`, tek `lsof -a`, ardından sağlık URL'si yoklaması. `@MainActor` sınıfına gömülü, dışarıdan kullanılamıyor.
- Log `Tmux.capture` + `Runner.strippingANSI` (300 satır).
- `projects.json` → `~/Library/Application Support/Harbor/projects.json`; `Service`/`Project` elle decode ediliyor.
- Test: `tests/security/run.sh` (kaçış/quoting ve güncelleme bütünlüğü). XCTest hedefi yok.

## Global Constraints

- Bağımlılık yok (CLAUDE.md: "no dependencies"). MCP protokolü elle; küçük bir JSON-RPC döngüsü.
- Kod yorumu yok (global kural); tanımlayıcılar İngilizce; yeni renk ve ölçü yalnız `Theme.swift`'te.
- MCP modunda stdout yalnız protokol içindir; her teşhis satırı stderr'e.
- Ajan **asla**: kayıtlı olmayan bir komut çalıştıramaz, servis ekleyemez ya da düzenleyemez, port boşaltamaz (`Terminals.free`), PID öldüremez. Durdurma yalnız Harbor'ın kendi tmux oturumunu hedefler.
- CLAUDE.md'deki "hard-won rules" geçerli: `Process.waitUntilExit()` yok, her alt sürece `FileHandle.nullDevice`, tmux UTF-8 locale ile.
- `swift build` ve `tests/security/run.sh` her görev sonunda temiz. Commit, sürüm ve yayın Eren'de.

## Dosya yapısı

| Dosya | Görev |
| --- | --- |
| `Sources/Harbor/Core/Snapshot.swift` | `Runner.poll`'un saf kısmı: hedeflerden durum, port, çakışma |
| `Sources/Harbor/Core/Runner.swift` | `poll` → `Snapshot.take`; davranış değişmez |
| `Sources/Harbor/Core/MCP.swift` | stdio JSON-RPC döngüsü, araç tanımları ve işleyiciler |
| `Sources/Harbor/main.swift` | `mcp` argümanında AppKit'siz dal |
| `Sources/Harbor/Core/Tmux.swift` | `PaneState.origin` (`#{@harbor_origin}`), `markOrigin(session:)` |
| `Sources/Harbor/Core/Paths.swift`, `Tmux.swift` | test için `HARBOR_SUPPORT_DIR` ve `HARBOR_TMUX_SOCKET` ortam değişkenleri |
| `Sources/Harbor/Views/ServicesPanel.swift`, `StripView.swift` | "agent" rozeti |
| `Sources/Harbor/Views/SettingsView.swift` | "Coding agents" bölümü: Claude Code'a ekle, Codex komutu |
| `tests/mcp/run.sh` | uçtan uca protokol testi, yalıtılmış ortamda |
| `README.md`, `CLAUDE.md`, `docs/index.html`, `VERSION` | belge ve sürüm |

---

## Görev 0 · Doğrulama (varsayım yok)

- [ ] MCP spesifikasyonu (güncel sürüm): stdio taşıma (satır başına bir JSON mesajı), `initialize` sürüm pazarlığı, `tools/list` şeması (`inputSchema`), `tools/call` sonucu (`content: [{type: "text"}]`, `isError`), `notifications/initialized`, `ping`. Kaynak: modelcontextprotocol.io ve spec reposu.
- [ ] Claude Code stdio MCP sunucusunu hangi `cwd` ile başlatıyor? (Proje çözümlemesi buna dayanıyor.) `claude mcp add --scope user <name> -- <command> <args>` sözdizimi ve `claude mcp get`.
- [ ] Codex: `codex mcp add` var mı, yoksa yalnız `~/.codex/config.toml` → `[mcp_servers.harbor]` mı; `cwd` davranışı.
- [ ] tmux kullanıcı seçeneği: `set-option -t <session> @harbor_origin agent` ve `list-panes -a -F '#{@harbor_origin}'` formatta okunabiliyor mu (oturum seçeneği pane formatında görünüyor mu).
- [ ] Çıktı: bu dosyanın altına "Doğrulama notları" bölümü; tutmayan varsayım varsa ilgili görev güncellenir.

## Görev 1 · Durum hesabını paylaşılabilir yapmak

- [ ] `Core/Snapshot.swift`: `struct ServiceState { status, port, conflict, origin }`, `enum Snapshot { static func take(_ targets: [Target], alreadyFailed: Set<UUID>) async -> [UUID: ServiceState] }`. `Runner.poll`'daki pane, süreç ağacı, port, sağlık yoklaması ve "yeni ölen servisin port çakışması" adımları birebir taşınır; `probe`, `portInUse`, `strippingANSI` `Snapshot`'a geçer.
- [ ] `Runner.poll` yalnız hedefleri toplar, `Snapshot.take`'i çağırır, `apply` eder. `apply`'ın "değişmeyeni yayınlama" kuralı yerinde kalır.
- [ ] Doğrulama: `swift build`; uygulamada bir servisi başlat/durdur, port ve sağlık noktası eskisi gibi; çöken servis için çakışma bandı eskisi gibi.

## Görev 2 · `Harbor mcp`: protokol iskeleti

- [ ] `main.swift`: `CommandLine.arguments.dropFirst().first == "mcp"` ise `MCP.run()` ve çık; `NSApplication` hiç oluşturulmaz.
- [ ] `MCP.run()`: stdin'den satır satır oku, her satır bir JSON-RPC mesajı. `initialize` (istemcinin sürümünü destekliyorsa yansıt, değilse desteklenen en yenisi; `capabilities: { tools: {} }`, `serverInfo: { name: "harbor", version: VERSION }`), `notifications/initialized` (yanıt yok), `ping`, `tools/list`, `tools/call`. Bilinmeyen metot `-32601`, bozuk JSON `-32700`, geçersiz parametre `-32602`.
- [ ] Araç hataları JSON-RPC hatası değil, `isError: true` olan araç sonucu (ajan okuyup devam edebilsin).
- [ ] Doğrulama: `printf '%s\n' '{"jsonrpc":"2.0","id":1,"method":"initialize",...}' | .build/debug/Harbor mcp` geçerli yanıt; stdout'ta protokol dışı tek bayt yok.

## Görev 3 · Araçlar

Proje çözümlemesi her araçta aynı: `project` (ad ya da yol) verilirse o; verilmezse sunucunun `cwd`'sini içeren en uzun `project.path`. Bulunamazsa hata: kayıtlı projelerin listesi ve "Bu klasörü Harbor'a eklemesini kullanıcıdan iste". Servis yalnız tam ad ya da id ile bulunur; bulunamazsa projedeki servis adları ve "Kullanıcıdan servisi Harbor'a eklemesini iste".

- [ ] `list_services(project?)` → `{ project, path, services: [{ name, command, status: stopped|starting|running|failed, exit_code?, port?, url?, health?, started_by: user|agent }] }`.
- [ ] `start_service(service, project?, wait_seconds = 20, ≤ 120)` → canlı pane varsa sahiplen (başlatma yok); ölü pane varsa `kill` + `start`; değilse `start`. Ardından `@harbor_origin agent` işareti. `wait_seconds` boyunca 1 sn aralıkla `Snapshot`: `running` (port ya da sağlık tamam) ya da `failed` olunca dön. Sonuç: durum, port, url, son 40 log satırı; port çakışması varsa portu tutan sürecin adı (öldürmeden).
- [ ] `stop_service(service, project?)` → `Tmux.interrupt`, 1,2 sn, `Tmux.kill`; yalnız o oturum.
- [ ] `restart_service(service, project?, wait_seconds)` → `Runner.restart` sırası, ardından `start_service` gibi bekleme ve sonuç.
- [ ] `read_logs(service, project?, lines = 200, ≤ 2000, contains?)` → `Tmux.capture` + ANSI temizliği; `contains` düz metin (regex değil, kabuğa gitmez), eşleşen satırlar ve öncesi/sonrası 2 satır.
- [ ] Araç açıklamaları ajana yol gösterir: "Use this instead of starting dev servers yourself in the background", "Never kill processes by name; stop_service stops only Harbor's own session".

## Görev 4 · Uygulamada "ajan başlattı" rozeti

- [ ] `Tmux.paneStates` formatına `#{@harbor_origin}` eklenir → `PaneState.origin`; `Snapshot` taşır; `Runner` `origins: [UUID: String]` yayınlar.
- [ ] `ServicesPanel` satırında ve strip'te küçük "agent" etiketi (yalnız `origin == "agent"` ve canlıyken). Renk ve ölçü `Theme.swift`'te.
- [ ] Uygulamadan elle başlatma ya da durdurma işareti temizler (`set-option -u`).

## Görev 5 · Bağlantı ayarı

- [ ] `SettingsView`'a "Coding agents" bölümü:
  - Claude Code: durum (`claude mcp get harbor` sonucu) ve "Add to Claude Code" düğmesi → kullanıcı tıklayınca `claude mcp add --scope user harbor -- <bundle>/Contents/MacOS/Harbor mcp` (Görev 0'da doğrulanan sözdizimi), sonuç satırı.
  - Codex: kopyalanabilir komut ya da `config.toml` parçası; Harbor Codex ayar dosyasına kendisi yazmaz.
  - Önerilen izin listesi (yalnız okuma araçları): `mcp__harbor__list_services`, `mcp__harbor__read_logs`; başlatma ve durdurma onayla kalır.
- [ ] Uygulama `/Applications` dışında çalışıyorsa (geliştirme) uyarı: komut o yolu gösterir.

## Görev 6 · Testler

- [ ] `Paths` ve `Tmux` `HARBOR_SUPPORT_DIR` ve `HARBOR_TMUX_SOCKET` ortam değişkenlerine uyar; testler gerçek servislere ve gerçek `projects.json`'a dokunmaz.
- [ ] `tests/mcp/run.sh`: yalıtılmış dizinde fixture `projects.json` (servis: `python3 -m http.server 8791`, sağlık `/`), sonra protokol üzerinden: `initialize` → `tools/list` → `list_services` (stopped) → `start_service` (running, port 8791) → `read_logs` (`contains: "GET"` için önce `curl`) → `stop_service` (stopped). Bitişte yalnız test soketindeki tmux sunucusu kapatılır (`kill-server` o sokete).
- [ ] Olumsuz durumlar: bilinmeyen servis, bilinmeyen proje, `service` alanında kabuk karakterleri (`; rm`, `$(…)`), `lines: 999999` → sınırlanır, bozuk JSON → `-32700`.
- [ ] `tests/security/run.sh`'a adım: "MCP üzerinden kayıtlı olmayan komut çalıştırılamaz".

## Görev 7 · Belgeler ve 1.1.0

- [ ] README: "Your agent can use it too" bölümü (kurulum tek satır, beş araç, güvenlik sınırları, izin listesi önerisi).
- [ ] CLAUDE.md "Hard-won rules"a MCP modunun kuralları (stdout protokol, AppKit yok, ajan sınırları).
- [ ] `docs/index.html`: kısa bölüm ve GIF.
- [ ] GIF (`.github/mcp.gif`): Claude Code'a "API'yi başlat ve neden 500 verdiğini bul" → strip'te servis yeşile döner, "agent" rozeti → ajan `read_logs` ile stack trace'i okur, düzeltir → `restart_service`.
- [ ] `VERSION` → `1.1.0`; Eren: `./dist.sh`, release, notlar.
- [ ] Gönderiler (tanıtım oturumunda): r/ClaudeCode ("a dev server manager your agent can't misuse"), r/macapps, Show HN. Hither 0.2 ve paper-ink gönderileriyle aynı hafta değil.

## Açık sorular

1. **Ajan yeni servis önerebilsin mi?** Magic'teki gibi, kullanıcının işaretleyeceği bir öneri olarak (`propose_service`). Öneri: 1.1'de yok; kayıtlı olmayan servis için hata mesajı kullanıcıya yönlendirir. Talep gelirse 1.2.
2. **Ajanın başlattığı servis oturum bitince dursun mu?** Öneri: hayır. Harbor'ın ilkesi servislerin yaşaması; rozet kimin başlattığını gösterir.
3. **Sürüm sırası:** Hither 0.2 ve paper-ink lansmanlarından sonraki hafta.

## Ölçüm

Harbor bugün 0★ (v1.0.0, 22 Ekim). Hedef: 1.1 yayınından sonraki 1. hafta +30★, 2. hafta +100★. Idea Radar'da `erenbekman` takipte.
