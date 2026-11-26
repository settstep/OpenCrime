# Bekannte Fehler

Offene Fehler und beobachtete Probleme. Eintragungen beschreiben den
beobachteten Effekt; die Ursache ist noch nicht in jedem Fall geklärt.

| ID | Priorität | Status | Beobachtung |
| --- | --- | --- | --- |
| BUG-001 | Hoch | Offen | Beim Wechsel in einen neuen Kartenblock verschwindet der Spielfeldrand, bevor die OSM-Daten fertig geladen sind. Straßen und Gebäude erscheinen dadurch verspätet; bis die benötigten Blöcke aktiv sind, soll der Rand den Spieler im bereits geladenen Bereich halten. |
| BUG-002 | Mittel | Offen | OSM-Blockdownloads schlagen gelegentlich mit `HTTP 502` fehl, z. B. „OSM-Download für Kartenblock `0_-2` fehlgeschlagen (HTTP 502, Fehler 0)“. Der Block bleibt dann zunächst ohne heruntergeladene Elemente; Wiederholungsversuche und der sichtbare Status müssen geprüft werden. |
| BUG-003 | Kritisch | Offen | Jeder Spielstand wird beim Laden als ungültig abgewiesen („Ungültiger Spielstand …, Fehler 30“), auch Spielstände, die mit der aktuellen Version gespeichert wurden. Die Ursache ist noch nicht eingegrenzt. |
| BUG-004 | Niedrig | Offen | Der Kartenblock-Cache ist schwer auffindbar und seine Dateinamen sind nicht geografisch lesbar. Auf Windows liegt `user://map_blocks` üblicherweise unter `%APPDATA%\Godot\app_userdata\OpenCrime\map_blocks`; aktuell enthalten die Namen einen Orts-Hash und Blockindizes statt Koordinaten. Lesbare geografische Koordinaten in den Cache-Dateinamen wären leichter zuzuordnen. |
