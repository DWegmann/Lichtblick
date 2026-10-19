# Lichtblick · SMB Photo Rating

[English](README.md) | **Deutsch**

Ich habe Lichtblick für meinen eigenen Gebrauch entwickelt. Wenn du die App ebenfalls nutzen möchtest, aber keine Möglichkeit hast, sie selbst zu bauen, melde dich gerne über ein [GitHub-Issue](https://github.com/DWegmann/Lichtblick/issues). Bei entsprechendem Interesse könnte ich die App auch zur Veröffentlichung im App Store einreichen.

> **100 % vibe coded:** Der eigene App-Code wurde vollständig mit KI generiert. Die Ideen, Anforderungen und die Steuerung der Entwicklung stammen von Dominic Wegmann. Verwendete Bibliotheken sind eigenständige Projekte ihrer jeweiligen Urheber.
>
> **Nur nichtkommerzielle Weiterverwendung:** Der eigene Projektcode darf unter der [PolyForm Noncommercial License 1.0.0](LICENSE.md) verwendet, verändert und weitergegeben werden. Eine kommerzielle Verwertung ist durch diese Lizenz nicht erlaubt.

Native iPad-App in SwiftUI, ab iPadOS 17. Bilder direkt auf einer SMB-2/3-Freigabe ansehen und mit 0–5 Sternen bewerten. Der Projektordner enthält ein direkt in Xcode zu öffnendes App-Projekt und ein separat testbares Metadatenmodul.

## Beispiel-Screenshots

Die Aufnahmen zeigen die deutsche Mac-Catalyst-Version mit der integrierten Demobibliothek und generierten Landschaftsillustrationen. Die App ist primär für das iPad ausgelegt; die Anordnung der Bedienelemente kann dort abweichen.

### Bibliothek

Bildübersicht mit Sternebewertungen und Bildern aus Unterordnern.

![Bildübersicht der Demobibliothek mit neun Bildern und Sternebewertungen](docs/screenshots/bibliothek.jpg)

### Bewertungsfilter

Die Bildübersicht lässt sich nach unbewerteten, mit 1–5 Sternen bewerteten oder abgelehnten Bildern filtern.

![Geöffnetes Menü mit den verfügbaren Bewertungsfiltern](docs/screenshots/bewertungsfilter.jpg)

### Einzelansicht

Große Bildansicht mit Navigation und direkter Sternebewertung.

![Einzelansicht eines Demo-Bildes mit einer Bewertung von drei Sternen](docs/screenshots/einzelansicht.jpg)

## Entstehung und Lizenz

Lichtblick ist eine vollständig KI-generierte, „vibe coded“ App, umgesetzt als native Anwendung in **Swift und SwiftUI**. Der Hinweis auf die KI-Entstehung bezieht sich auf den eigenen Projektcode, nicht auf die eingebundenen Drittbibliotheken.

Der eigene Projektcode wird unter der **PolyForm Noncommercial License 1.0.0** veröffentlicht. Nichtkommerzielle Nutzung, Änderungen, eigene darauf aufbauende Projekte und Weitergabe sind nach deren Bedingungen erlaubt. Verkauf, kostenpflichtige Angebote und andere kommerzielle Verwertungen sind durch diese Lizenz nicht gestattet. Bei der Weitergabe müssen der Lizenztext beziehungsweise dessen URL und die vorgeschriebenen Hinweise erhalten bleiben. Maßgeblich ist der vollständige [Lizenztext](LICENSE.md), einschließlich seiner Regelungen für nichtkommerzielle Organisationen.

Required Notice: Copyright 2026 Dominic Wegmann

Diese Lizenz gilt für die eigenen Projektbestandteile, soweit daran entsprechende Rechte bestehen. Drittbibliotheken, deren Quellcode und Lizenztexte behalten ihre jeweiligen Lizenzen; die nichtkommerzielle Beschränkung dieses Projekts schränkt deren eigenständige Rechte nicht ein. Die Hinweise und Lizenztexte zu AMSMB2 und libsmb2 stehen in [OpenSourceLicenses.txt](SMBRating/Resources/OpenSourceLicenses.txt).

Der Quellcode ist damit öffentlich einsehbar und nichtkommerziell weiterverwendbar („source available“); die kommerzielle Einschränkung macht diese Veröffentlichung nicht zu Open Source im Sinne der OSI.

## Starten

1. `SMBRating.xcodeproj` in Xcode öffnen. Das Schema heißt **SMBRating**, die App **Lichtblick**.
2. Xcode lädt die festgelegte SMB-Bibliothek AMSMB2 **4.0.3** automatisch.
3. Einen iPad-Simulator oder ein angeschlossenes iPad auswählen. Für ein echtes Gerät unter **Signing & Capabilities** das eigene Development Team und gegebenenfalls eine eigene Bundle-ID einstellen.
4. App starten und **Demobibliothek öffnen** oder **Mit SMB-Server verbinden** wählen. Die Demo enthält generierte Landschaftsillustrationen; ihre Änderungen existieren nur im Arbeitsspeicher.

Zum lokalen Prüfen ist zusätzlich Mac Catalyst aktiviert. Das Hauptziel bleibt iPadOS. In Xcode **My Mac (Mac Catalyst)** auswählen und mit **⌘R** starten.

## Sprache

Die App unterstützt **Deutsch und Englisch** und folgt der bevorzugten Geräte- beziehungsweise App-Sprache. Für andere Sprachen wird Englisch verwendet. Auf dem iPad lässt sich die Sprache bei Bedarf unter **Einstellungen → Apps → Lichtblick → Sprache** wählen, sofern iPadOS mehrere bevorzugte Sprachen anbietet. Menüs, Statusmeldungen, Dialoge, Fehlermeldungen, VoiceOver-Beschriftungen und der Hinweis zum lokalen Netzwerkzugriff sind übersetzt. Eigene Datei- und Ordnernamen sowie die Namen der Demo-Dateien bleiben unverändert.

## Verbindung

- Server: `nas.local`, `192.168.1.10` oder `smb://nas.local`; ein optionaler Port ist erlaubt.
- Freigabe: beispielsweise `Fotos`, separat vom Server eingeben.
- Startordner: optional, beispielsweise `Urlaub/2026`, relativ zur Freigabe.
- Benutzername, Passwort und optional Domäne; leerer Benutzername verwendet `guest`.
- Optional SMB-3-Verschlüsselung verlangen. Ohne diese Option wird keine Verschlüsselung garantiert. SMB 1 wird nicht verwendet.

Server und iPad müssen sich erreichen können, beispielsweise im selben LAN oder über VPN. Den iPadOS-Dialog für lokalen Netzwerkzugriff erlauben. Das Passwort wird auf Wunsch im gerätegebundenen Schlüsselbund gespeichert; die übrigen Verbindungsdaten liegen in den lokalen App-Einstellungen. Host, Freigabe und die übrigen Verbindungsfelder werden bereits bei der Eingabe lokal gemerkt und beim erneuten Öffnen des Dialogs wieder eingesetzt – auch ohne erfolgreichen Verbindungsaufbau. Dieser Entwurf ist von einer laufenden Verbindung getrennt; ein Passwort ist darin nicht enthalten.

Erfolgreiche SMB-Verbindungen erscheinen unter **Gespeicherte Verbindungen** in der Seitenleiste. Für jede Verbindung wird der zuletzt geöffnete Ordner nach jedem Ordnerwechsel gespeichert. Beim nächsten App-Start wird die zuletzt aktive Verbindung mit diesem Ordner wiederhergestellt. Ist ein gemerktes Passwort im Schlüsselbund zugänglich, erfolgt der Verbindungsaufbau automatisch; andernfalls erscheint der vorausgefüllte Dialog zur Passworteingabe. Passwörter werden pro Verbindung getrennt gespeichert. Ein nicht mehr vorhandener oder nicht mehr zugänglicher letzter Ordner führt mit einem Hinweis zur Freigabenwurzel zurück.

Ein Klick auf einen Eintrag in der Seitenleiste stellt diese Verbindung samt ihrem letzten Ordner wieder her. **Verbindung trennen** beendet die automatische Wiederherstellung für den nächsten Start; die gespeicherten Verbindungen bleiben auswählbar. Auch die Demo merkt sich ihren letzten Ordner, ihre Bewertungen bleiben jedoch nur bis zum App-Ende erhalten. Die zuvor gespeicherte einzelne SMB-Verbindung wird beim ersten Start dieser Version automatisch übernommen; ihr Ordner wird ab jetzt bei der Navigation mitgeführt.

Wenn der Schlüsselbund nicht verfügbar ist, bleibt die SMB-Verbindung trotzdem nutzbar. Ein Hinweis erklärt, dass das eingegebene Passwort nur für die laufende Sitzung verwendet wird. Falls das Löschen eines früher gespeicherten Passworts scheitert, wird dies ausdrücklich gemeldet. Bei einem lokal signierten Mac-Catalyst-Build kann der Schlüsselbundzugriff mit `-34018` scheitern: Zum dauerhaften Speichern unter **Signing & Capabilities** ein eigenes Apple-Development-Team einstellen und die App neu bauen. Siehe [Apples Erklärung zum Fehler -34018](https://developer.apple.com/forums/thread/114456).

## Bilder und Bewertungen

Laufende Bild-, Bewertungs- und Ordnerlesungen nutzen die von iPadOS gewährte Hintergrundzeit, wenn zu einer anderen App gewechselt oder das iPad gesperrt wird. Große, im Vordergrund gestartete Bewertungsprüfungen (ab 100 Bildern) beantragen ab iPadOS 26 zusätzlich einen fortlaufenden Hintergrundauftrag mit System-Fortschrittsanzeige. Bei Ablehnung bleibt die kürzere UIKit-Hintergrundzeit verfügbar. Endet die gewährte Zeit, warten offene Lesevorgänge bis zur Rückkehr in die App und werden dort wiederholt; bereits ermittelte Filtertreffer und der laufende Ordnersuchlauf bleiben im Arbeitsspeicher erhalten. Abbrechen, Filterwechsel und Verbindungswechsel beenden die zugehörigen wartenden Vorgänge. Ratings werden weiterhin nur für die laufende Ansicht gehalten und bei einem neuen Prüflauf frisch gelesen; auf der Festplatte liegen ausschließlich Vorschaubilder. Hintergrunddauer und Netzwerkzugriff bestimmt iPadOS. Ein erzwungenes Schließen oder Beenden durch das System beendet die laufende Arbeit; sie wird nicht als dauerhafter Auftrag gespeichert.

- Sobald nach dem Verbinden oder beim Wiederherstellen der letzten Sitzung ein Ordner geöffnet ist, ist die Seitenleiste standardmäßig eingeklappt. Über das Seitenleisten-Symbol oben links lässt sie sich ein- und ausklappen. Eine anschließend manuell eingeblendete Seitenleiste bleibt beim weiteren Navigieren und Neuladen geöffnet. Der Button bleibt auch bei eingeklappter Seitenleiste erreichbar; in schmalen Fenstern lässt sich die Seitenleiste über denselben Button im Kopfbereich wieder schließen.
- Die Übersicht trennt **Ordner** und **Bilder** in eigene Bereiche mit jeweiliger Anzahl. Beide Bereiche lassen sich unabhängig über ihre Überschrift ein- und ausklappen. Der Bilderbereich merkt sich seine Auswahl nach einem Neustart; der Ordnerbereich startet bei jedem Ordnerwechsel ausgeklappt. Leere Bereiche werden ausgeblendet. Ordnerkacheln öffnen die jeweiligen Unterordner, Bilder erscheinen in einem anpassbaren Raster mit lokal erzeugten Vorschaubildern. Bei eingeklapptem Bilderbereich pausiert das Vorladen. Der Pfeil nach oben führt zum übergeordneten Ordner; die anklickbare Pfadleiste springt direkt zu einem Vorfahren oder zur Freigabe zurück. Auch von einem angegebenen Startordner ist die Freigabenwurzel erreichbar.
- Beim Scrollen werden bis zu zwölf weitere Vorschauen vor und hinter den sichtbaren Bildkacheln vorgeladen. Sichtbare Bilder haben Vorrang; entfernte Vorladeaufträge werden abgebrochen. Suche und Sortierung bestimmen dabei auch die Vorladereihenfolge.
- Ausschließlich verkleinerte Vorschaubilder werden lokal im App-Cache gespeichert und bei erneutem Öffnen wiederverwendet. Ratings und andere Originalmetadaten werden bei jedem Laden frisch vom Server gelesen, auch bei Treffern im Arbeitsspeicher- oder Festplatten-Cache. Die Vorschau erscheint bereits währenddessen; bis zum Abschluss steht dort „Bewertung wird geladen …“. Bei einem Lesefehler wird keine alte Bewertung als aktuell angezeigt. Der bisherige Cache mit gespeicherten Metadaten wird beim ersten Start dieser Version entfernt. Der Cache ist nach Server, Freigabe, Benutzer und Dateipfad getrennt; Dateigröße und Änderungszeit bestimmen seine Gültigkeit. Ohne Änderungszeit vom Server wird nur im Arbeitsspeicher gecached. Die Demo verwendet ebenfalls nur den Arbeitsspeicher.
- Suche nach Dateinamen und natürliche Sortierung, auf- oder absteigend.
- Das Filter-Symbol oben rechts bietet **Alle Bewertungen**, **Ohne Bewertung**, genau **1–5 Sterne** und **Abgelehnt**. Der Filter gilt für die aktuelle Ansicht, bei eingeschalteter Unterordneroption auch für deren Bilder, und lässt sich mit der Dateinamensuche kombinieren. Ordner bleiben zur Navigation sichtbar. Für jede neue Filterauswahl, Suche und jedes Neuladen werden die Bewertungen frisch gelesen; die Ergebnisse gelten nur für die laufende Ansicht und werden nicht dauerhaft gespeichert. Passende Bilder erscheinen bereits während der Prüfung und werden nach und nach ergänzt. Eine kleine Statuszeile zeigt den Fortschritt; die Übersicht bleibt benutzbar und bietet **Abbrechen** an. Nicht lesbare Bewertungen werden gemeldet und niemals als null Sterne behandelt. **Erneut prüfen** beziehungsweise **Bewertungen erneut lesen** wiederholt die Prüfung. **Filter entfernen** stellt die vollständige aktuelle Ansicht wieder her. Die Einzelansicht blättert durch die gefilterte Bildmenge; geänderte Bewertungen aktualisieren die Zugehörigkeit zur Übersicht.
- Unter **Ansicht anpassen** (Regler-Symbol oben rechts) die Sortierung **Dateiname aufsteigend/absteigend** auswählen. Sie gilt für Bilder und Ordner, wobei Ordner weiterhin zuerst erscheinen.
- Ebenfalls dort zwischen **Ausschnitt anzeigen** (bisherige, kachelfüllende Vorschau) und **Ganzes Bild anzeigen** wechseln. Bei der vollständigen Ansicht wird das Seitenverhältnis beibehalten; freie Flächen werden mit dem Kachelhintergrund gefüllt. Vorschaugröße, Darstellung und Sortierung bleiben nach einem Neustart erhalten.
- Einzelansicht mit Wischen, Vor-/Zurück-Tasten, Pinch-Zoom und Doppeltipp-Zoom. Nach unten wischen kehrt zur Übersicht zurück; im vergrößerten Bild verschiebt dieselbe Geste weiterhin das Bild. Während des Speicherns, Verschiebens oder Löschens ist die Rückkehr gesperrt. Beim Bildwechsel gleitet das aktuelle Bild sichtbar zur Seite hinaus, während das nächste beziehungsweise vorherige Bild passend zur Wischrichtung hereinkommt. Eine unabhängige Momentaufnahme hält das ausgehende Bild bis zum Ende der Bewegung sichtbar, auch wenn das nächste Original noch lädt. Die beiden benachbarten Vorschaubilder werden vorbereitet, während Originaldatei und Rating weiterhin frisch geladen werden; bis dahin sind Bewertungen gesperrt. Bei aktivierter Bedienungshilfe **Bewegung reduzieren** wird stattdessen kurz übergeblendet. Im Zoom verschiebt eine Wischbewegung weiterhin das aktuelle Bild.
- Mit externer Tastatur: Pfeiltasten blättern, `1` bis `5` bewerten, `0` entfernt die Bewertung, Escape schließt die Einzelansicht.
- Sterne werden direkt als **`xmp:Rating`** im eingebetteten XMP-Paket gespeichert. `0` bedeutet unbewertet. Bereits vorhandenes `-1` wird als abgelehnt angezeigt; die App vergibt selbst `0…5`.
- Lesen: XMP hat Vorrang, IPTC-StarRating dient als Fallback. Image I/O stellt XMP-Ratings auch über die IPTC-StarRating-Eigenschaft bereit. Es gibt deshalb keinen separaten, möglicherweise widersprüchlichen IPTC-Schreibmodus und keine Sidecar-Dateien.
- JPEG, PNG, HEIC/HEIF und einseitige TIFF-Dateien werden nur über die verlustfreie Image-I/O-Kopierfunktion geändert. Falls das konkrete Format nicht unterstützt wird, erscheint eine Fehlermeldung; es gibt keinen Fallback auf erneute Bildkompression.
- Andere gängige Bild- und RAW-Endungen werden zur Ansicht angeboten, soweit das jeweilige iPadOS sie decodieren kann. RAWs, Animationen und mehrseitige Bilder bleiben schreibgeschützt.

Die Grid-Bewertungen werden frisch aus den Originaldateien gelesen, unabhängig vom Vorschaucache. Unter **Ansicht anpassen → Unterordner einbeziehen** lässt sich die Übersicht auf alle Bilder im aktuellen Ordner und seinen Unterordnern erweitern. Die Option gilt nur für die aktuelle Ansicht und klappt beim Aktivieren den Ordnerbereich ein. Beim Wechsel in einen anderen Ordner, beim erneuten Verbinden und nach einem Neustart ist sie wieder deaktiviert und der Ordnerbereich ausgeklappt. **Neu laden** im selben Ordner behält die Option bei. Unter den Bildern steht dann ihr relativer Ordner; gleichnamige Dateien bleiben getrennt. Ordnerkacheln navigieren weiterhin in die direkten Unterordner. Die Suche nach Bildern ist abbrechbar. Versteckte Ordner und symbolische Verzeichnisverknüpfungen werden nicht durchsucht. Falls ein Ordner nicht gelesen werden kann, meldet die App dessen Pfad und behält die bisherige Ansicht bei. **Neu laden** verwirft den Vorschaucache des Ordners und liest externe Änderungen erneut ein.

Die Demobibliothek enthält zusätzlich die verschachtelten Ordner **Landschaften → Auswahl**, um die Navigation ohne SMB-Server auszuprobieren.

## Dateien verschieben

In der Übersicht ein Vorschaubild lange drücken beziehungsweise auf dem Mac rechtsklicken und **Datei verschieben** wählen. In der Einzelansicht öffnet das Ordner-Symbol oben rechts dieselbe Ordnerauswahl. Über Unterordner, **Übergeordneter Ordner** und die Freigabenwurzel zum gewünschten Ziel navigieren und **Hierher verschieben** wählen. Die Auswahl startet im tatsächlichen Quellordner des Bildes, auch in der Ansicht mit einbezogenen Unterordnern. **Abbrechen** lässt die Datei unverändert.

Verschieben ist innerhalb derselben SMB-Freigabe möglich. Dateiname, Bilddaten und eingebettete Bewertungen bleiben erhalten; die App verschiebt die Datei direkt auf dem Server, ohne sie herunterzuladen und erneut hochzuladen. Der Quellordner ist als Ziel gesperrt. Vorhandene gleichnamige Dateien oder Ordner werden nicht überschrieben; die serverseitige Umbenennung schützt auch vor einem Eintrag, der erst nach der Zielauswahl angelegt wird. Dafür benötigt der SMB-Benutzer die entsprechenden Rechte in Quell- und Zielordner. Ordner und symbolische Verknüpfungen werden nicht verschoben.

Nach erfolgreicher Prüfung aktualisiert sich die Übersicht. Bei einbezogenen Unterordnern bleibt das Bild unter seinem neuen Pfad sichtbar, sofern das Ziel weiterhin im angezeigten Unterbaum liegt. In der Einzelansicht geht es zum nächsten beziehungsweise vorherigen Bild; nach dem letzten Bild öffnet sich die Übersicht. Während des Verschiebens sind weitere Änderungen gesperrt. Die Zielauswahl ändert weder den geöffneten Bibliotheksordner noch die Option **Unterordner einbeziehen**.

Falls die Serverantwort oder die anschließende Prüfung fehlschlägt, zeigt die App Quell- und Zielpfad an und fordert zum Neuladen auf. Sie wiederholt den Verschiebevorgang nicht automatisch. In der Demo gilt das Verschieben nur bis zum erneuten Öffnen der Demobibliothek.

## Dateien löschen

In der Übersicht ein Vorschaubild lange drücken beziehungsweise auf dem Mac rechtsklicken und **Datei löschen** wählen. In der Einzelansicht gibt es dafür einen Papierkorb oben rechts. Vor jedem Löschvorgang erscheint eine Bestätigung mit dem Dateinamen, bei SMB auch mit Server, Freigabe und Pfad. **Abbrechen** oder das Schließen des Dialogs lässt die Datei unverändert.

Erst nach Bestätigung wird die Datei direkt auf der SMB-Freigabe gelöscht. Die App verwendet keinen Papierkorb und bietet kein Rückgängigmachen an. Dafür benötigt der SMB-Benutzer Löschrechte. Während des Vorgangs sind weitere Änderungen gesperrt. Bei Erfolg verschwinden Datei und Bewertung aus der Übersicht. In der Einzelansicht wird das nächste Bild gezeigt, am Ende das vorherige; nach dem letzten Bild öffnet sich die Übersicht. Ordner werden über diese Funktion nicht gelöscht.

Bei Fehlern bleibt die Datei in der Ansicht; ein Hinweis fordert zum Neuladen auf, um den tatsächlichen Serverzustand zu prüfen. In der Demo betrifft das Löschen nur die laufende Demobibliothek: Beim erneuten Öffnen der Demo werden die Beispielbilder wiederhergestellt.

## Schreiben auf die Freigabe

Zum Bewerten werden Lese-, Schreib-, Lösch- und Umbenennrechte im jeweiligen Ordner benötigt. Die App:

1. vergleicht die aktuelle Serverdatei mit der in der Einzelansicht geladenen Originaldatei;
2. erstellt lokal eine Kopie mit aktualisierten XMP-Metadaten;
3. schreibt eine eindeutige `.smbrating-….tmp`-Datei in denselben Ordner und prüft sie durch vollständiges Zurücklesen;
4. prüft das Original erneut, benennt es in `.smbrating-….backup` um und prüft auch diese Sicherung;
5. benennt die geprüfte temporäre Datei auf den ursprünglichen Dateinamen um, liest sie zur Kontrolle zurück und entfernt anschließend die Sicherung.

Bei einem klar erkennbaren Fehler versucht sie, das Original zurückzubenennen. Bei unklarem Netzwerkzustand bleiben Sicherungsdateien zur manuellen Wiederherstellung bestehen; der genaue Pfad wird angezeigt. Eine fehlgeschlagene Sicherungsbereinigung wird ebenfalls gemeldet. Die App führt beim nächsten Start bewusst keine automatische Bereinigung solcher Dateien durch.

Dieser Ablauf ist keine serverseitige Transaktion. Nicht gleichzeitig in anderen Programmen dieselbe Datei bearbeiten. Ein Abbruch genau zwischen den Umbenennungen kann eine Wiederherstellung aus der versteckten Sicherungsdatei erfordern. Dateisystemattribute, ACLs und alternative SMB-Datenströme werden beim Erstellen der Ersatzdatei nicht kopiert; der ursprüngliche Dateiname und die Bildmetadaten werden beibehalten.

## Grenzen und Prüfung

Bei großen Bibliotheken werden Suche, natürliche Sortierung und Positionsindex nur bei Änderungen der Dateiliste, Suche oder Sortierung neu aufgebaut. Scrollereignisse aktualisieren ausschließlich den Vorladecontroller; dieser bündelt Ereignisse einer Bildzeile für 80 ms und bestimmt das nächste Vorladefenster über den Positionsindex. Das Laden einer Kachel ohne vorhandene Bewertungsüberschreibung veröffentlicht keine globale Zustandsänderung. Die Bewertungszeile bleibt beim Nachladen gleich hoch, damit Bildzeilen nicht springen. Ratings werden weiterhin frisch gelesen und nicht gecached. Bei einer neuen Suche oder Sortierung beginnt die Übersicht wieder oben.

Beim ersten Laden einer Vorschau wird die ganze Datei übertragen. Für die Vorschau genügt danach bei unverändertem Dateistand der lokale Cache. Die Metadaten werden unabhängig davon frisch gelesen; aktuell erfordert dies weiterhin die Übertragung der Originaldatei. Maximal drei Bildladevorgänge laufen gleichzeitig, davon pro Vorladefenster nur ein spekulativer Vorgang; überlappende Vorschauanfragen teilen sich einen Ladeauftrag. Der Arbeitsspeicher-Cache ist auf etwa 80 MB begrenzt und bleibt beim Ordnerwechsel erhalten. Der Festplatten-Cache enthält nur Bilddaten von Vorschauen mit maximal 520 Pixeln Kantenlänge, keine Ratings, Originalmetadaten oder Originaldateien; er ist über alle Verbindungen auf 256 MB begrenzt und entfernt die am längsten unbenutzten Einträge zuerst. Das Betriebssystem darf diesen Cache ebenfalls löschen. Bewerten und Löschen verwerfen die betroffenen Cache-Einträge, **Neu laden** erzwingt frische Vorschauen der aufgelisteten Bilder. Dateien über 128 MB werden abgewiesen. Die große Ansicht verwendet eine Vorschau mit maximal 3200 Pixeln Kantenlänge; zum Bewerten wird die Originaldatei weiterhin frisch vom Server gelesen.

Die Tests prüfen Sterne und wiederholte Änderungen, Pixel- und Metadatenerhalt, JPEG/PNG/TIFF/HEIC, Konflikte, beschädigte Uploads, fehlende Rechte, Wiederherstellung, verlorene Antworten auf SMB-Umbenennungen, nicht blockierende Schlüsselbundfehler beim Speichern und Löschen sowie die dauerhafte Speicherung mehrerer Verbindungen, ihrer Ordner und die Übernahme alter Verbindungsdaten sowie rekursive Ordnerlisten, gleichnamige Bilder, Unterbaumgrenzen, ausgelassene versteckte Ordner und Verknüpfungen, Lesefehler und Abbruch:

```sh
swift test
```

Simulator-Build ohne Signierung:

```sh
xcodebuild -project SMBRating.xcodeproj -scheme SMBRating \
  -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
```

Falls die Command Line Tools statt Xcode aktiv sind, `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` vor den jeweiligen Befehl setzen.

Acht zusätzliche Tests prüfen die Ausgabe erster Treffer vor Abschluss der übrigen Lesevorgänge, genaue Bewertungsfilter einschließlich fehlender und abgelehnter Bewertungen, das Zusammenspiel mit Suche und Sortierung, die Erhaltung der Ordnernavigation und Bildindizes, frische Wiederholungslesungen, Lesefehler, maximal drei parallele Lesevorgänge, Fortschritt und Abbruch.

Sieben Tests prüfen die Hintergrundsteuerung mit simulierten Systemfreigaben: Weiterlesen während der Freigabe, Pause bei Zeitablauf, Wiederaufnahme ohne erneutes Lesen fertiger Filtertreffer, Abbruch während der Pause und während aktiver Übertragungen, abgelehnte Freigaben, normale Lesefehler und verspätete oder veraltete Freigabeereignisse. Die tatsächliche Hintergrunddauer auf dem Gerät hängt von iPadOS ab.

Vier zusätzliche Tests prüfen natürliche Sortierung und Suche, gleichnamige Dateien in unterschiedlichen Ordnern, den Positionsindex und Vorladefenster einer Bibliothek mit 1.200 Einträgen in beiden Sortierrichtungen. Die Oberfläche wurde in einer separaten Testkopie mit 1.203 Demo-Bildern beim Scrollen ans Listenende und zurück sowie beim Suchen und Öffnen eines Bildes geprüft. Ein isolierter Vergleich mit 1.200 Einträgen und 200 Scrollereignissen reduzierte die Zeit für wiederholtes Sortieren und die Fenstersuche von etwa 201 ms auf 0,6 ms für die indizierte Fenstersuche; dies ist keine Messung der Bildrate. Ein zusätzlicher Modelltest bestätigt, dass 2.400 wirkungslose Bewertungsbereinigungen keine globalen Ansichtsaktualisierungen auslösen.

Sieben zusätzliche Tests prüfen den dauerhaften Vorschaucache einschließlich reiner Bildspeicherung, Entfernung des alten Metadatencaches, Verbindungstrennung, Dateiversionen, Invalidierung, beschädigter Einträge, Größenlimit und Vorladefenster.

Elf Tests prüfen das Verschieben einschließlich Erhalt der Datei, frisch gespeicherter Bewertungen mit geänderter Dateigröße, Freigabenwurzel als Ziel, ungültiger Pfade, fehlender Quelldateien, Namenskonflikten, fehlender Rechte, Abbruch und verlorener Serverantworten. Die Zustandswechsel der Übersicht wurden zusätzlich mit einem nachgebildeten Dateispeicher geprüft: direkte und rekursive Ansichten, Verschieben innerhalb beziehungsweise außerhalb des angezeigten Unterbaums, Cache- und Bewertungsbereinigung sowie veraltete Anfragen nach Verbindungswechseln. In der laufenden Mac-Catalyst-Demo wurden Kontextmenü, Zielauswahl, Abbrechen, Verschieben aus Übersicht und Einzelansicht, Erhalt einer unmittelbar zuvor gespeicherten Fünf-Sterne-Bewertung und die Rückkehr zur Übersicht nach dem letzten Bild geprüft.

Vier zusätzliche Lokalisierungstests prüfen die Vollständigkeit beider Sprachdateien, passende Platzhalter, formatierte Fortschritts- und Löschmeldungen sowie den Hinweis zum lokalen Netzwerkzugriff. Die lokalisierte App wurde zusätzlich in einer separaten Mac-Catalyst-Testkopie auf Englisch und Deutsch geprüft, einschließlich des englischen Verbindungsdialogs und der Einzelansicht.

Die Tests verwenden Image I/O auf macOS und einen nachgebildeten Dateispeicher. Die iPad-Simulator- und Apple-Silicon-Mac-Catalyst-Builds wurden geprüft. In der laufenden Mac-Catalyst-App wurden Raster, Einzelansicht, Speichern und erneutes Lesen einer Demo-Bewertung kontrolliert. Für die neuen Einstellungen wurden die Sortierung, die vollständige Bilddarstellung, die obere Ordnerausrichtung, gemerkte Formulareingaben und ein Neustart im verschachtelten Demo-Ordner geprüft. Der Löschablauf wurde in der Demo mit Abbrechen, bestätigtem Entfernen aus dem Raster, dem Wechsel zum nächsten Bild und der Rückkehr zur Übersicht nach dem letzten Bild geprüft. Die Installation und der erfolgreiche Prozessstart auf einem physischen iPad wurden ebenfalls geprüft. Die rekursive Demo-Ansicht wurde mit 9 Bildern in der Wurzel, 6 Bildern im Unterordner der gemeinsamen Einzelansicht, dem Ausschalten der Option geprüft. Ein vollständiger Test gegen einen echten SMB-Server steht noch aus.

## Aufbau

- `SMBRating/App`: App-Einstieg und Bibliothekszustand.
- `SMBRating/Views`: Verbindung, Raster, Einzelansicht und Zoom.
- `SMBRating/Services`: SMB-Adapter, Schlüsselbund, Bildpipeline und Demo.
- `SMBRating/Resources`: Drittanbieterhinweise und deutsche/englische Sprachdateien.
- `Sources/RatingCore`: Metadaten und abgesicherter Schreibablauf.
- `Tests/RatingCoreTests`: Tests ohne SMB-Server, einschließlich Lokalisierungsprüfungen.

Verwendete Schnittstellen: [AMSMB2](https://github.com/amosavian/AMSMB2/tree/4.0.3), [Apple Image I/O](https://developer.apple.com/documentation/imageio), [verlustfreies Kopieren von Bildquellen](https://developer.apple.com/documentation/imageio/cgimagedestinationcopyimagesource(_:_:_:_:)). Die Lizenztexte der SMB-Komponenten liegen in `SMBRating/Resources/OpenSourceLicenses.txt` und sind in der App unter **Über Bewertungen** zugänglich.
