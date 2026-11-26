# Bekannte Fehler

Offene Fehler und beobachtete Probleme. Eintragungen beschreiben den
beobachteten Effekt; die Ursache ist noch nicht in jedem Fall geklärt.

| ID | Priorität | Status | Beobachtung |
| --- | --- | --- | --- |
| BUG-001 | Hoch | Behoben (0.15.2) | Beim Wechsel in einen neuen Kartenblock verschwand der Spielfeldrand, bevor die OSM-Daten fertig geladen waren. Der Rand wird nun erst verschoben, wenn alle neun Blöcke des neuen 3 × 3-Bereichs vollständig aktiv sind. |
| BUG-002 | Mittel | Behandelt (0.18.0) | OSM-Blockdownloads können gelegentlich mit `HTTP 502` oder `HTTP 429` fehlschlagen. Anfragen laufen einzeln; `Retry-After` und ein exponentieller, auf 120 Sekunden begrenzter Wiederholungsabstand werden berücksichtigt. Bei `HTTP 429` ohne `Retry-After` gilt eine globale Pause von mindestens 60 Sekunden. |
| BUG-003 | Kritisch | Behoben (0.15.1) | Spielstände mit numerisch als Dezimalwert geparster Formatversion wurden fälschlich als ungültig erkannt. |
| BUG-004 | Niedrig | Behoben (0.16.0) | Der Kartenblock-Cache war schwer auffindbar und seine Dateinamen waren nicht geografisch lesbar. Er liegt nun unter `OpenCrimeData/map_blocks`; Dateinamen enthalten die UTM-Zone und Rasterindizes. |
| BUG-005 | Mittel | Behoben (0.18.2) | Objekte auf der Spielkarte, insbesondere Erste-Hilfe-Pakete, wurden bereits angezeigt, bevor ihr Bereich aufgedeckt war. Objektmarker sind nun erst nach dem Aufdecken des jeweiligen Kartenfelds sichtbar. |
| BUG-006 | Mittel | Offen | Der Text oben rechts wird von einem anderen Element überlagert und ist dadurch schwer lesbar; betroffen sind unter anderem „Geld 0 $“ und das abschließende „: J“. |
