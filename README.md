# OpenFlow

Dyktowanie push-to-talk dla macOS, po polsku i angielsku, z tłumaczeniem
PL→EN w locie. Osobisty zamiennik Wispr Flow: bez subskrypcji, rozpoznawanie
mowy w całości lokalne (audio nie opuszcza komputera), jakość polskiego
dobrana pomiarem, a nie marketingiem.

Trzymasz klawisz, mówisz, puszczasz. Tekst ląduje w aktywnej aplikacji:
w edytorze, przeglądarce, Slacku, terminalu, gdziekolwiek.

Aplikacja żyje tylko w pasku menu (ikona mikrofonu), bez ikony w Docku.

## Funkcje w skrócie

- **Dyktowanie push-to-talk** (domyślnie prawy ⌘): mowa staje się tekstem
  w języku, w którym mówisz. Polski i angielski, wykrywane automatycznie.
- **Tłumaczenie w locie** (domyślnie prawy ⌃): mówisz po polsku, wkleja się
  angielski.
- **Style tekstu, osobno dla dyktowania i tłumaczenia**: Normalny
  (dopracowana proza) i Luźny (czat: małe litery, bez kropek).
- **TAB w trakcie nagrywania**: przełącza język dyktowania (Auto/PL/EN)
  albo styl tłumaczenia, na żywo, bez puszczania klawisza.
- **Rekorder skrótów**: kliknij przycisk, naciśnij klawisz, ustawione.
- **Profil programisty**: feature, PR, commit, deploy zostają po angielsku
  i są naprawiane, gdy rozpoznawanie je przekręci ("pi ar" → "PR").
- **Poprawianie AI**: interpunkcja, usuwanie "yyy", naprawa polskich
  końcówek. Domyślnie DeepSeek V4 Flash przez OpenRouter, grosze miesięcznie.
- **Wszystko ma fallback**: brak internetu czy klucza API nigdy nie blokuje
  dyktowania.
- **Prywatność**: transkrypcja w 100% lokalna (Whisper na Neural Engine),
  klucz API tylko w zmiennej środowiskowej, nigdzie nie zapisywany.

## Szybki start

```sh
git clone <to-repo> && cd open-flow
make install                                   # buduje i kopiuje do /Applications
launchctl setenv OPENROUTER_API_KEY sk-or-...  # opcjonalnie, dla funkcji AI
open /Applications/OpenFlow.app
```

Potem:

1. Zgódź się na dostęp do **Mikrofonu** i nadaj **Dostępność**
   (Ustawienia systemowe → Prywatność i ochrona → Dostępność).
2. Poczekaj na pobranie modelu (~1.5 GB) i jednorazową specjalizację
   Core ML (~8 minut, tylko za pierwszym razem).
3. Przytrzymaj prawy ⌘, powiedz coś po polsku, puść. Tekst się wklei.
4. Włącz w menu "Poprawiaj tekst przez AI", jeśli ustawiłeś klucz.

## Funkcje szczegółowo

### Dwa skróty push-to-talk

| Skrót (domyślny) | Działanie |
| --- | --- |
| Prawy ⌘ | **Dyktowanie**: tekst w języku, w którym mówisz (PL lub EN) |
| Prawy ⌃ | **Tłumaczenie**: mówisz po polsku, wkleja się angielski |

Oba skróty ustawia się rekorderem "kliknij przycisk, naciśnij klawisz".
Zadziała dowolny pojedynczy klawisz: modyfikator (prawy ⌘, prawy ⌃, Fn...)
albo zwykły klawisz (np. F13). Zwykły klawisz trzymany jako push-to-talk jest
połykany przez aplikację, więc nie wpisuje znaków w aktywnym oknie. Escape
anuluje nagrywanie skrótu, rekorder rozbraja się sam po 10 sekundach,
a TAB nie może być skrótem, bo jest zarezerwowany do przełączania (niżej).
Ten sam klawisz nie może pełnić obu ról.

Podczas nagrywania przy dolnej krawędzi ekranu wisi pigułka pokazująca stan
("Słucham…", "Rozpoznaję…", "Poprawiam…", "Tłumaczę…") oraz aktywny język
lub styl. Widać ją też nad aplikacjami pełnoekranowymi.

### TAB w trakcie nagrywania

Trzymając skrót, naciśnij TAB:

- przy **dyktowaniu** przełącza język: Auto → PL → EN → Auto...
- przy **tłumaczeniu** przełącza styl: Normalny ↔ Luźny

Wybór widać na żywo na pigułce i jest trwały (zostaje na kolejne dyktowania,
do zmiany TAB-em albo w ustawieniach). TAB jest konsumowany przez aplikację,
więc nie przeskakuje focusa ani nie odpala przełącznika ⌘Tab.

Wymuszenie PL/EN pomija detekcję języka. Przydatne, gdy auto-wykrywanie
się pomyli albo gdy dyktujesz krótkie wtrącenia.

### Style dyktowania i tłumaczenia

Dyktowanie (styl nakłada przebieg Poprawiania AI):

- **Normalny**: pełna interpunkcja, wielkie litery, dopracowana proza.
- **Luźny**: jak na czacie. Wszystko małymi literami (akronimy typu PR, API
  i identyfikatory kodu zachowują pisownię), bez kropek na końcu zdań,
  myśli rozdzielane przecinkami albo nową linią.

Tłumaczenie:

- **Normalny**: wierny i profesjonalny. Do opisów PR-ów, ticketów,
  dokumentacji, maili.
- **Luźny**: swobodny i idiomatyczny, jak native-speaker programista piszący
  na Slacku. Model może przeredagować zdanie, byle sens został.

Oba style przełączysz w menu przy ikonie mikrofonu albo w Ustawieniach;
styl tłumaczenia dodatkowo TAB-em w trakcie nagrywania.

### Profil programisty

Prompty czyszczenia i tłumaczenia zakładają, że mówi programista. Angielskie
terminy techniczne (feature, PR, merge request, commit, deploy, branch, code
review, backlog, standup, endpoint, bug...) zostają po angielsku, nigdy nie są
spolszczane ani tłumaczone, a przekręcone przez rozpoznawanie mowy formy są
naprawiane ("pi ar" staje się "PR", "komit" staje się "commit").

Do tego dochodzi **słownik osobisty**: dowolne linie doklejane do promptów
(pisownia nazwisk, nazwy projektów, żargon), edytowany w Ustawieniach.

### Poprawianie tekstu przez AI (opcjonalne)

Drugi przebieg po transkrypcji: interpunkcja, wielkie litery, usuwanie
"yyy"/"eee" i falstartów, naprawa polskich końcówek i znaków diakrytycznych.
Domyślnie DeepSeek V4 Flash przez OpenRouter; zadziała każde API zgodne
z formatem OpenAI (w ustawieniach można zmienić adres i model). Gdy API nie
odpowie w limicie czasu, wkleja się surowa transkrypcja.

Koszt: jedno dyktowanie z poprawianiem to ~0.003 grosza, tłumaczenie
~0.01 grosza. Przy intensywnym używaniu wychodzi kilkanaście groszy
miesięcznie.

### Zawsze jest fallback

| Scenariusz | Co się dzieje |
| --- | --- |
| Brak klucza API / brak internetu przy dyktowaniu | wkleja się surowa transkrypcja Whispera |
| Brak klucza API / błąd sieci przy tłumaczeniu | tłumaczy lokalny Whisper (task translate), bez stylu, ale offline |
| Nagranie krótsze niż 0.35 s | ignorowane (przypadkowe muśnięcie klawisza) |
| Prawie-cisza | znane halucynacje Whispera ("Thank you.", napisy amara.org itp.) są wycinane |
| Schowek | zapamiętywany przed wklejeniem i przywracany po 0.4 s |

## Jak to działa

```
trzymasz skrót ──▶ AVAudioEngine nagrywa 16 kHz mono
                          │
puszczasz ────────────────▼
              WhisperKit / Core ML na Neural Engine
                          │  język: auto (tylko pl/en) albo wymuszony TAB-em
                          ▼
   dyktowanie: opcjonalny przebieg LLM (czyszczenie + styl, timeout 4 s,
               fallback na surowy tekst)
   tłumaczenie: przebieg LLM w wybranym stylu (fallback na lokalne
               tłumaczenie Whispera)
                          │
                          ▼
          wklejenie do aktywnej aplikacji przez ⌘V
          (schowek jest zapamiętywany i przywracany)
```

Trzy detale decydują o jakości polskiego:

- **Detektor języka jest ograniczony do polskiego i angielskiego.**
  Nieograniczony detektor Whispera regularnie bierze polską mowę za czeski
  albo słowacki, co rujnuje transkrypcję. OpenFlow porównuje tylko
  prawdopodobieństwa `pl` i `en`.
- **Detekcja ma bias w stronę polskiego.** Angielski wygrywa dopiero przy
  wyraźnej przewadze (margines 0.2). Polski dev-slang pełen słów typu
  "code review" ciągnie detektor w stronę EN, a błędny EN jest najgorszą
  awarią: Whisper wtedy tłumaczy polską mowę zamiast ją spisać. Błędny PL
  na angielskiej mowie to tylko krzywa transkrypcja, do powtórzenia
  z TAB→EN.
- **Domyślny model to `large-v3-turbo`, wybrany pomiarem.** Turbo tnie
  dekoder z 32 warstw do 4, co podobno kosztuje jakość w językach innych niż
  angielski. Na polskiej mowie na tej maszynie transkrybował **3.7× szybciej**
  (speed factor 6.6 vs 1.8, 39 vs 10 tokenów/s) i oddał polskie znaki oraz
  odmianę co najmniej tak dobrze jak pełny large-v3. Pełny large-v3 zostaje
  jako opcja w ustawieniach.

## Wymagania

- macOS 14 lub nowszy, Apple Silicon
- Xcode (dla toolchaina Swift)
- ~1.5 GB dysku na domyślny model (więcej dla pełnej precyzji)
- konto OpenRouter (albo dowolne API zgodne z OpenAI) do funkcji AI;
  bez niego działa dyktowanie offline i tłumaczenie lokalne

## Budowanie

```sh
make build     # kompilacja + złożenie + podpisanie build/OpenFlow.app
make run       # jak wyżej, potem uruchomienie
make install   # kopiuje do /Applications
make logs      # podgląd logów aplikacji
make clean     # czyści artefakty builda
```

`Scripts/bundle.sh` podpisuje aplikację Twoją tożsamością Apple Development.
To ważne: macOS wiąże zgody na Mikrofon i Dostępność z podpisem kodu, więc
podpis ad-hoc oznaczałby ponowne klikanie zgód po każdej przebudowie.
Inną tożsamość wskażesz przez `IDENTITY=...`.

## Pierwsze uruchomienie

1. Zgoda na **Mikrofon** (standardowy systemowy prompt).
2. Zgoda na **Dostępność** (Ustawienia systemowe → Prywatność i ochrona →
   Dostępność). Potrzebna podwójnie: żeby widzieć skróty globalnie i żeby
   wysyłać ⌘V do innych aplikacji. Aplikacja sama wykrywa nadanie zgody,
   bez restartu.
3. Pobranie modelu mowy (~1.5 GB) do
   `~/Library/Application Support/OpenFlow/models`. Postęp widać w menu.

Potem uzbrój się w cierpliwość dokładnie raz. Core ML musi "wyspecjalizować"
model pod Twój chip; dla modelu tej wielkości trwało to tu **około 8 minut**.
Apple cache'uje wynik poza aplikacją, więc każdy kolejny start ładuje model
w kilka sekund. To samo czekanie wraca po zmianie modelu albo gdy aktualizacja
macOS wyczyści cache.

Po zbudowaniu cache aplikacja nie dotyka sieci do transkrypcji. Pobiera
ponownie tylko wtedy, gdy plików modelu fizycznie brakuje.

## Klucz API (tylko zmienna środowiskowa)

Klucz nie jest nigdzie zapisywany przez aplikację: ani w ustawieniach, ani
w Keychain. Czytany jest wyłącznie ze zmiennej `OPENROUTER_API_KEY`.

Aplikacje GUI dziedziczą środowisko launchd, a nie shella, więc `export`
w `.zshrc` nie wystarczy:

```sh
launchctl setenv OPENROUTER_API_KEY sk-or-...   # do najbliższego restartu
```

Żeby klucz przetrwał restart komputera, wrzuć tę linię do LaunchAgenta albo
skryptu logowania, albo uruchamiaj aplikację z terminala z wyeksportowaną
zmienną. Status klucza ("Wczytany ze środowiska" / "Nie znaleziono") widać
w Ustawieniach na karcie Poprawianie AI.

## Ustawienia

**Skróty.** Rekorder kliknij-i-naciśnij dla obu skrótów. Prawy ⌥ Option to
zły wybór na polskim układzie Polish Pro, bo to klawisz od ą ć ę ł ń ó ś ź ż.
Klawisz 🌐 Fn działa po ustawieniu Ustawienia systemowe → Klawiatura →
"Naciśnięcie klawisza 🌐" → "Nic nie rób".

**Język dyktowania.** Auto / Polski / Angielski. To samo, co przełącza TAB.

**Styl dyktowania.** Normalny / Luźny. Luźny pisze małymi literami i bez
kropek; wymaga włączonego Poprawiania AI.

**Styl tłumaczenia.** Normalny / Luźny. To samo, co przełącza TAB przy
skrócie tłumaczenia.

**Model rozpoznawania.** Domyślnie `large-v3-turbo`. Zmiana modelu uruchamia
pobieranie i nową specjalizację Core ML (znów kilka minut, raz).

**Poprawianie AI.** Przełącznik, adres API, nazwa modelu, timeout. Wyłączone,
dopóki w środowisku nie ma klucza.

**Słownik osobisty.** Dowolne linie doklejane do promptów AI: pisownia
nazwisk, nazwy projektów, żargon. Jedna reguła na linię.

**Zachowanie.** Dźwięki startu/końca nagrywania i przełączania TAB-em,
autostart przy logowaniu.

Szybki dostęp do języka, stylów i przełącznika AI jest też w menu przy ikonie
mikrofonu, razem z ostatnią transkrypcją i przyciskiem jej skopiowania.

## Rozwiązywanie problemów

**Mówię po polsku, a wychodzi angielski.** Trzy możliwości: trzymasz skrót
tłumaczenia zamiast dyktowania (pigułka pokaże "PL→EN"), TAB-em przełączyłeś
język na EN (pigułka pokaże "EN"), albo auto-detekcja się pomyliła. Sprawdź
w logach linię `detekcja języka: ... (pl=... en=...)`:

```sh
make logs        # albo: log stream --predicate 'process == "OpenFlow"'
```

Doraźnie: TAB do wymuszenia PL.

**Skróty nie reagują.** Brak zgody Dostępność, albo cofnęła się po
przebudowie z inną tożsamością podpisu. Sprawdź badge w Ustawieniach.

**Aplikacja długo "Ładowanie modelu…" po aktualizacji macOS.** System
wyczyścił cache Core ML; specjalizacja leci od nowa (~8 minut), raz.

**Poprawianie AI wyszarzone.** Brak klucza w środowisku: `launchctl setenv`,
potem restart aplikacji.

**Wkleja się "Thank you." albo napisy z amara.org.** To halucynacje Whispera
na ciszy; znane wzorce są wycinane, nowe zgłoś (dopisz do listy
w `TranscriptionEngine.swift`).

## Układ kodu

| Plik | Rola |
| --- | --- |
| `AppState.swift` | Orkiestracja: skrót → nagranie → transkrypcja → czyszczenie/tłumaczenie → wklejenie |
| `HotkeyManager.swift` | Globalny `CGEventTap`: dwa klawisze push-to-talk, TAB, rekorder skrótów |
| `AudioRecorder.swift` | Nagrywanie `AVAudioEngine`, resampling do 16 kHz mono |
| `TranscriptionEngine.swift` | WhisperKit: pobieranie, ładowanie, transkrypcja, lokalne tłumaczenie |
| `CleanupService.swift` | Przebieg czyszczący ze stylem (API zgodne z OpenAI) |
| `TranslationService.swift` | Tłumaczenie PL→EN, styl normalny albo luźny |
| `TextInserter.swift` | Zapis schowka / wklejenie / przywrócenie |
| `RecordingIndicator.swift` | Pływająca pigułka, widoczna też w trybie pełnoekranowym |
| `Preferences.swift` | UserDefaults + klucz z ENV + autostart |
| `MenuContentView.swift` | Menu przy ikonie w pasku |
| `SettingsView.swift` | Okno ustawień |

Szczegóły techniczne, które łatwo zgubić:

- Tap zdarzeń jest **aktywny** (`.defaultTap`), nie listen-only, bo TAB
  i zwykłe klawisze-skróty muszą być konsumowane zanim zobaczy je aktywna
  aplikacja. Zdarzenia modyfikatorów (flagsChanged) zawsze przechodzą dalej.
- System wyłącza tap, który za długo blokuje; callback obsługuje
  `tapDisabledByTimeout` i włącza tap z powrotem.
- Wklejanie robi snapshot schowka, podmienia go, wysyła syntetyczne ⌘V
  i po 0.4 s przywraca poprzednią zawartość.
- Modele lądują w Application Support, nie w ~/Documents (domyślna
  lokalizacja klienta HuggingFace jest zła dla wielogigabajtowych plików).
- Uprawnienia są odpytywane co 2 s, więc nadanie zgody w Ustawieniach
  systemowych uzbraja aplikację bez restartu.

## Znane ograniczenia

- Realnie tylko Apple Silicon; Core ML na Intelu byłby dużo wolniejszy.
- Aplikacja nie jest sandboxowana, bo sandbox nie pozwala na globalny event
  tap, którego wymaga push-to-talk.
- Nagrania są ucinane po 5 minutach, żeby zaklinowany klawisz nie rósł
  buforem w nieskończoność.
- Tłumaczenie wymusza transkrypcję po polsku. Jak przy trzymaniu skrótu
  tłumaczenia zaczniesz mówić po angielsku, wyjdzie kalectwo; pigułka zawsze
  pokazuje, który tryb jest aktywny.
- Whisper z wymuszonym językiem EN na polskiej mowie potrafi tłumaczyć
  zamiast transkrybować; to zachowanie modelu, nie bug aplikacji. Tryb Auto
  albo wymuszony PL załatwiają sprawę.
