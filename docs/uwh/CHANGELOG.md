# Changelog

## 0.2.1 – 2026-09-22

- Behoben: Was im Menü angehakt wurde, ging verloren – installiert wurde nur die
  Vorauswahl.
- Behoben: Mit Leerzeichen im Pfad („C:\Users\Max Mustermann“) oder von einem
  Netzlaufwerk fand der Lauf mit Administratorrechten seinen Zwischenstand nicht.
- Fehlermeldungen bleiben stehen, bis eine Taste gedrückt wird – auch beim Start
  über die Verknüpfung.
- „Später neu starten“: uwh macht nach dem nächsten Neustart von allein weiter.
- Sicherheit: Profile setzen nur noch Antworten, nach denen der Katalog fragt;
  Direkt-Downloads nur mit Prüfsumme (`sha256`).
- Profile: Umlaute und Akzente im Namen; `reboot: nein` und `unattended: "false"`
  werden richtig verstanden; Pfade wie `\\nas\…` und Werte wie `007` bleiben beim
  Speichern heil.
- Entfernen fragt mit Vorgabe „Nein“; Aktualisieren von nicht Installiertem ist
  kein Fehler mehr.
- PowerShell-Module lassen sich mit dem PowerShellGet von Windows installieren.
- Schneller: Downloads ohne Fortschrittsbalken (bis zu hundertmal), Katalog und
  Menü; kein Warten auf unerreichbare eigene Repos. Alte Protokolle werden
  aufgeräumt.
- Eine git-Arbeitskopie aktualisiert sich nicht mehr selbst.
- Einzeiler `irm … | iex`: Ein Fehler schließt das Fenster nicht mehr und
  verändert die Sitzung nicht.
- Neu: `tools/build.ps1` – alle Prüfungen und das Release-Archiv
  `dist/uwh-<version>.zip`.

## 0.2.0 – 2026-09-22

- Fünf Sprachen: Deutsch, Englisch, Französisch, Italienisch, Spanisch. uwh
  spricht wie Windows, `L` im Menü wechselt, die Wahl steht in
  `apps/cli/config/settings.yaml`. Fester Wert beim Aufruf: `-Language fr`.
- Katalog mehrsprachig: Grundtext Englisch, Übersetzung mit Kürzel
  (`descriptionDE`, `categoryFR` …). Firefox und Thunderbird kommen in der
  eingestellten Sprache, Aktualisieren und Entfernen treffen die installierte.
- Eigene Einträge mit den deutschen Kategorienamen von bisher landen weiter in
  der richtigen Kategorie.
- Einrichtung (`tools/install.ps1`) ebenfalls in fünf Sprachen. Der Einzeiler
  `irm … | iex` scheiterte am BOM der Datei – behoben.
- Energieplan wird mit 1, 2 oder 3 gewählt; alte Antworten in Profilen gelten weiter.

## 0.1.0 – 2026-09-22

- Software auswählen und in einem Rutsch installieren: winget, Windows-Funktionen,
  optionale Komponenten, PowerShell-Module, Direkt-Download, eigene Skripte.
- Alle Fragen vorab, danach läuft alles allein durch – auch über einen Neustart.
- Profile zum Wiederholen auf dem nächsten Rechner, Kennwörter werden nie gespeichert.
- Eigene Programme und eigene Repos wie bei ulh.
- Aufbau nach dem Projektstandard: Programm unter `apps/cli/`, Eigenes in
  `apps/cli/config/` und `apps/cli/data/`, Einrichtung unter `tools/`.
