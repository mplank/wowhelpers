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

**Empfänger / Zielliste:**  
Im Mail-Fenster (Reiter „Verschieben“) wählst du den Empfänger aus einem **Dropdown**. Die Liste enthält nur Charaktere vom **gleichen Realm und gleicher Fraktion**, an die du mit diesem Addon oder normal per „Post versenden“ schon einmal erfolgreich eine Mail geschickt hast. Es werden keine Namen manuell eingegeben – wer in der Liste erscheinen soll, muss mindestens einmal als Empfänger einer erfolgreich versendeten Mail vorkommen (danach speichert das Addon ihn in der Zielliste). Beim ersten Mal: einmal „normal“ eine Mail an deinen Alt schicken (Namen im Spiel-Empfängerfeld eintippen und absenden), danach steht der Char im Dropdown für „Verschieben“. Der zuletzt gewählte Empfänger wird pro Charakter gemerkt. Einträge entfernst du mit `/wh mailcharpurge <Name>`.

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

Dieses Addon steht unter der **MIT-Lizenz** (siehe [LICENSE](LICENSE)). Die eingebundenen Bibliotheken in `Libs/` haben ggf. eigene Lizenzen.

**Haftungsausschluss:** Das Addon wird „wie besehen“ bereitgestellt, ohne Gewähr. Nutzung erfolgt auf eigene Verantwortung. Die Autoren haften nicht für direkte oder indirekte Schäden (z. B. verlorene Items, Account-Probleme), die durch die Nutzung entstehen. Bei Aktionen wie Quest-Abbruch, Verkauf oder Zerstörung von Gegenständen gilt: Der Nutzer handelt auf eigenes Risiko.
