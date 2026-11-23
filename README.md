# OpenCrime

OpenCrime ist der Arbeitstitel für ein Open-World-Spiel aus der Vogelperspektive.
Langfristig sind unter anderem Fahrzeuge, Aufträge, Multiplayer und eine Spielwelt
auf Basis realer Kartendaten geplant.

## Aktueller Prototyp

Der erste Prototyp enthält eine kleine 3D-Testfläche, Gebäude mit Kollisionen,
eine Spielfigur und ein einfaches Auto. Mit **WASD** bewegt sich die Figur oder
fährt das Auto in die jeweilige Richtung. In der Nähe des Autos steigt man mit
**E** ein und später wieder aus. Die Fahrphysik ist vorerst bewusst einfach.

Der Multiplayer-Prototyp synchronisiert Spieler und das gemeinsame Auto über
einen Server. Der Server berechnet Bewegung und Kollisionen; das Auto kann nur
von einem Spieler gleichzeitig gefahren werden. Echte Kartendaten sind noch
nicht implementiert.

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

## Multiplayer ausprobieren

1. Das Spiel starten und **Spiel hosten** wählen. Der Host spielt selbst mit.
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

Der Port ist optional und standardmäßig 7777. Zum Beenden **Strg+C** drücken.
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
