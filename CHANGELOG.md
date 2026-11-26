# Änderungen

## 0.18.1
- Die Missionsübersicht und der Hinweis darunter überlagern die Lebensenergie-Anzeige nicht mehr.

## 0.18.0
- OSM-Blockdownloads werden einzeln und mit mindestens einer Sekunde Abstand gestartet.
- Bei HTTP 429/503 werden Anfragen global pausiert; `Retry-After` wird als Sekundenangabe oder HTTP-Datum berücksichtigt.
- Fehlgeschlagene Downloads werden mit exponentiellem Abstand bis maximal 120 Sekunden erneut versucht; bei HTTP 429 ohne `Retry-After` gilt eine Pause von mindestens 60 Sekunden.

## 0.17.0
- Neue Orte laden und speichern vor Spielstart den vollständigen 1.000 × 1.000-Meter-UTM-Block.
- Bereits gecachte UTM-Blöcke können direkt zur Ortsauswahl verwendet werden; die übrigen Nachbarblöcke werden nach Spielstart gestreamt.

## 0.16.0
- Kartenblöcke sind jetzt 1.000 × 1.000 Meter groß und verwenden UTM-basierte, ortsunabhängige Block-IDs.
- OSM-Blöcke, Spielstände, gespeicherte Orte, Kartenkacheln, Einstellungen und Logs liegen im portablen Ordner `OpenCrimeData`.
- Bisherige Spielstände, Orte, Kartenkacheln, Erste-Hilfe-Einstellungen und Logs werden beim Start in den neuen Ordner kopiert; die alten Dateien bleiben als Sicherung erhalten.

## 0.15.2
- Der Spielfeldrand wird erst verschoben, wenn der neue 3 × 3-Kartenbereich vollständig geladen ist.
- Fehlgeschlagene OSM-Downloads werden mit exponentiellem Abstand bis maximal 30 Sekunden erneut versucht.
- Ein rotierendes Spielprotokoll erfasst Sitzungsstarts, Kartenblock-Ladevorgänge, Wiederholungen und Speicherfehler.

## 0.15.1
- Behoben: Spielstände mit numerisch als Dezimalwert geparster Formatversion wurden fälschlich als ungültig erkannt.

## 0.15.0
- Die Spielwelt streamt OSM-Daten in feste 500 × 500-Meter-Blöcke und hält für jeden Spieler ein 3 × 3-Fenster aktiv.
- Neu benötigte Blöcke werden über Overpass geladen, lokal zwischengespeichert und nach Verlassen des aktiven Bereichs aus dem Speicher entfernt.
- Im Multiplayer lädt der Server neue Blöcke und synchronisiert sie mit Clients; Clients speichern die empfangenen Daten lokal.
- Die Spielkarte und der gespeicherte Erkundungsfortschritt funktionieren auch außerhalb des ursprünglichen Kartenausschnitts.

## 0.14.0
- Unsichtbare Kollisionsbegrenzungen halten Spielfigur und Fahrzeuge im Kartenbereich.
- Das Pausemenü kann Spielfigur oder gefahrenes Fahrzeug sicher auf der Karte zurücksetzen.

## 0.13.0
- Inventar für bis zu fünf Erste-Hilfe-Pakete; ein Paket kann in der Welt aufgenommen und mit H benutzt werden.
- Pakete heilen bis zu 50 Lebenspunkte, werden im Einzelspieler gespeichert und im Multiplayer serverautoritativ synchronisiert.

## 0.12.0
- Mehrere Testfahrzeuge können unabhängig benutzt und im Multiplayer gleichzeitig gefahren werden.
- Die Spielkarte markiert Fahrzeuge; Einzelspieler-Spielstände speichern alle Fahrzeugpositionen und das belegte Auto.

## 0.11.0
- Markierte Erste-Hilfe-Teststation mit einstellbarem Preis und Heilwert.
- Behandlungen verwenden das persönliche Auftragsgeld und werden im Multiplayer vom Server verwaltet.

## 0.10.0
- Lebensenergie und Schaden bei starken Fahrzeugkollisionen.
- Bei null Lebensenergie Wiederbelebung am Startpunkt mit 25 %; im Einzelspieler wird die Lebensenergie gespeichert.

## 0.9.0
- SMS-Aufträge mit einmaligem Einstieg und wiederkehrenden Paketlieferungen.
- Aufträge können angenommen, zurückgestellt und im Multiplayer weitergeleitet werden.
- Gemeinsame Aufträge teilen die Belohnung; Einzelspieler-Spielstände speichern Fortschritt und Geld.

## 0.8.0
- Die Kamera zoomt beim schnelleren Fahren sanft heraus und beim Anhalten wieder hinein.
- Das Testauto fährt schneller.

## 0.7.0
- Die Spielkarte lässt sich mit dem Mausrad zoomen und mit der linken Maustaste verschieben.
- Eine Schaltfläche zentriert die Kartenansicht auf die eigene Position.

## 0.6.0
- Abgerundete Verbindungen schließen Lücken zwischen Straßen- und Wegstücken.
- Straßen werden vor überlappenden Gehwegen dargestellt, auch auf der Spielkarte.

## 0.5.1
- Der Ladebildschirm funktioniert auch, wenn noch keine Spielstände vorhanden sind.

## 0.5.0
- Mehrere Einzelspieler-Spielstände mit automatischem und manuellem Speichern.
- Ort, Figur, Auto und erkundete Kartenbereiche werden wiederhergestellt.
- Spielstände können im Hauptmenü geladen und nach Bestätigung gelöscht werden.

## 0.4.0
- Spielkarte mit eigener Position und Erkundungsnebel, erreichbar über M.
- Erkundung gilt je Spieler während der aktuellen Sitzung und benötigt keine Kartendownloads.

## 0.3.0
- Straßenbreiten und Gebäudehöhen werden nach Möglichkeit aus OSM-Tags übernommen.
- Separat erfasste Gehwege und oberirdische Parkplatzflächen werden dargestellt.
- Der mitgelieferte Thalhofen-Ausschnitt enthält zusätzliche OSM-Merkmale.

## 0.2.0
- Ortsauswahl auf einer OpenStreetMap-Karte und Liste gespeicherter Orte.
- Neue Kartenausschnitte werden heruntergeladen und lokal gespeichert.
- Multiplayer-Clients erhalten denselben Kartenausschnitt vom Server.
- Dieses Änderungsprotokoll ist im Hauptmenü verfügbar.

## 0.1.0
- Erster spielbarer Prototyp mit Bewegung, Auto und Gebäudekollisionen.
- Multiplayer-Grundlagen und eigenständiger Server.
- OSM-Testausschnitte für Thalhofen und Berlin, Kartenfaktor und Pausenmenü.
