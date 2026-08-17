# FS25 NPC Crop Damage

**NPC Crop Damage** rozszerza standardowy mechanizm niszczenia upraw w *Farming Simulator 25* na pola należące do NPC. Jeżeli gracz wjedzie pojazdem w podatną na zniszczenie uprawę na takim polu, rośliny zostaną zniszczone tak samo jak na własnym polu, a gospodarstwo gracza zostanie obciążone kosztem szkód.

Mod działa wyłącznie dla pojazdów kierowanych przez gracza i respektuje ustawienie gry **Niszczenie upraw**.

## Założenia

Mod został zaprojektowany jako możliwie niewielkie rozszerzenie mechaniki podstawowej gry:

- nie zastępuje standardowego systemu `WheelDestruction`;
- nie zmienia zachowania niszczenia upraw na polach należących do gracza;
- rozszerza działanie wyłącznie na pola NPC, czyli grunty rolne bez właściciela będącego gospodarstwem gracza;
- działa tylko wtedy, gdy w ustawieniach gry włączono **Niszczenie upraw**;
- działa tylko dla pojazdów faktycznie kierowanych przez gracza;
- ignoruje pracowników AI;
- respektuje opony pielęgnacyjne / koła, których podstawowa gra nie traktuje jako niszczących uprawy;
- niszczy tylko te typy i stany wzrostu roślin, które podstawowa gra oznacza jako podatne na zniszczenie przez koła;
- nie wymusza niszczenia upraw okopowych, które w standardowej grze nie podlegają temu mechanizmowi, m.in. ziemniaków, buraków cukrowych i buraków czerwonych.

## Jak działa mod

Skrypt jest dołączany do standardowej funkcji `WheelDestruction:update()`. Podstawowa gra najpierw wykonuje własną obsługę koła, a mod uruchamia dodatkową ścieżkę tylko wtedy, gdy koło znajduje się na polu NPC.

Przed zmianą stanu roślin skrypt sprawdza mapę gęstości uprawy i liczy wyłącznie piksele znajdujące się jeszcze w stanach podatnych na zniszczenie. Dopiero później wywoływana jest standardowa funkcja gry odpowiedzialna za zniszczenie rośliny.

Takie rozwiązanie ma dwie zalety:

1. zachowuje zasady niszczenia zdefiniowane przez grę lub mapę;
2. ogranicza wielokrotne naliczanie odszkodowania za ten sam, już zniszczony fragment uprawy.

## Ostrzeżenie

Gdy pojazd gracza **faktycznie zacznie niszczyć uprawę na polu NPC**, wyświetlany jest komunikat:

> Uwaga! Niszczysz uprawy na polu NPC. Zostaniesz obciążony kosztami szkód.

Dostępna jest również wersja angielska:

> Warning! You are damaging crops on an NPC field. You will be charged for the damage.

Teksty znajdują się w sekcji `l10n` pliku `modDesc.xml`, więc można łatwo dodać kolejne języki.

Komunikat nie jest generowany przy samym wjechaniu na pole. Musi zostać wykryta nowa powierzchnia uprawy, którą można rzeczywiście zniszczyć. Aby wiele kół i kolejne klatki animacji nie tworzyły serii komunikatów, nowe ostrzeżenie pojawia się dopiero po przerwie w niszczeniu.

## Obliczanie kosztu szkód

Domyślnie koszt jest wyliczany według wzoru:

```text
koszt = powierzchnia nowych szkód [m²]
      × potencjalny plon [l/m²]
      × najwyższa aktualna cena sprzedaży [waluta/l]
      × PENALTY_MULTIPLIER
```

Skrypt:

1. określa nowo niszczoną powierzchnię uprawy;
2. pobiera `literPerSqm` dla danego typu rośliny;
3. wyszukuje najwyższą aktualną cenę danego produktu w dostępnych punktach sprzedaży;
4. mnoży wynik przez konfigurowalny współczynnik kary;
5. sumuje niewielkie kwoty i okresowo obciąża nimi gospodarstwo gracza.

Koszt jest widoczny w finansach jako **Szkody w uprawach NPC** / **NPC crop damage**.

### Uproszczenie modelu kosztu

`literPerSqm` oznacza bazowy potencjalny plon danego typu rośliny. Mod nie próbuje obecnie odtwarzać faktycznej wydajności konkretnego fragmentu pola wynikającej np. z nawożenia, chwastów, wapnowania, orki czy systemu Precision Farming.

Odszkodowanie jest więc szacunkową wartością potencjalnie utraconego plonu, a nie dokładną prognozą zbioru z danego miejsca.

## Tabela działania

| Sytuacja | Niszczenie upraw | Kara finansowa | Ostrzeżenie |
|---|:---:|:---:|:---:|
| Własne pole, zwykłe koła | zgodnie z grą | nie przez ten mod | nie |
| Pole NPC, zwykłe koła, podatna uprawa | tak | tak | tak |
| Pole NPC, opony pielęgnacyjne | nie | nie | nie |
| Pole NPC, pracownik AI | nie przez ten mod | nie | nie |
| Pole NPC, wyłączone „Niszczenie upraw” | nie | nie | nie |
| Pole NPC, już zniszczony fragment | brak nowych szkód | nie | nie |
| Pole NPC, ziemniaki | nie* | nie | nie |
| Pole NPC, buraki cukrowe | nie* | nie | nie |
| Pole NPC, buraki czerwone | nie* | nie | nie |

\* Mod respektuje definicje podstawowej gry. Jeżeli dany typ rośliny nie ma stanów oznaczonych jako podatne na zniszczenie przez koła, mod nie wymusza jego niszczenia.

## Konfiguracja

Najważniejsze ustawienia znajdują się na początku pliku:

```lua
scripts/NPCCropDamage.lua
```

### Wysokość odszkodowania

```lua
NPCCropDamage.PENALTY_MULTIPLIER = 1.0
```

Przykłady:

- `0.5` — 50% oszacowanej wartości szkody;
- `1.0` — 100% oszacowanej wartości szkody;
- `2.0` — 200% oszacowanej wartości szkody.

### Ponowne wyświetlenie ostrzeżenia

```lua
NPCCropDamage.WARNING_RESET_MS = 3000
```

Wartość określa, po ilu milisekundach bez nowych szkód następne niszczenie zostanie potraktowane jako nowe zdarzenie i ponownie wyświetli ostrzeżenie.

Domyślnie jest to **3000 ms**, czyli 3 sekundy.

### Diagnostyka

```lua
NPCCropDamage.DEBUG = false
```

Po zmianie na:

```lua
NPCCropDamage.DEBUG = true
```

mod zapisuje dodatkowe informacje diagnostyczne w pliku `log.txt`, m.in. obszar szkód, potencjalny plon, cenę i naliczony koszt.

## Instalacja

Skopiuj archiwum:

```text
FS25_NPCCropDamage.zip
```

do katalogu:

```text
Documents/My Games/FarmingSimulator2025/mods
```

Następnie włącz mod podczas ładowania zapisu gry.

## Zgodność

Mod jest skryptowym modem przygotowanym dla **Farming Simulator 25** i korzysta ze standardowego mechanizmu `WheelDestruction`.

Aktualna wersja została przygotowana na podstawie API skryptowego FS25 **v1.20.0.0**.

Mod jest przeznaczony do gry jednoosobowej. `modDesc.xml` ma ustawione:

```xml
<multiplayer supported="false"/>
```

## Historia zmian

### 1.1.0.0

- dodano ostrzeżenie wyświetlane przy rozpoczęciu faktycznego niszczenia uprawy na polu NPC;
- dodano tłumaczenie ostrzeżenia na język polski i angielski;
- dodano mechanizm zapobiegający wielokrotnemu wyświetlaniu komunikatu przez kolejne koła i klatki;
- dodano konfigurowalny `WARNING_RESET_MS`;
- oznaczono mod jako przeznaczony do gry jednoosobowej.

### 1.0.0.0

- pierwsza wersja;
- rozszerzono standardowe niszczenie upraw przez koła na pola NPC;
- ograniczono działanie do pojazdów kierowanych przez gracza;
- dodano naliczanie odszkodowania na podstawie powierzchni szkód, `literPerSqm` oraz najwyższej aktualnej ceny sprzedaży;
- dodano współczynnik `PENALTY_MULTIPLIER`;
- dodano wpis finansowy „Szkody w uprawach NPC” / „NPC crop damage”.
