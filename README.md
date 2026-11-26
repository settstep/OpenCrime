# OpenCrime

OpenCrime ist der Arbeitstitel für ein Open-World-Spiel aus der Vogelperspektive.
Langfristig sind unter anderem Fahrzeuge, Aufträge, Multiplayer und eine Spielwelt
auf Basis realer Kartendaten geplant.

## Aktueller Prototyp

Der Prototyp enthält Gebäude mit Kollisionen, eine Spielfigur und mehrere
einfache Testautos. Mit **WASD** bewegt sich die Figur oder fährt das Auto in
die jeweilige Richtung. Mit **E** steigt man in das nächstgelegene Auto ein
und später wieder aus. Die Fahrphysik ist vorerst bewusst einfach.
Beim schnelleren Fahren zeigt die Kamera sanft einen größeren Ausschnitt; beim
Anhalten oder Aussteigen kehrt sie zur normalen Ansicht zurück. Zu Fuß bleibt
die bisherige Ansicht erhalten.

Die Lebensenergie steht oben rechts. Starke Fahrzeugkollisionen verletzen den
Fahrer; langsame Kontakte und dauerhaftes Drücken gegen ein Hindernis verursachen
keinen weiteren Schaden. Bei null Lebensenergie wird die Figur mit 25 %
Lebensenergie am Startpunkt wiederbelebt. Ist dieser belegt, wird ein freier
Platz in der Nähe gesucht; ist keiner verfügbar, wartet die Figur, bis ein Platz
frei wird. Das Auto bleibt am Unfallort und aktive Aufträge bleiben erhalten.
Im Einzelspieler wird die Lebensenergie gespeichert; alte Spielstände starten
mit voller Lebensenergie. Im Multiplayer berechnet der Server den Schaden und
die Wiederbelebung; die Lebensenergie gilt wie die übrigen Fortschrittsdaten
nur für die laufende Sitzung.

Eine grüne Kreuzmarkierung in der Welt und auf der Karte zeigt die
Erste-Hilfe-Teststation. In ihrer Nähe **zu Fuß F drücken**, um Lebensenergie
gegen eigenes Geld aufzufüllen. Standardmäßig kostet die Behandlung 25 $ und
heilt bis zu 50 Lebenspunkte, höchstens bis zum Maximum von 100. Bei voller
Lebensenergie oder unzureichendem Geld wird nichts berechnet. Das Auto wird
weiterhin unabhängig davon mit **E** bedient.

Die Teststation ist kein echter OSM-Ort; sie wird automatisch auf einem
geeigneten Weg nahe dem Start platziert. Preis und Heilwert stehen in
`user://first_aid.json`, unter Windows üblicherweise
`%APPDATA%\Godot\app_userdata\OpenCrime\first_aid.json`. Die Datei wird beim
ersten Start aus `data/first_aid.json` angelegt und lässt sich danach mit einem
Texteditor ändern. `price` muss eine ganze Zahl zwischen 1 und 1.000.000.000
sein, `healing` eine ganze Zahl zwischen 1 und 100. Änderungen gelten beim
nächsten Spielstart; im Multiplayer gelten die Einstellungen des Servers.
Ungültige Einstellungen oder ein fehlender geeigneter Ort werden angezeigt
und deaktivieren nur die Teststation. Geld und Gesundheit werden wie bisher
im Einzelspieler-Spielstand gespeichert; im Multiplayer nur für die Sitzung.

Ein gelbes Paket mit weißem Kreuz kann zu Fuß in der Nähe automatisch
aufgenommen werden. Das Inventar fasst höchstens fünf Pakete; mit **H** wird
eines benutzt und heilt bis zu 50 Lebenspunkte, höchstens bis zur vollen
Lebensenergie. Während man fährt, bei voller Lebensenergie oder während einer
Wiederbelebung wird kein Paket verbraucht. Im Einzelspieler werden Inventar und
Zustand des Welt-Pakets gespeichert; im Multiplayer prüft und verwaltet der
Server Aufheben, Benutzung und Synchronisierung.

Mit **Escape** öffnet sich das Menü; mit Escape oder **Spiel fortsetzen**
kehrt man zurück. Im Einzelspieler pausiert das Spiel, im Multiplayer läuft
der Server weiter und nur die eigene Steuerung wird gesperrt. **Zum Hauptmenü**
verlässt das laufende Spiel; beim Host werden dabei die Clients getrennt.
Mit **Auf die Karte zurücksetzen** wird die Spielfigur oder das gerade
gefahrene Fahrzeug an einen sicheren Startpunkt innerhalb der Karte versetzt.
Unsichtbare Kollisionsgrenzen verhindern, dass Spielfigur oder Fahrzeuge den
geladenen Kartenausschnitt verlassen. Mit **Spiel beenden** wird das Programm
geschlossen.

Pro Ort werden bis zu drei Testautos platziert; wenn nicht genügend geeignete
Stellen gefunden werden, erscheint ein Hinweis. Auf der Spielkarte sind die
Autos orange markiert. Im Multiplayer synchronisiert der Server alle Autos,
berechnet Bewegung und Kollisionen und lässt pro Auto nur einen Fahrer zu.
Mehrere Spieler können verschiedene Autos gleichzeitig fahren.

## SMS-Aufträge

Mit **J** öffnet man SMS und Aufträge. Eine SMS kann angenommen oder für später
zurückgestellt werden. Nach einem einmaligen Einführungsauftrag folgen
wiederkehrende Lieferungen; zurückgestellte Angebote bleiben auswählbar.
Gelbe Markierungen zeigen das aktuelle Ziel in der Welt und auf der Spielkarte.
Das Paket wird **zu Fuß** bei Annäherung automatisch aufgenommen und am Ziel
abgegeben. Der Bildschirm zeigt den Fortschritt und das verdiente Geld.

Im Multiplayer kann ein aktiver Auftrag an einen Mitspieler weitergeleitet
werden. Nimmt dieser die Einladung an, teilen sich die Teilnehmer Fortschritt
und Belohnung; eine Person kann abholen oder abgeben. Der Server verwaltet die
Aufträge. Ein verbleibender Dollar bei einer ungeraden Aufteilung geht an den
Teilnehmer mit der kleinsten Spieler-ID. Getrennte Spieler nehmen nicht mehr an der Belohnung teil. Geld und
Auftragsfortschritt werden im Einzelspieler-Spielstand gespeichert; Multiplayer
bleibt sitzungsbezogen. Ältere Spielstände erhalten beim Laden ihren ersten
Auftrag. Die Definitionen liegen in `data/missions.json`; Orte werden anhand der
geladenen OSM-Wege gewählt. Falls keine geeigneten Ziele gefunden werden, wird
dies angezeigt und das übrige Spiel bleibt nutzbar.
Die SMS nennt für beide Ziele den OSM-Wegnamen und den ungefähren Abstand vom
Ursprung des Kartenausschnitts; das jeweils aktuelle Ziel ist markiert.
Einladungen können nur angenommen werden, solange der gemeinsame Auftrag läuft.
Jede Definition benötigt eine eindeutige `id`, den `type` (`story` oder
`recurring`), `title`, `sms` und eine positive ganzzahlige `reward`. Aktuell
verwenden alle Definitionen denselben Ablauf: Paket abholen und abgeben.
IDs abgeschlossener Hauptaufträge bleiben im Spielstand gespeichert und sollten
deshalb nicht nachträglich geändert werden.

Mit **M** öffnet und schließt man die Spielkarte; **Escape** oder
**Schließen** schließt sie ebenfalls. Die eigene Position ist blau markiert.
Um die Figur beziehungsweise das gefahrene Auto wird die Umgebung nach und
nach aufgedeckt; dunkle Bereiche sind noch nicht erkundet. Die Karte wird
aus den bereits geladenen Kartendaten gezeichnet. Bereits gecachte Bereiche
funktionieren offline; nur für noch fehlende Kartenblöcke ist eine
Internetverbindung nötig.
Mit dem **Mausrad** zoomt man auf die Mausposition; mit gedrückter **linker
Maustaste** verschiebt man die Ansicht. **Zur Position** zentriert sie wieder
auf die eigene Figur beziehungsweise das gefahrene Auto, ohne den Zoom zu ändern.
Die Ansicht bleibt beim Schließen und erneuten Öffnen der Karte erhalten.

Im Einzelspieler pausiert das Spiel, während die Karte geöffnet ist. Im
Multiplayer läuft der Server weiter und die eigene Steuerung ist gesperrt.
Jeder Spieler erkundet seine Karte selbst. Im Einzelspieler wird der
Erkundungsfortschritt im Spielstand gespeichert; im Multiplayer gilt er
vorerst nur für die aktuelle Sitzung.

## Einzelspieler-Spielstände

Jedes neue Einzelspiel erhält einen eigenen Spielstand. Er wird beim Start,
alle 30 Sekunden während des Spiels sowie beim regulären Beenden oder beim
Zurückkehren zum Hauptmenü automatisch gespeichert. Im Pausenmenü steht
zusätzlich **Spiel speichern** zur Verfügung. Beim unerwarteten Abbruch kann
Fortschritt seit der letzten Speicherung verloren gehen. Mit **Als neuen
Spielstand speichern** entsteht eine unabhängige Kopie; anschließend wird
diese Kopie automatisch weitergespeichert.

Über **Spielstand laden** im Hauptmenü können Spielstände ausgewählt, geladen
und nach einer Bestätigung gelöscht werden. Gespeichert werden der Ort samt
seinen konkreten Kartendaten, der Kartenfaktor, die Positionen von Figur und
Autos, ihre Ausrichtung, das belegte Auto sowie die erkundeten Bereiche.
Alte Spielstände mit nur einem Auto bleiben ladbar und erhalten, soweit
geeignete Plätze verfügbar sind, zusätzliche Testautos. Ältere Spielstände
mit der bisherigen Erkundungskarte werden beim Laden automatisch migriert.
Der eingebettete Startausschnitt kann ohne Ortsauswahl geladen werden; noch
nicht gecachte Nachbarblöcke werden danach im Hintergrund heruntergeladen.
Der eingestellte Kartenfaktor muss dem
gespeicherten Wert entsprechen; bei einem Unterschied wird das Laden mit
einer Meldung abgebrochen.

Die Dateien liegen unter `user://saves`, unter Windows üblicherweise
`%APPDATA%\Godot\app_userdata\OpenCrime\saves`. Bei einem Speicherfehler wird
eine Meldung angezeigt; das reguläre Verlassen des Einzelspiels wird dann
verhindert, damit der Fehler behoben werden kann. Derselbe Spielstand sollte
nicht gleichzeitig in mehreren Spielinstanzen geöffnet werden, da sonst die
letzte Speicherung gewinnt. Multiplayer-Spielstände sind noch nicht vorhanden.

## Kartenausschnitt

Bei **Einzelspieler** und **Spiel hosten** erscheint eine Ortsauswahl. Ziehen
und zoomen Sie die OpenStreetMap-Karte und klicken Sie auf einen Ort, oder
wählen Sie einen gespeicherten Ausschnitt aus der Liste. Für einen neuen Ort
geben Sie einen Namen ein und wählen **Ort laden und starten**. Dafür werden
Straßen, Gebäude und Parkplatzflächen in einem Gebiet von etwa 330 × 330 Metern
über die Overpass API geladen. Ein geeigneter Startpunkt muss nahe einer Straße liegen; wird
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

Straßen, Gebäude und separat erfasste Gehwege sowie geschlossene,
oberirdische Parkplatzflächen werden aus gespeicherten OpenStreetMap-Wegen
erzeugt; die Gebäude haben Kollisionen. Straßenbreiten verwenden `width`, wo
vorhanden, andernfalls wird aus `lanes` mit 3 Metern pro Fahrstreifen geschätzt.
Ohne diese Angaben gelten je nach Wegtyp 2, 4, 6 oder 7 Meter.
Straßen- und Wegstücke werden an ihren OSM-Punkten abgerundet verbunden;
die OSM-Mittellinien bleiben unverändert. Überlappende Gehwege und
Fußgängerflächen werden von Straßen verdeckt, auch auf der Spielkarte.
Brücken, Tunnel und andere höhengetrennte Kreuzungen werden dabei noch nicht
berücksichtigt.
Gebäude verwenden `height`, andernfalls `building:levels` mit 3 Metern pro
Etage; ohne Angaben sind es 10 Meter, für Garagen 3 Meter. Maße ohne Einheit
oder mit `m` gelten als Meter; `ft` wird in Meter umgerechnet. Nicht auswertbare
Angaben führen zur jeweils nächsten Schätzung.

Parkplätze und Fußgängerflächen müssen als geschlossene Wege vorliegen;
Parkplatzpunkte, unterirdische Parkplätze und Relationen werden noch nicht
dargestellt. In Straßentags angegebene Gehwege werden nicht automatisch
hinzuerfunden. Gebäudeformen und geschätzte Höhen bleiben vereinfacht; das
Gelände ist eben und echte Höhendaten fehlen noch.

Der mitgelieferte Thalhofen-Bereich umfasst 47.7735–47.7765° Nord und
10.6013–10.6057° Ost (ungefähr 330 × 330 Meter). Wege können über diesen
Bereich hinausragen. Bei Faktor 1,0 entspricht eine Godot-Einheit ungefähr
einem Meter; die Spielfigur ist 1,8 Meter hoch. Die Daten werden offline aus
`data/thalhofen.json` erzeugt. Die Daten stammen aus der
[Overpass API](https://overpass-api.de/), abgerufen am 24. November 2026;
der OSM-Datenstand ist im Datensatz vermerkt. Gespeichert sind die Geometrien
und Tags der Gebäude-, Straßen- und Parkplatzwege. Der ältere Berliner
Testdatensatz enthält weiterhin nur eine reduzierte Auswahl von Tags und keine
Parkplatzflächen. Früher gespeicherte Nutzerorte bleiben unverändert und können
nicht automatisch um bisher fehlende Daten ergänzt werden.

Die Spielwelt ist in Blöcke von 500 × 500 Metern aufgeteilt. Um jeden Spieler
bleibt ein 3 × 3-Bereich aktiv; im Multiplayer wird die Vereinigung der
Spielerbereiche geladen. Beim Wechsel in einen Nachbarblock werden nur neu
benötigte Blöcke ergänzt und nicht mehr benötigte Geometrie und Kollisionen
entfernt. Fehlende Blöcke werden über die konfigurierte Overpass-API geladen
und unter `user://map_blocks` zwischengespeichert. Bereits gecachte Blöcke
lassen sich offline verwenden. Für einen neuen Ort dient der geladene
Kartenausschnitt zunächst als Startbereich, während der vollständige
500-Meter-Block im Hintergrund geladen wird. Im Multiplayer lädt ausschließlich
der Server fehlende Blöcke von Overpass und überträgt sie an die Clients.
Bereits aktive Blöcke werden beim Beitritt ebenfalls übertragen. Clients
speichern empfangene Blöcke im lokalen Cache und benötigen daher keinen eigenen
Zugriff auf die Overpass-Quelle. Unter Windows befindet sich der Cache
üblicherweise in `%APPDATA%\Godot\app_userdata\OpenCrime\map_blocks`.
Die Dateinamen enthalten derzeit einen Hash der Orts-ID und die Blockindizes;
sie sind nicht als geografische Koordinaten lesbar.
Beim Wechsel des zentralen Blocks bleibt der Spielfeldrand zunächst an seiner
bisherigen Position und rückt erst vor, wenn alle neun Blöcke des neuen
3 × 3-Bereichs aktiv sind. Fehlgeschlagene Overpass-Anfragen werden nach 2, 4,
8, 16 und anschließend höchstens alle 30 Sekunden erneut versucht.
Ein Spielprotokoll mit Sitzungsbeginn, Blockdownloads, Cache-Treffern,
Wiederholungsversuchen und Speicherfehlern liegt unter `user://logs/opencrime.log`
(Windows: `%APPDATA%\Godot\app_userdata\OpenCrime\logs\opencrime.log`).
Bei mehr als 1 MiB wird eine vorherige Logdatei als `opencrime.log.1` behalten.

### Kartenfaktor testen

In `project.godot` steht unter `[opencrime]` der Parameter `osm/scale=1.0`.
Er kann beispielsweise auf `1.2` gesetzt werden, um Abstände, Gebäudegrößen und
die Straßenbreiten um 20 % zu vergrößern. Der Wert muss eine
endliche Zahl größer als 0 sein. Nach einer Änderung das Spiel neu starten;
bei geöffnetem Godot-Editor die Projektdatei gegebenenfalls neu laden.

Der Faktor skaliert auch Gebäudehöhen, Parkplatzflächen und den Boden; Figur und
Auto bleiben unverändert. Bei `1.0` entspricht eine Godot-Einheit ungefähr einem Meter.
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
Geplante Erweiterungen stehen in der [Todo-Liste](TODO.md).

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
Der Server überträgt den ausgewählten Startausschnitt an die Clients und lädt
weitere benötigte Blöcke über die konfigurierte Overpass-API. Aktive Blöcke
werden an alle Clients übertragen und dort lokal zwischengespeichert; Clients
benötigen daher keinen eigenen Zugriff auf Overpass.

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

**Wichtig:** Dies ist ein früher Multiplayer-Prototyp ohne Anmeldung,
Verschlüsselung oder Multiplayer-Spielstandspeicherung. Nur in vertrauenswürdigen Netzwerken verwenden und nicht
ungeschützt im Internet bereitstellen.

## Tests ausführen

Im PowerShell-Terminal im Projektordner kann der Fahrzeugtest mit der
Godot-Konsolenprogrammdatei gestartet werden (den Pfad entsprechend anpassen):

```powershell
& "C:\Pfad\zu\Godot_v4.7.2-stable_win64_console.exe" --headless --path . --script res://tests/car_test.gd
& "C:\Pfad\zu\Godot_v4.7.2-stable_win64_console.exe" --headless --path . --script res://tests/multicar_test.gd
& "C:\Pfad\zu\Godot_v4.7.2-stable_win64_console.exe" --headless --path . --script res://tests/health_test.gd
& "C:\Pfad\zu\Godot_v4.7.2-stable_win64_console.exe" --headless --path . --script res://tests/first_aid_test.gd
& "C:\Pfad\zu\Godot_v4.7.2-stable_win64_console.exe" --headless --path . --script res://tests/medkit_test.gd
& "C:\Pfad\zu\Godot_v4.7.2-stable_win64_console.exe" --headless --path . --script res://tests/menu_test.gd
& "C:\Pfad\zu\Godot_v4.7.2-stable_win64_console.exe" --headless --path . --script res://tests/pause_menu_test.gd
& "C:\Pfad\zu\Godot_v4.7.2-stable_win64_console.exe" --headless --path . --script res://tests/osm_map_test.gd
& "C:\Pfad\zu\Godot_v4.7.2-stable_win64_console.exe" --headless --path . --script res://tests/osm_features_test.gd
& "C:\Pfad\zu\Godot_v4.7.2-stable_win64_console.exe" --headless --path . --script res://tests/osm_scale_test.gd
& "C:\Pfad\zu\Godot_v4.7.2-stable_win64_console.exe" --headless --path . --script res://tests/game_map_test.gd
& "C:\Pfad\zu\Godot_v4.7.2-stable_win64_console.exe" --headless --path . --script res://tests/missions_test.gd
& "C:\Pfad\zu\Godot_v4.7.2-stable_win64_console.exe" --headless --path . --script res://tests/mission_game_test.gd
& "C:\Pfad\zu\Godot_v4.7.2-stable_win64_console.exe" --headless --path . --script res://tests/save_game_test.gd
& "C:\Pfad\zu\Godot_v4.7.2-stable_win64_console.exe" --headless --path . --script res://tests/place_test.gd
& "C:\Pfad\zu\Godot_v4.7.2-stable_win64_console.exe" --headless --path . --script res://tests/place_download_test.gd
& "C:\Pfad\zu\Godot_v4.7.2-stable_win64_console.exe" --headless --path . --script res://tests/map_cache_test.gd
& "C:\Pfad\zu\Godot_v4.7.2-stable_win64_console.exe" --headless --path . --script res://tests/map_block_test.gd
& "C:\Pfad\zu\Godot_v4.7.2-stable_win64_console.exe" --headless --path . --script res://tests/game_log_test.gd
& "C:\Pfad\zu\Godot_v4.7.2-stable_win64_console.exe" --headless --path . --script res://tests/connection_failure_test.gd
```

Der Spielstandtest simuliert absichtlich Speicherfehler; der Erste-Hilfe-Test
prüft ungültige Einstellungen. Entsprechende Fehlermeldungen in der Konsole
sind dabei erwartet.

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

Für den gemeinsamen Auftrags- und Erste-Hilfe-Test zwei Terminals öffnen und
zuerst den Host, dann den Client starten. Standardmäßig wird UDP-Port 17785 verwendet:

```powershell
& "C:\Pfad\zu\Godot_v4.7.2-stable_win64_console.exe" --headless --path . --script res://tests/mission_network_test.gd -- --host
```
```powershell
& "C:\Pfad\zu\Godot_v4.7.2-stable_win64_console.exe" --headless --path . --script res://tests/mission_network_test.gd
```

Der Multiplayer-Test für Lebensenergie läuft ebenso in zwei Terminals und
verwendet standardmäßig UDP-Port 17786:

```powershell
& "C:\Pfad\zu\Godot_v4.7.2-stable_win64_console.exe" --headless --path . --script res://tests/health_network_test.gd -- --host
```
```powershell
& "C:\Pfad\zu\Godot_v4.7.2-stable_win64_console.exe" --headless --path . --script res://tests/health_network_test.gd
```

Der Test für mehrere gleichzeitig fahrende Spieler läuft ebenfalls in zwei
Terminals und verwendet standardmäßig UDP-Port 17787:

```powershell
& "C:\Pfad\zu\Godot_v4.7.2-stable_win64_console.exe" --headless --path . --script res://tests/multicar_network_test.gd -- --host
```
```powershell
& "C:\Pfad\zu\Godot_v4.7.2-stable_win64_console.exe" --headless --path . --script res://tests/multicar_network_test.gd
```
