# Changelog

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
