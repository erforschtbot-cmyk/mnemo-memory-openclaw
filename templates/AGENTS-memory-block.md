# Gedaechtnis-Arbeitsregeln (Block fuer AGENTS.md)

Diesen Abschnitt in die `AGENTS.md` der OpenClaw aufnehmen, die das
Mnemo-Verfahren nutzt. Er beschreibt Verhalten, nicht Installation. Ohne diese
Regeln speichert der Agent entweder nichts oder unbrauchbaren Text.

## Memory

- **Vor Antworten** zu frueherer Arbeit, Entscheidungen, Personen, Vorlieben
  oder TODOs: `memory_search` (nativ). Fuer Treffer in Memory-Dateien
  `memory_get` mit den betroffenen Zeilen. Nicht erneut suchen, wenn der
  aktuelle Kontext die Frage schon beantwortet.
- **Fuer sitzungs- und agentenuebergreifende oder aeltere Fakten:**
  `mnemo_recall` (eigener Agent) bzw. `mnemo_search` (alle Agenten, wenn
  `MNEMO_SHARE=always`). Vor wiederkehrenden Aufgaben:
  `mnemo_recall_trajectory` — dort stehen bewaehrte Arbeitsschritte.
- **Speichern nach Salienz, nicht als Protokoll:** Entscheidungen, verifizierte
  Fakten, geloeste nicht-triviale Probleme, stabile Vorlieben. Kein Chat-
  Rauschen, keine Logs, keine Zwischenschritte.
- **Nichts Geheimes:** keine Passwoerter, Tokens, Schluessel, keine
  personenbezogenen Daten ohne Anlass. Mnemo liegt im Klartext auf der Platte.
- **Quelle angeben:** `source: "user"` nur, wenn der Mensch es gesagt hat;
  `"tool"` bei deterministischem Tool-Output (Befehl, Messung, API-Antwort);
  `"inferred"` fuer eigene Schluesse.
- **Kategorie waehlen** (steuert den Verfall):
  - `topology` — IPs, Ports, Pfade, Prozessstaende (verfaellt schnell)
  - `current_state` — aktueller Zustand von etwas
  - `incident` — Fehler, Ursache, Fix
  - `decision` — getroffene Entscheidung mit Begruendung
  - `doctrine` — dauerhafte Regel
  - `identity` / `relationship` — wer ist wer, wer mag was
  - `idea` — noch nicht umgesetzt
  - `session_log` — Verlauf; wird aus normalen Recalls herausgefiltert
  Ohne Angabe raet Mnemo per Regex und nennt die Wahl in der Antwort.
- **`stale_warning` befolgen:** Topologie- und `current_state`-Treffer vor dem
  Handeln live pruefen (Datei, Dienst, API). Erinnerung ist ein Hinweis, kein
  Beweis.
- **Exakte Fakten** als `(entity, attribute)` per `mnemo_fact_save` (UPSERT).
  `confidence: "verified"` nur nach Bestaetigung durch Quellcode, Tool-Output
  oder direkte Aussage des Menschen.
- **Nach guter nicht-trivialer Arbeit:** `mnemo_save_trajectory` mit
  geordneten Schritten, Ergebnis und ehrlicher 1-5-Bewertung. Auch ein
  lehrreich gescheiterter Lauf darf gespeichert werden.
- **Workspace:** Tagesnotizen `memory/YYYY-MM-DD.md`, laengere Details
  `memory/topics/`, `MEMORY.md` bleibt ein kleiner kuratierter Index.
- **Dreaming** laeuft nativ nachts (Default `0 3 * * *`), konsolidiert und
  promoted nach `MEMORY.md`. Nicht manuell nachbauen; bei Bedarf `/dreaming`.
- **Private Memory** nur in Haupt-/Direktsitzungen laden, nie in Gruppen.

## Typische Fehler, die du vermeidest

| Fehler | Folge | Besser |
|---|---|---|
| Jeden Chatverlauf speichern | Recall liefert Rauschen, Kosten steigen | nur Salientes |
| `source: "user"` fuer eigene Schluesse | falsche Sicherheit | `"inferred"` |
| Topologie aus der Erinnerung handeln | falsche IP, toter Dienst | live pruefen |
| `session_log` in normale Recalls mischen | wichtige Fakten gehen unter | Default-Filter lassen |
| Secrets speichern | Klartext-Leak | nie |
