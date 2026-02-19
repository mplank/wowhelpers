# wowhelpers

Kleine Helfer für World of Warcraft (Retail): Mail-Verschieben, Verkaufen & Zerstören, Questlog leeren.

## Installation

Addon-Ordner `wowhelpers` in den Pfad  
`World of Warcraft\_retail_\Interface\AddOns\` legen und im Spiel Addons aktivieren.

## Slash-Befehle

| Befehl | Beschreibung |
|--------|--------------|
| `/wh` | Zeigt die Befehlsübersicht |
| `/wh trashlog` | Alle Quests abbrechen (mit Bestätigung), läuft automatisch bis das Log leer ist |
| `/wh sell` | Alles Verkaufbare am Händler verkaufen (Verkaufsfenster muss offen sein) |
| `/wh destroy` | Nicht verkaufbare / graue Gegenstände zerstören (Frame mit Löschen / Nicht löschen / Abbrechen) |
| `/wh emptybags` | Erst verkaufen, dann Zerstören-Frame für den Rest |
| `/wh mailcharpurge <Name>` | Charakter aus der Mail-Zielliste entfernen |

## Funktionen

### Mail (Verschieben)

- Items per Mail an anderen Charakter verschieben.
- Nur versendbare Items (kein BoP/Seelengebunden, keine Event-Items außer aktivem Event).
- Reagenzientasche wird mit einbezogen.
- Blacklist für Chars, Paketversand (12 Items pro Mail), Fortschrittsanzeige.

### Verkaufen & Zerstören

- **Verkaufen:** Am Händler alles verkaufen, was einen Händlerpreis hat (`hasNoValue`-Logik wie Baganator).
- **Zerstören:** Nicht verkaufbare Items (z. B. Quest-Müll) nacheinander zerstören:
  - Frame mit **Löschen** (Enter bestätigt), **Nicht löschen** (überspringen), **Abbrechen**.
  - Legendary/Artifact werden ausgelassen (nicht zerstörbar).
- Button „Verkaufen & Löschen“ am Händlerfenster: erst verkaufen, dann Zerstören-Frame.

### Questlog leeren

- Button „Questlog leeren“ unter dem Questlog-/Kartenfenster.
- Er erscheint nur, wenn Quests im Log sind und das Fenster nicht „Keine Quests verfügbar“ anzeigt.
- Ein Klick startet den Abbruch aller Quests (mit Verzögerung und automatischem Nachlauf bis leer).

## Abhängigkeiten

- WoW Retail (Interface 120000+).
- Enthaltene Libs: LibStub, AceAddon-3.0, CallbackHandler, weitere in `Libs/`.

## Lizenz

Siehe Projektstruktur; eingebundene Bibliotheken haben eigene Lizenzen.
