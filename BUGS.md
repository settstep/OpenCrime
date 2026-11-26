# Bekannte Fehler

Offene Fehler und beobachtete Probleme. Eintragungen beschreiben den
beobachteten Effekt; die Ursache ist noch nicht in jedem Fall geklärt.

| ID | Priorität | Status | Beobachtung |
| --- | --- | --- | --- |
| BUG-001 | Hoch | Behoben (0.15.2) | Beim Wechsel in einen neuen Kartenblock verschwand der Spielfeldrand, bevor die OSM-Daten fertig geladen waren. Der Rand wird nun erst verschoben, wenn alle neun Blöcke des neuen 3 × 3-Bereichs vollständig aktiv sind. |
| BUG-002 | Mittel | Behandelt (0.15.2) | OSM-Blockdownloads schlagen gelegentlich mit `HTTP 502` fehl, z. B. „OSM-Download für Kartenblock `0_-2` fehlgeschlagen (HTTP 502, Fehler 0)“. Fehlgeschlagene Blöcke werden mit exponentiellem, auf 30 Sekunden begrenztem Abstand erneut angefragt; Status und Versuche werden protokolliert. |
| BUG-003 | Kritisch | Behoben (0.15.1) | Spielstände mit numerisch als Dezimalwert geparster Formatversion wurden fälschlich als ungültig erkannt. |
| BUG-004 | Niedrig | Behoben (0.16.0) | Der Kartenblock-Cache war schwer auffindbar und seine Dateinamen waren nicht geografisch lesbar. Er liegt nun unter `OpenCrimeData/map_blocks`; Dateinamen enthalten die UTM-Zone und Rasterindizes. |
