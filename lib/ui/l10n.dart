// UI texts, German and English (the Desk speaks both too).
import 'package:flutter/widgets.dart';

class T {
  T(this.de);
  final bool de;

  static T of(BuildContext context) => T(Localizations.localeOf(context).languageCode == 'de');

  String _(String en, String de_) => de ? de_ : en;

  String get welcomeTitle => _('Your NAS in your pocket', 'Dein NAS in der Tasche');
  String get welcomeText => _(
    'In the Desk, open UntrashMesh → "Pair the UntrashApp" as admin and pick your user. Then scan the QR code shown there.',
    'Öffne im Desk als Admin UntrashMesh → „UntrashApp koppeln“ und wähle deinen Benutzer. Dann scanne den QR-Code, der dort erscheint.',
  );
  String get scan => _('Scan QR code', 'QR-Code scannen');
  String get paste => _('Paste invitation', 'Einladung einfügen');
  String get pasteHint => _('Invitation text from the Desk', 'Einladungstext aus dem Desk');
  String get deviceName => _('Name of this phone', 'Name dieses Telefons');
  String get deviceNameHelp => _('Shown in the Desk; a-z, 0-9 and "-"', 'Wird im Desk angezeigt; a-z, 0-9 und „-“');
  String get pair => _('Pair', 'Koppeln');
  String get pairing => _('Pairing …', 'Kopple …');
  String get cancel => _('Cancel', 'Abbrechen');
  String get ok => _('OK', 'OK');
  String invitationFor(String mesh) => _('Invitation to the mesh "$mesh"', 'Einladung in das Mesh „$mesh“');
  String get expired => _(
    'This invitation has expired. Make a new one in the Desk.',
    'Diese Einladung ist abgelaufen. Erstelle im Desk eine neue.',
  );

  String get requests => _('Waiting for you', 'Wartet auf dich');
  String get noRequests => _(
    'Nothing waiting. Sign-ins and confirmations show up here.',
    'Nichts offen. Anmeldungen und Bestätigungen erscheinen hier.',
  );
  String get nasTitle => _('Your NAS', 'Deine NAS');
  String get settings => _('This phone', 'Dieses Telefon');

  String kindTitle(String kind, String? action) => switch (kind) {
    'login' => _('Sign-in without password', 'Anmeldung ohne Passwort'),
    'login2' => _('Sign-in: second step', 'Anmeldung: zweiter Schritt'),
    _ => action ?? _('Confirm an action', 'Aktion bestätigen'),
  };
  String get pickNumber => _(
    'Tap the number the browser shows. If you did not start this, deny it.',
    'Tippe die Zahl an, die der Browser zeigt. Wenn du das nicht warst, lehne ab.',
  );
  String get deny => _('Deny', 'Ablehnen');
  String get approved => _('Approved', 'Bestätigt');
  String get denied => _('Denied', 'Abgelehnt');
  String get gone => _('This request is no longer open.', 'Diese Anfrage ist nicht mehr offen.');
  String from(String ip) => _('from $ip', 'von $ip');
  String secondsLeft(int s) => _('$s s left', 'noch $s s');

  String conn(String c) => switch (c) {
    'connecting' => _('Connecting …', 'Verbinde …'),
    'online' => _('Connected', 'Verbunden'),
    'partly' => _('Partly connected', 'Teilweise verbunden'),
    'offline' => _('No NAS reachable', 'Kein NAS erreichbar'),
    'vpnDenied' => _('VPN permission needed', 'VPN-Erlaubnis nötig'),
    _ => _('Not connected', 'Nicht verbunden'),
  };
  String get reconnect => _('Connect again', 'Neu verbinden');
  String get vpnWhy => _(
    'The app reaches your NAS through its own encrypted tunnel (WireGuard). Android asks once for permission.',
    'Die App erreicht dein NAS über einen eigenen verschlüsselten Tunnel (WireGuard). Android fragt dafür einmal um Erlaubnis.',
  );
  String get noTunnel => _(
    'No tunnel on this platform: development mode, requests go directly.',
    'Kein Tunnel auf dieser Plattform: Entwicklungsmodus, Anfragen gehen direkt.',
  );

  String get linked => _('signed in as', 'angemeldet als');
  String get notLinked => _(
    'Not linked here. An admin of this NAS can link the app under UntrashMesh → Link….',
    'Hier nicht verknüpft. Ein Admin dieses NAS kann die App unter UntrashMesh → Verknüpfen… zuordnen.',
  );
  String get unreachable => _('Not reachable', 'Nicht erreichbar');
  String get version => _('Version', 'Version');
  String get signin => _('Desk sign-in', 'Desk-Anmeldung');
  String signinMode(String m) => switch (m) {
    'app' => _('password or app', 'Passwort oder App'),
    'both' => _('password and app', 'Passwort und App'),
    _ => _('password only', 'nur Passwort'),
  };
  String get signinHelp => _('Change it in the Desk under Account.', 'Ändern kannst du das im Desk unter Konto.');
  String get system => _('System', 'System');
  String get uptime => _('Running for', 'Läuft seit');
  String get memory => _('Memory free', 'Speicher frei');
  String get volumes => _('Volumes', 'Volumes');
  String get arrays => _('Disk groups', 'Datenträgergruppen');
  String get services => _('Services', 'Dienste');
  String get adminOnly => _('Details are shown for admins.', 'Details sehen nur Admins.');
  String free(String a, String b) => _('$a of $b free', '$a von $b frei');

  String get openDesk => _('Open the Desk', 'Desk öffnen');
  String get openDeskHelp => _(
    'Files, shares, users, media, settings: the whole Desk of this NAS, over the encrypted tunnel.',
    'Dateien, Freigaben, Benutzer, Medien, Einstellungen: der ganze Desk dieses NAS, über den verschlüsselten Tunnel.',
  );
  String get reload => _('Reload', 'Neu laden');
  String get deskFailed => _('The Desk could not be opened', 'Der Desk ließ sich nicht öffnen');
  String get deskNeedsUpdate => _(
    'This NAS needs UntrashOS 1.1-rc9 or newer for the Desk in the app.',
    'Für den Desk in der App braucht dieses NAS UntrashOS 1.1-rc9 oder neuer.',
  );
  String downloading(String name) => _('Downloading $name …', 'Lade $name herunter …');

  String get tunnelStarts => _('Tunnel starts', 'Tunnel-Starts');
  String get tunnelStartsHelp => _(
    'Newest first. Many starts in a row mean the tunnel is not stable.',
    'Neueste zuerst. Viele Starts hintereinander heißen: Der Tunnel ist nicht stabil.',
  );

  String get mesh => _('Mesh', 'Mesh');
  String get node => _('Node id', 'Knoten-ID');
  String get address => _('Mesh address', 'Mesh-Adresse');
  String get members => _('Members', 'Mitglieder');
  String get forget => _('Remove from this phone', 'Von diesem Telefon entfernen');
  String get forgetText => _(
    'Deletes the keys and the mesh on this phone. On the NAS, an admin should also remove the member "%s".',
    'Löscht Schlüssel und Mesh auf diesem Telefon. Auf dem NAS sollte ein Admin zusätzlich das Mitglied „%s“ entfernen.',
  );
  String get removedTitle => _('Removed from the mesh', 'Aus dem Mesh entfernt');
  String get removedText => _(
    'A NAS admin removed this app. Remove it here too and pair again if needed.',
    'Ein NAS-Admin hat diese App entfernt. Entferne sie auch hier und kopple sie bei Bedarf neu.',
  );
}
