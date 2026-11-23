# OpenCrime

OpenCrime ist der Arbeitstitel für ein Open-World-Spiel aus der Vogelperspektive.
Langfristig sind unter anderem Fahrzeuge, Aufträge, Multiplayer und eine Spielwelt
auf Basis realer Kartendaten geplant.

## Aktueller Prototyp

Der erste Prototyp enthält eine kleine 3D-Testfläche, Gebäude mit Kollisionen,
eine Spielfigur und ein einfaches Auto. Mit **WASD** bewegt sich die Figur oder
fährt das Auto in die jeweilige Richtung. In der Nähe des Autos steigt man mit
**E** ein und später wieder aus. Die Fahrphysik ist vorerst bewusst einfach;
Multiplayer und echte Kartendaten sind noch nicht implementiert.

## Projekt öffnen

1. [Godot 4.7.2 Standard](https://godotengine.org/download/archive/4.7.2-stable/)
   für Windows herunterladen und entpacken.
2. Die normale Godot-Programmdatei starten.
3. Im Projektmanager **Importieren** wählen und die Datei `project.godot` in
   diesem Repository auswählen.
4. Das Projekt öffnen und mit **F6** die aktuelle Szene oder mit **F5** das
   gesamte Projekt starten. Beenden lässt sich das Spiel mit **F8**.

Die Projektdateien und Skripte können auch in VS Code bearbeitet werden. Godot
wird weiterhin benötigt, um das Spiel auszuführen und Szenen zu bearbeiten.

## Test ausführen

Im PowerShell-Terminal im Projektordner kann der Fahrzeugtest mit der
Godot-Konsolenprogrammdatei gestartet werden (den Pfad entsprechend anpassen):

```powershell
& "C:\Pfad\zu\Godot_v4.7.2-stable_win64_console.exe" --headless --path . --script res://tests/car_test.gd
```
