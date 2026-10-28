#!/usr/bin/env python3
"""Store listing text for extra languages, with Apple's limits and keyword-overlap checks.

Run: python3 store/localized_listings.py          (checks everything)
     python3 store/localized_listings.py --write  (writes store/listing-localized.md)
Limits: name 30, subtitle 30, keywords 100, promo 170, description 4000.
The app screens are English only; each description says so near the top, on purpose.
"""
import re
import sys

LOCALES = {
    "Spanish (Mexico)": dict(
        name="Murmur: Transcribir Audio",
        subtitle="Voz a texto, sin conexión",
        keywords="transcripción,dictado,whisper,notas,reunión,clase,entrevista,grabadora,subtítulos,ia,srt,privado",
        promo="Transcribe reuniones, clases y notas de voz en tu dispositivo con Whisper. Sin cuenta, sin subir nada, sin internet. Prueba Pro 3 días gratis.",
        description="""Convierte voz en texto sin enviarla a ningún lado.

Murmur transcribe reuniones, clases, entrevistas y notas de voz. Graba o importa audio y video que ya tengas, y obtén una transcripción precisa con Whisper, que funciona directamente en tu dispositivo. Sin servidores y sin cuentas. Tu audio y tu texto nunca se suben a nuestros servidores, y Murmur funciona incluso en modo avión después de descargar una sola vez el modelo de voz.

Transcribe en 13 idiomas, entre ellos español e inglés. Las pantallas de la app están en inglés por ahora.

GRABA O IMPORTA
• Graba con un toque y marca los momentos importantes
• Importa desde Archivos, o videos desde Fotos, y transcribe varios a la vez
• Envía grabaciones desde tu Apple Watch y encuéntralas transcritas en tu iPhone

LEE, BUSCA Y CORRIGE
• Toca cualquier línea para reproducir desde ese momento
• Busca en todas tus notas y usa buscar y reemplazar en una transcripción
• Edita el texto, divide y une líneas, e indica quién habló
• Agrega tus nombres y términos a un diccionario personal para que se escriban a tu manera

RESÚMENES PRIVADOS
• Resúmenes de reunión, clase o en viñetas, con tareas pendientes
• Se crean en tu dispositivo con Apple Intelligence (en dispositivos compatibles)

EXPORTA COMO QUIERAS
• Texto, Markdown, subtítulos (SRT) o audio
• Comparte con cualquier app o copia al portapapeles

EN TODOS TUS DISPOSITIVOS
• iPhone, iPad, Mac y Apple Watch
• La sincronización con iCloud es opcional: mantiene tus notas, transcripciones, carpetas y diccionario al día en tu iCloud privado. Viene desactivada. El audio se queda en el dispositivo que lo grabó.
• En Mac: grabadora en la barra de menús y un atajo global para empezar a grabar desde cualquier app

PRIVADO POR DISEÑO
Sin analíticas. Sin anuncios. Sin rastreo. Murmur descarga su modelo de voz una vez y luego funciona sin conexión.

MURMUR PRO
Gratis: los primeros 2 minutos de cada nota. Pro desbloquea transcripciones completas, edición, exportación, buscar y reemplazar, y resúmenes de todo lo que grabes, incluidas notas anteriores.
• Anual, con 3 días de prueba gratis
• Mensual
• De por vida, un solo pago
Los precios se muestran en la app y varían según el país.
Las suscripciones se renuevan automáticamente a menos que las canceles al menos 24 horas antes de que termine el periodo. Adminístralas en Ajustes > tu ID de Apple > Suscripciones.

Términos de uso: https://killoldesai.github.io/murmur/terms/
Política de privacidad: https://killoldesai.github.io/murmur/privacy/""",
    ),
    "German": dict(
        name="Murmur: Sprache zu Text",
        subtitle="Transkription ohne Internet",
        keywords="diktieren,transkribieren,whisper,audio,notizen,meeting,vorlesung,interview,untertitel,ki,srt,memo",
        promo="Transkribiere Meetings, Vorlesungen und Sprachnotizen direkt auf deinem Gerät mit Whisper. Kein Konto, kein Upload, auch offline. Pro 3 Tage gratis testen.",
        description="""Sprache in Text umwandeln, ohne sie irgendwohin zu senden.

Murmur transkribiert Meetings, Vorlesungen, Interviews und Sprachnotizen. Nimm auf oder importiere vorhandene Audio- und Videodateien und erhalte eine genaue Transkription von Whisper, das direkt auf deinem Gerät läuft. Keine Server, keine Konten. Deine Aufnahmen und Texte werden nie zu uns hochgeladen, und Murmur funktioniert nach dem einmaligen Download des Sprachmodells sogar im Flugmodus.

Transkribiert in 13 Sprachen, darunter Deutsch und Englisch. Die Oberfläche der App ist derzeit auf Englisch.

AUFNEHMEN ODER IMPORTIEREN
• Mit einem Tipp aufnehmen und wichtige Momente markieren
• Aus Dateien importieren, Videos aus Fotos, und gleich mehrere nacheinander abarbeiten
• Aufnahmen von der Apple Watch senden und fertig transkribiert auf dem iPhone finden

LESEN, SUCHEN, KORRIGIEREN
• Auf eine Zeile tippen und ab dieser Stelle abspielen
• Alle Notizen durchsuchen, in einer Transkription suchen und ersetzen
• Text bearbeiten, Zeilen teilen und zusammenführen, Sprecher benennen
• Eigene Namen und Fachbegriffe in ein Wörterbuch aufnehmen, damit sie richtig geschrieben werden

ZUSAMMENFASSUNGEN, DIE PRIVAT BLEIBEN
• Zusammenfassungen für Meetings, Vorlesungen oder als Stichpunkte, mit Aufgaben
• Auf deinem Gerät mit Apple Intelligence erstellt (auf unterstützten Geräten)

EXPORT, WIE DU ES BRAUCHST
• Text, Markdown, Untertitel (SRT) oder Audio
• In jede App teilen oder direkt in die Zwischenablage kopieren

AUF ALLEN GERÄTEN
• iPhone, iPad, Mac und Apple Watch
• Optionale iCloud-Synchronisierung hält Notizen, Transkriptionen, Ordner und Wörterbuch über deinen privaten iCloud-Bereich aktuell. Sie ist standardmäßig aus. Audio bleibt auf dem Gerät, das es aufgenommen hat.
• Am Mac: Aufnahme aus der Menüleiste und ein globales Tastenkürzel, um aus jeder App aufzunehmen

PRIVAT VON GRUND AUF
Keine Analyse. Keine Werbung. Kein Tracking. Murmur lädt sein Sprachmodell einmal herunter und arbeitet danach offline.

MURMUR PRO
Kostenlos: die ersten 2 Minuten jeder Notiz. Pro schaltet vollständige Transkriptionen, Bearbeiten, Export, Suchen und Ersetzen sowie Zusammenfassungen für alles frei, was du aufnimmst, auch für ältere Notizen.
• Jährlich, mit 3 Tagen kostenlosem Test
• Monatlich
• Lebenslang, einmalige Zahlung
Die Preise siehst du in der App, sie unterscheiden sich je nach Land.
Abos verlängern sich automatisch, wenn du nicht mindestens 24 Stunden vor Ablauf des Zeitraums kündigst. Verwalten unter Einstellungen > Apple-ID > Abonnements.

Nutzungsbedingungen: https://killoldesai.github.io/murmur/terms/
Datenschutzerklärung: https://killoldesai.github.io/murmur/privacy/""",
    ),
    "French": dict(
        name="Murmur: Audio en Texte",
        subtitle="Transcription hors ligne",
        keywords="dictée,vocal,whisper,notes,réunion,cours,entretien,dictaphone,sous-titres,ia,srt,privée,mémo",
        promo="Transcrivez réunions, cours et notes vocales sur votre appareil avec Whisper. Sans compte, sans envoi de données, même hors ligne. Essayez Pro 3 jours gratuitement.",
        description="""Transformez la voix en texte sans l'envoyer nulle part.

Murmur transcrit vos réunions, cours, entretiens et notes vocales. Enregistrez ou importez de l'audio et de la vidéo existants, et obtenez une transcription précise grâce à Whisper, qui fonctionne directement sur votre appareil. Pas de serveur, pas de compte. Votre audio et votre texte ne sont jamais envoyés chez nous, et Murmur fonctionne même en mode avion après le téléchargement unique du modèle vocal.

Transcrit en 13 langues, dont le français et l'anglais. L'interface de l'app est pour l'instant en anglais.

ENREGISTRER OU IMPORTER
• Enregistrez d'une touche et repérez les moments importants
• Importez depuis Fichiers, ou des vidéos depuis Photos, et traitez-en plusieurs à la suite
• Envoyez des enregistrements depuis votre Apple Watch et retrouvez-les transcrits sur votre iPhone

LIRE, CHERCHER, CORRIGER
• Touchez une ligne pour lire à partir de cet instant
• Cherchez dans toutes vos notes, puis cherchez et remplacez dans une transcription
• Modifiez le texte, scindez et fusionnez les lignes, indiquez qui parle
• Ajoutez vos noms et termes à un dictionnaire personnel pour qu'ils soient écrits comme vous le voulez

DES RÉSUMÉS QUI RESTENT PRIVÉS
• Résumés de réunion, de cours ou en liste, avec les actions à mener
• Créés sur votre appareil avec Apple Intelligence (sur les appareils compatibles)

EXPORTEZ COMME VOUS VOULEZ
• Texte, Markdown, sous-titres (SRT) ou audio
• Partagez vers n'importe quelle app ou copiez dans le presse-papiers

SUR TOUS VOS APPAREILS
• iPhone, iPad, Mac et Apple Watch
• La synchronisation iCloud, facultative, garde vos notes, transcriptions, dossiers et dictionnaire à jour via votre iCloud privé. Elle est désactivée par défaut. L'audio reste sur l'appareil qui l'a enregistré.
• Sur Mac : enregistreur dans la barre des menus et raccourci global pour enregistrer depuis n'importe quelle app

PRIVÉ PAR CONCEPTION
Aucune analyse. Aucune publicité. Aucun suivi. Murmur télécharge son modèle vocal une fois, puis fonctionne hors ligne.

MURMUR PRO
Gratuit : les 2 premières minutes de chaque note. Pro débloque les transcriptions complètes, la modification, l'export, chercher et remplacer, et les résumés pour tout ce que vous enregistrez, y compris vos anciennes notes.
• Annuel, avec 3 jours d'essai gratuit
• Mensuel
• À vie, paiement unique
Les prix s'affichent dans l'app et varient selon le pays.
Les abonnements se renouvellent automatiquement sauf résiliation au moins 24 heures avant la fin de la période. Gérez-les dans Réglages > identifiant Apple > Abonnements.

Conditions d'utilisation : https://killoldesai.github.io/murmur/terms/
Politique de confidentialité : https://killoldesai.github.io/murmur/privacy/""",
    ),
    "Portuguese (Brazil)": dict(
        name="Murmur: Áudio para Texto",
        subtitle="Transcrição offline e privada",
        keywords="transcrever,ditado,voz,whisper,notas,reunião,aula,entrevista,gravador,legendas,ia,srt,memo",
        promo="Transcreva reuniões, aulas e notas de voz no seu aparelho com o Whisper. Sem conta, sem envio de dados, funciona offline. Teste o Pro por 3 dias grátis.",
        description="""Transforme voz em texto sem enviá-la para lugar nenhum.

O Murmur transcreve reuniões, aulas, entrevistas e notas de voz. Grave ou importe áudios e vídeos que você já tem e receba uma transcrição precisa do Whisper, que roda direto no seu aparelho. Sem servidores e sem contas. Seu áudio e seu texto nunca são enviados para nós, e o Murmur funciona até no modo avião depois de baixar o modelo de voz uma única vez.

Transcreve em 13 idiomas, incluindo português e inglês. As telas do app estão em inglês por enquanto.

GRAVE OU IMPORTE
• Grave com um toque e marque os momentos importantes
• Importe de Arquivos, ou vídeos de Fotos, e transcreva vários em fila
• Envie gravações do Apple Watch e encontre tudo transcrito no iPhone

LEIA, BUSQUE E CORRIJA
• Toque em qualquer linha para ouvir a partir daquele ponto
• Busque em todas as notas e use localizar e substituir em uma transcrição
• Edite o texto, divida e junte linhas e indique quem falou
• Adicione seus nomes e termos a um dicionário pessoal para que sejam escritos do seu jeito

RESUMOS QUE FICAM PRIVADOS
• Resumos de reunião, aula ou em tópicos, com tarefas
• Criados no seu aparelho com a Apple Intelligence (em aparelhos compatíveis)

EXPORTE DO SEU JEITO
• Texto, Markdown, legendas (SRT) ou áudio
• Compartilhe com qualquer app ou copie para a área de transferência

EM TODOS OS SEUS APARELHOS
• iPhone, iPad, Mac e Apple Watch
• A sincronização com o iCloud é opcional e mantém notas, transcrições, pastas e dicionário em dia no seu iCloud privado. Vem desativada. O áudio fica no aparelho que gravou.
• No Mac: gravador na barra de menus e um atalho global para gravar de qualquer app

PRIVADO POR PROJETO
Sem análises. Sem anúncios. Sem rastreamento. O Murmur baixa o modelo de voz uma vez e depois funciona offline.

MURMUR PRO
Grátis: os primeiros 2 minutos de cada nota. O Pro libera transcrições completas, edição, exportação, localizar e substituir e resumos de tudo o que você grava, inclusive notas antigas.
• Anual, com 3 dias de teste grátis
• Mensal
• Vitalício, pagamento único
Os preços aparecem no app e variam conforme o país.
As assinaturas são renovadas automaticamente, a menos que você cancele pelo menos 24 horas antes do fim do período. Gerencie em Ajustes > ID Apple > Assinaturas.

Termos de uso: https://killoldesai.github.io/murmur/terms/
Política de privacidade: https://killoldesai.github.io/murmur/privacy/""",
    ),
}

LIMITS = dict(name=30, subtitle=30, keywords=100, promo=170, description=4000)


def words(text):
    return set(re.findall(r"[^\W\d_]+", text.lower()))


def check():
    ok = True
    for loc, d in LOCALES.items():
        print(loc)
        for field, limit in LIMITS.items():
            value = d["promo" if field == "promo" else field]
            n = len(value)
            flag = "ok " if n <= limit else "BAD"
            ok &= n <= limit
            print(f"  {flag} {field}: {n}/{limit}")
        if " " in d["keywords"].replace(",", ""):
            pass
        spaces = ", " in d["keywords"]
        if spaces:
            print("  BAD keywords have a space after a comma")
            ok = False
        used = words(d["name"]) | words(d["subtitle"])
        dupes = [w for w in d["keywords"].split(",") if words(w) and words(w) <= used]
        if dupes:
            print("  note: keywords repeat name/subtitle words:", dupes)
    return ok


def write():
    out = ["# Localized store listings", "",
           "Generated from `store/localized_listings.py` (limits checked there). The app screens are English only,",
           "so each description says so. Have a native speaker review before launch.", ""]
    for loc, d in LOCALES.items():
        out += [f"## {loc}", "", f"- Name: `{d['name']}`", f"- Subtitle: `{d['subtitle']}`",
                f"- Keywords: `{d['keywords']}`", f"- Promotional text: `{d['promo']}`", "", "```", d["description"], "```", ""]
    open("store/listing-localized.md", "w").write("\n".join(out))


if __name__ == "__main__":
    good = check()
    if "--write" in sys.argv:
        write()
    sys.exit(0 if good else 1)
