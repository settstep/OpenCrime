# Bekannte Fehler

Offene Fehler und beobachtete Probleme. Eintragungen beschreiben den
beobachteten Effekt; die Ursache ist noch nicht in jedem Fall geklärt.

| ID | Priorität | Status | Beobachtung |
| --- | --- | --- | --- |
| BUG-001 | Hoch | Behoben (0.15.2) | Beim Wechsel in einen neuen Kartenblock verschwand der Spielfeldrand, bevor die OSM-Daten fertig geladen waren. Der Rand wird nun erst verschoben, wenn alle neun Blöcke des neuen 3 × 3-Bereichs vollständig aktiv sind. |
| BUG-002 | Mittel | Behandelt (0.18.0) | OSM-Blockdownloads können gelegentlich mit `HTTP 502` oder `HTTP 429` fehlschlagen. Anfragen laufen einzeln; `Retry-After` und ein exponentieller, auf 120 Sekunden begrenzter Wiederholungsabstand werden berücksichtigt. Bei `HTTP 429` ohne `Retry-After` gilt eine globale Pause von mindestens 60 Sekunden. |
| BUG-003 | Kritisch | Behoben (0.15.1) | Spielstände mit numerisch als Dezimalwert geparster Formatversion wurden fälschlich als ungültig erkannt. |
| BUG-004 | Niedrig | Behoben (0.16.0) | Der Kartenblock-Cache war schwer auffindbar und seine Dateinamen waren nicht geografisch lesbar. Er liegt nun unter `OpenCrimeData/map_blocks`; Dateinamen enthalten die UTM-Zone und Rasterindizes. |
| BUG-005 | Mittel | Behoben (0.18.3) | Objekte auf der Spielkarte, insbesondere Erste-Hilfe-Pakete, wurden bereits angezeigt, bevor ihr Bereich aufgedeckt war. Erste-Hilfe-, Paket- und Fahrzeugmarker sind nun erst nach dem Aufdecken des jeweiligen Kartenfelds sichtbar; Auftragsmarker bleiben unabhängig davon sichtbar. |
| BUG-006 | Mittel | Behoben (0.18.1) | Die Missionsübersicht oben rechts wurde von der Lebensenergie-Anzeige überlagert und war schwer lesbar. Beide Anzeigen sind nun getrennt. |
| BUG-007 | Hoch | Behoben (0.21.1) | Geladene Kartenblöcke wurden beim Einlesen wegen ihrer als Dezimalzahl geparsten Datenversion als ungültig abgelehnt und erneut heruntergeladen; auch die Verifikation nach manueller Aktualisierung schlug fehl. |
| BUG-008 | Mittel | Offen | Wird während des Ladens eines Kartenbereichs mit M die Karte geöffnet, ist sie teilweise vollständig schwarz. Erst „Zur Position“ zeigt den erkundeten Bereich wieder an. |
| BUG-009 | Mittel | Offen | Beim Start an einem neu gewählten Kartenpunkt wird weiterhin ein eigener gespeicherter Ort angelegt, obwohl der Startpunkt aus dem Kartenblock kommen soll. |
| BUG-010 | Hoch | Offen | Wege und Gebäude in grünen Nachbarblöcken fehlen zunächst oder erscheinen verspätet, sodass der Spieler in einem Gebäude stecken bleiben kann. |
| BUG-011 | Hoch | Behandelt (0.25.1) | Die Spielfigur blieb an Gebäudewänden und nach dem Zusammenfassen auch beim erneuten Laden des Spielstands hängen. Bei bestimmten Umlaufrichtungen waren die Kollisionsflächen falsch ausgerichtet; sie werden nun einheitlich erzeugt. |
