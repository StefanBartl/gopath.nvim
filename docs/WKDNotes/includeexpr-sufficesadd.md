Einfluss von includeexpr und suffixesadd

includeexpr ist ein Ausdruck (Vimscript), den man setzen kann, damit Dateinamen beim Öffnen transformiert werden. Beispiel: Pfade in Makefile-Syntax umwandeln oder relative Pfade anpassen.

Ablauf: <cfile> liefert den Rohpfad → includeexpr wird ausgewertet → Ergebnis wird weiterverarbeitet (z. B. über findfile()).

suffixesadd enthält Dateiendungen, die automatisch angehängt werden, wenn bei der Suche nach Dateien kein Treffer vorliegt. Beispiel: :set suffixesadd=.c,.h → foo könnte zu foo.c oder foo.h erweitert werden.

Praktische Reihenfolge: man extrahiert <cfile>, wendet optional includeexpr an, versucht existente Datei zu öffnen, sonst werden suffixesadd-Erweiterungen geprüft.
