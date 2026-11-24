# OpenCrime

OpenCrime ist der Arbeitstitel für ein Open-World-Spiel aus der Vogelperspektive.
Langfristig sind unter anderem Fahrzeuge, Aufträge, Multiplayer und eine Spielwelt
auf Basis realer Kartendaten geplant.

## Aktueller Prototyp

Der erste Prototyp enthält eine kleine 3D-Testfläche, Gebäude mit Kollisionen,
eine Spielfigur und ein einfaches Auto. Mit **WASD** bewegt sich die Figur oder
fährt das Auto in die jeweilige Richtung. In der Nähe des Autos steigt man mit
**E** ein und später wieder aus. Die Fahrphysik ist vorerst bewusst einfach.

Mit **Escape** öffnet sich das Menü; mit Escape oder **Spiel fortsetzen**
kehrt man zurück. Im Einzelspieler pausiert das Spiel, im Multiplayer läuft
der Server weiter und nur die eigene Steuerung wird gesperrt. **Zum Hauptmenü**
verlässt das laufende Spiel; beim Host werden dabei die Clients getrennt.
Mit **Spiel beenden** wird das Programm geschlossen.

Der Multiplayer-Prototyp synchronisiert Spieler und das gemeinsame Auto über
einen Server. Der Server berechnet Bewegung und Kollisionen; das Auto kann nur
von einem Spieler gleichzeitig gefahren werden.

## Kartenausschnitt

Bei **Einzelspieler** und **Spiel hosten** erscheint eine Ortsauswahl. Ziehen
und zoomen Sie die OpenStreetMap-Karte und klicken Sie auf einen Ort, oder
wählen Sie einen gespeicherten Ausschnitt aus der Liste. Für einen neuen Ort
geben Sie einen Namen ein und wählen **Ort laden und starten**. Dafür werden
Straßen und Gebäude in einem Gebiet von etwa 330 × 330 Metern über die Overpass
API geladen. Ein geeigneter Startpunkt muss nahe einer Straße liegen; wird
keiner gefunden, wählen Sie bitte einen anderen Punkt.

Mitgeliefert werden Ausschnitte rund um die Waldmünchener Straße in Thalhofen
bei Marktoberdorf und den Gendarmenmarkt in Berlin. Gespeicherte Orte werden
ohne erneuten Download der OSM-Rohdaten gestartet; auch ein Klick innerhalb
eines gespeicherten Ausschnitts wählt diesen aus. Neue Orte liegen unter
`user://places`, unter Windows üblicherweise
`%APPDATA%\Godot\app_userdata\OpenCrime\places`. Die Kartenansicht lädt sichtbare
Kartenkacheln über das Internet und speichert sie zwischengespeichert unter
`user://tile_cache`. Die Liste gespeicherter Orte funktioniert auch offline.
Eine Textsuche ist noch nicht vorhanden.
Ein späterer Bearbeitungsmodus mit lokalen Änderungen anhand von OSM-IDs ist
geplant, aber noch nicht implementiert.

Straßen und Gebäude werden aus gespeicherten
OpenStreetMap-Wegen erzeugt; die Gebäude haben Kollisionen. Der Ausschnitt
ist bewusst unvollständig: Flächen, Relationen und Gebäudedetails werden noch
nicht ausgewertet, Straßenbreiten sind geschätzt und Gebäude pauschal 10 Meter
hoch. Das Gelände ist eben; echte Höhendaten fehlen noch.

Der mitgelieferte Thalhofen-Bereich umfasst 47.7735–47.7765° Nord und
10.6013–10.6057° Ost (ungefähr 330 × 330 Meter). Wege können über diesen
Bereich hinausragen. Bei Faktor 1,0 entspricht eine Godot-Einheit ungefähr
einem Meter; die Spielfigur ist 1,8 Meter hoch. Die Daten werden offline aus
`data/thalhofen.json` erzeugt. Die Daten stammen aus der
[Overpass API](https://overpass-api.de/), abgerufen am 24. November 2026;
der OSM-Datenstand ist im Datensatz vermerkt. Gespeichert sind die Geometrien
und ausgewählte Tags der Gebäude- und Straßenwege; die übrigen Daten wurden
weggelassen. Der ältere Berliner Testdatensatz bleibt ebenfalls im Repository.

### Kartenfaktor testen

In `project.godot` steht unter `[opencrime]` der Parameter `osm/scale=1.0`.
Er kann beispielsweise auf `1.2` gesetzt werden, um Abstände, Gebäudegrößen und
die geschätzten Straßenbreiten um 20 % zu vergrößern. Der Wert muss eine
endliche Zahl größer als 0 sein. Nach einer Änderung das Spiel neu starten;
bei geöffnetem Godot-Editor die Projektdatei gegebenenfalls neu laden.

Der Faktor skaliert auch die geschätzte Gebäudehöhe und den Boden; Figur und
Auto bleiben unverändert. Parkplätze und zusätzliche Gehwege werden dadurch
nicht ergänzt. Bei `1.0` entspricht eine Godot-Einheit ungefähr einem Meter.
Im Multiplayer müssen Server und Clients denselben Faktor verwenden; bei
unterschiedlichen Werten wird die Verbindung mit einer Meldung getrennt.

Kartendaten: © [OpenStreetMap-Mitwirkende](https://www.openstreetmap.org/copyright),
verfügbar unter der [Open Database License (ODbL)](https://opendatacommons.org/licenses/odbl/1-0/).
Die OSM-Daten unterliegen dieser Lizenz und nicht der MIT-Lizenz des Projektcodes.

## Projekt öffnen

1. [Godot 4.7.2 Standard](https://godotengine.org/download/archive/4.7.2-stable/)
   für Windows herunterladen und entpacken.
2. Die normale Godot-Programmdatei starten.
3. Im Projektmanager **Importieren** wählen und die Datei `project.godot` in
   diesem Repository auswählen.
4. Das Projekt öffnen und mit **F5** starten. Beenden lässt sich das Spiel mit
   **F8**.

Die Projektdateien und Skripte können auch in VS Code bearbeitet werden. Godot
wird weiterhin benötigt, um das Spiel auszuführen und Szenen zu bearbeiten.

## Versionierung

Die aktuelle Spielversion steht als `config/version` im Abschnitt
`[application]` der `project.godot` und wird im Hauptmenü angezeigt.
Ausgangspunkt ist **0.1.0**. Bei einer neuen Version wird dieser Wert manuell
angepasst; er folgt dem Schema `MAJOR.MINOR.PATCH`, zum Beispiel `0.2.0` für
eine neue Funktion oder `0.1.1` für eine Fehlerkorrektur. Die Versionsnummer
allein prüft noch nicht die Multiplayer-Kompatibilität.
Das Änderungsprotokoll ist über **Änderungsprotokoll** im Hauptmenü und in
`CHANGELOG.md` verfügbar.

## Windows-EXE exportieren

Godot erzeugt die EXE nicht automatisch beim Spielen mit F5. Für einen Export:

1. In Godot **Editor → Exportvorlagen verwalten** öffnen und die zu Godot 4.7.2
   passenden Standard-Exportvorlagen installieren.
2. **Projekt → Exportieren** öffnen. Das vorhandene Exportprofil
   **Windows Desktop** auswählen und **Projekt exportieren** wählen.
3. Die erzeugte `.exe` **und** die gleichnamige `.pck`-Datei zusammen auf den
   anderen Windows-64-Bit-Rechner kopieren. Die PCK enthält die Spieldaten,
   darunter den Kartenausschnitt. Dort ist Godot nicht erforderlich.

Alternativ können auf dem anderen Rechner Godot 4.7.2 und dieselben
Projektdateien verwendet werden. Für den Multiplayer müssen beide Rechner
dieselbe Projektversion verwenden; Netzwerkadresse und Firewall siehe unten.

## Multiplayer ausprobieren

1. Das Spiel starten, **Spiel hosten** wählen und einen Ort auswählen. Der Host
   spielt selbst mit.
2. Eine zweite Spielinstanz starten, die Serveradresse und denselben UDP-Port
   eingeben und **Spiel beitreten** wählen. Zum Testen auf demselben Rechner
   ist die voreingestellte Adresse `127.0.0.1` richtig.
3. Für andere Rechner im lokalen Netzwerk die lokale IP-Adresse des Hosts
   verwenden. Im Internet ist die öffentliche Adresse oder der Hostname des
   Servers erforderlich; je nach Netzwerk müssen UDP-Portfreigabe und Firewall
   passend eingerichtet werden.

Der Standardport ist **7777/UDP**. Ein Host kann bis zu acht weitere Spieler
aufnehmen. Bei Verbindungsverlust muss das Spiel derzeit neu gestartet werden.
Alle Beteiligten benötigen dieselbe Projektversion.
Der Server überträgt den ausgewählten Kartenausschnitt an die Clients; diese
benötigen dafür weder einen eigenen OSM-Download noch denselben gespeicherten
Ort.

Für einen zweiten lokalen Spielstart kann man beispielsweise ein neues
PowerShell-Terminal öffnen und den folgenden Befehl ausführen (Pfade anpassen):

```powershell
& "C:\Pfad\zu\Godot_v4.7.2-stable_win64.exe" --path "C:\GIT\OpenCrime"
```

### Eigenständiger Server

Ein Server ohne eigenen Spieler lässt sich aus PowerShell starten. Den Pfad
zur Godot-Konsolenprogrammdatei und zum Projektordner entsprechend anpassen:

```powershell
& "C:\Pfad\zu\Godot_v4.7.2-stable_win64_console.exe" --headless --path "C:\GIT\OpenCrime" -- --server --port=7777
```

Der Port ist optional und standardmäßig 7777. Ohne weitere Angabe wird
Thalhofen geladen. Mit `--place=gendarmenmarkt` lässt sich stattdessen Berlin
wählen; für andere gespeicherte Orte kann die ID aus dem Dateinamen ohne
`.json` verwendet werden, z. B. `--place=place_0123456789abcdef`. Diese Orte
müssen auf dem Server in dessen `user://places` vorhanden sein. Ein unbekannter
Ort wird als Fehler gemeldet. Zum Beenden **Strg+C** drücken.
Auch auf einem entfernten Rechner funktioniert der Server mit einer passenden
Godot-Version und denselben Projektdateien.

**Wichtig:** Dies ist ein früher Prototyp ohne Anmeldung, Verschlüsselung oder
Spielstandspeicherung. Nur in vertrauenswürdigen Netzwerken verwenden und nicht
ungeschützt im Internet bereitstellen.

## Tests ausführen

Im PowerShell-Terminal im Projektordner kann der Fahrzeugtest mit der
Godot-Konsolenprogrammdatei gestartet werden (den Pfad entsprechend anpassen):

```powershell
& "C:\Pfad\zu\Godot_v4.7.2-stable_win64_console.exe" --headless --path . --script res://tests/car_test.gd
& "C:\Pfad\zu\Godot_v4.7.2-stable_win64_console.exe" --headless --path . --script res://tests/menu_test.gd
& "C:\Pfad\zu\Godot_v4.7.2-stable_win64_console.exe" --headless --path . --script res://tests/pause_menu_test.gd
& "C:\Pfad\zu\Godot_v4.7.2-stable_win64_console.exe" --headless --path . --script res://tests/osm_map_test.gd
& "C:\Pfad\zu\Godot_v4.7.2-stable_win64_console.exe" --headless --path . --script res://tests/osm_scale_test.gd
& "C:\Pfad\zu\Godot_v4.7.2-stable_win64_console.exe" --headless --path . --script res://tests/place_test.gd
& "C:\Pfad\zu\Godot_v4.7.2-stable_win64_console.exe" --headless --path . --script res://tests/place_download_test.gd
& "C:\Pfad\zu\Godot_v4.7.2-stable_win64_console.exe" --headless --path . --script res://tests/map_cache_test.gd
& "C:\Pfad\zu\Godot_v4.7.2-stable_win64_console.exe" --headless --path . --script res://tests/connection_failure_test.gd
```

Für den Netzwerktest drei Terminals im Projektordner öffnen und nacheinander
die folgenden Befehle starten. Der Test verwendet UDP-Port 17777 und beendet
alle drei Instanzen selbstständig:

```powershell
& "C:\Pfad\zu\Godot_v4.7.2-stable_win64_console.exe" --headless --path . --script res://tests/network_test.gd -- --role=host
```
```powershell
& "C:\Pfad\zu\Godot_v4.7.2-stable_win64_console.exe" --headless --path . --script res://tests/network_test.gd -- --role=driver
```
```powershell
& "C:\Pfad\zu\Godot_v4.7.2-stable_win64_console.exe" --headless --path . --script res://tests/network_test.gd -- --role=observer
```
