<?php
/*
 * Berufe der Gilde direkt von Blizzard holen – ohne Addon-Export, ohne Einfügen, ohne Mac-App.
 *
 * Blizzards Web-API kennt für WoW Forever jede Figur mit ihren Berufen und allen bekannten Rezepten
 * (Stand: letztes Ausloggen der Figur). Dieses Skript holt die Gildenliste, dann die Berufe jeder
 * Figur, und schreibt alles in eine JSON-Datei, die berufe.php lesen kann.
 *
 * Einrichten (einmal, fünf Minuten):
 *   1. Auf https://develop.battle.net/access/clients einen eigenen API-Client anlegen
 *      (Name egal, Redirect-URL egal, z. B. https://www.gilde-elternabend.de).
 *   2. Client-ID und Secret als Umgebungsvariablen BNET_CLIENT_ID / BNET_CLIENT_SECRET setzen
 *      oder unten in KONFIG eintragen. Das Secret gehört nicht ins Git.
 *   3. Per Cron stündlich aufrufen:   php /pfad/berufe-api.php
 *      oder im Browser:               berufe-api.php?neu=GEHEIMWORT   (siehe KONFIG['webSchluessel'])
 *
 * Ergebnis: berufe-api.json (siehe Ende der Datei). Ein Lauf für ~250 Figuren dauert etwa 15 Sekunden, der allererste (Rezeptnamen holen) gut 30.
 * Rezeptnamen (deutsch) werden einmal geholt und in berufe-api-rezepte.json gemerkt.
 *
 * Läuft mit PHP 7.4 und neuer, braucht nur die curl-Erweiterung.
 */

const KONFIG = [
    'clientId'     => '',                 // oder Umgebungsvariable BNET_CLIENT_ID
    'clientSecret' => '',                 // oder Umgebungsvariable BNET_CLIENT_SECRET
    'gilde'        => 'elternabend',      // so wie im Gildenlink, klein
    'region'       => 'eu',
    'sprache'      => 'de_DE',
    'ordner'       => __DIR__,            // hier landen Token, Rezept-Cache und Ergebnis
    'parallel'     => 8,                  // gleichzeitige Abrufe; mehr löst bei Blizzard die Bremse aus
    'webSchluessel'=> '',                 // leer = Aufruf im Browser nur lesend
];

// Forever hat eigene Namensräume; ohne Realm im Pfad.
const NS_PROFIL   = 'profile-forever-';
const NS_STATISCH = 'static-forever-';

// ---------------------------------------------------------------------------------------------------

function konfig(string $k): string
{
    $env = ['clientId' => 'BNET_CLIENT_ID', 'clientSecret' => 'BNET_CLIENT_SECRET'][$k] ?? null;
    if ($env && getenv($env)) return getenv($env);
    return (string) KONFIG[$k];
}

function datei(string $name): string
{
    return rtrim(KONFIG['ordner'], '/') . '/' . $name;
}

function jsonLesen(string $name, $sonst)
{
    $p = datei($name);
    if (!is_file($p)) return $sonst;
    $d = json_decode((string) file_get_contents($p), true);
    return is_array($d) ? $d : $sonst;
}

function jsonSchreiben(string $name, $daten): void
{
    $p = datei($name);
    $tmp = $p . '.tmp';
    file_put_contents($tmp, json_encode($daten, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES | JSON_PRETTY_PRINT));
    rename($tmp, $p); // nie eine halbe Datei für berufe.php
}

/** App-Token (Client Credentials), 24 h gültig, wird zwischengespeichert. */
function token(): string
{
    $t = jsonLesen('berufe-api-token.json', []);
    if (($t['bis'] ?? 0) > time() + 300) return $t['token'];

    $id = konfig('clientId');
    $secret = konfig('clientSecret');
    if ($id === '' || $secret === '') throw new RuntimeException('BNET_CLIENT_ID / BNET_CLIENT_SECRET fehlen.');

    $ch = curl_init('https://oauth.battle.net/token');
    curl_setopt_array($ch, [
        CURLOPT_POST => true,
        CURLOPT_POSTFIELDS => 'grant_type=client_credentials',
        CURLOPT_USERPWD => $id . ':' . $secret,
        CURLOPT_RETURNTRANSFER => true,
        CURLOPT_TIMEOUT => 20,
    ]);
    $antwort = json_decode((string) curl_exec($ch), true);
    $code = curl_getinfo($ch, CURLINFO_HTTP_CODE);
    curl_close($ch);
    if ($code !== 200 || empty($antwort['access_token'])) throw new RuntimeException("Token: HTTP $code");

    jsonSchreiben('berufe-api-token.json', ['token' => $antwort['access_token'], 'bis' => time() + (int) $antwort['expires_in']]);
    @chmod(datei('berufe-api-token.json'), 0600);
    return $antwort['access_token'];
}

function url(string $pfad, string $ns): string
{
    $r = KONFIG['region'];
    $trenner = strpos($pfad, '?') === false ? '?' : '&';
    return "https://$r.api.blizzard.com$pfad{$trenner}namespace=$ns$r&locale=" . KONFIG['sprache'];
}

/**
 * Viele GETs parallel. Gibt [schlüssel => [code, daten]] zurück.
 * Bei 429 (zu schnell) wird einmal kurz gewartet und neu versucht.
 */
function holeAlle(array $urls, string $token): array
{
    $ergebnis = [];
    $offen = $urls;
    for ($versuch = 0; $versuch < 3 && $offen; $versuch++) {
        if ($versuch) sleep(2);
        $nochmal = [];
        foreach (array_chunk($offen, max(1, KONFIG['parallel']), true) as $stapel) {
            $mh = curl_multi_init();
            $griffe = [];
            foreach ($stapel as $k => $u) {
                $ch = curl_init($u);
                curl_setopt_array($ch, [
                    CURLOPT_HTTPHEADER => ['Authorization: Bearer ' . $token],
                    CURLOPT_RETURNTRANSFER => true,
                    CURLOPT_TIMEOUT => 20,
                    CURLOPT_ENCODING => '',
                ]);
                curl_multi_add_handle($mh, $ch);
                $griffe[$k] = $ch;
            }
            do {
                $status = curl_multi_exec($mh, $laufend);
                if ($laufend) curl_multi_select($mh, 1.0);
            } while ($laufend && $status === CURLM_OK);
            foreach ($griffe as $k => $ch) {
                $code = curl_getinfo($ch, CURLINFO_HTTP_CODE);
                if ($code === 429 || $code === 0 || $code >= 500) $nochmal[$k] = $stapel[$k];
                else $ergebnis[$k] = [$code, json_decode((string) curl_multi_getcontent($ch), true)];
                curl_multi_remove_handle($mh, $ch);
                curl_close($ch);
            }
            curl_multi_close($mh);
        }
        $offen = $nochmal;
    }
    foreach ($offen as $k => $_) $ergebnis[$k] = [0, null];
    return $ergebnis;
}

function hole(string $url, string $token): array
{
    return holeAlle(['x' => $url], $token)['x'];
}

// ---------------------------------------------------------------------------------------------------

function aktualisieren(): array
{
    $start = microtime(true);
    $token = token();

    // 1. Gildenliste
    [$code, $liste] = hole(url('/data/wow/guild/' . rawurlencode(KONFIG['gilde']) . '/roster', NS_PROFIL), $token);
    if ($code !== 200) throw new RuntimeException("Gildenliste: HTTP $code");

    // 2. Klassen- und Berufsnamen auf Deutsch (klein, jedes Mal frisch)
    [, $klassenIndex] = hole(url('/data/wow/playable-class/index', NS_STATISCH), $token);
    $klassen = [];
    foreach ($klassenIndex['classes'] ?? [] as $k) $klassen[$k['id']] = $k['name'];

    // 3. Berufe jeder Figur, parallel
    $figuren = [];
    $urls = [];
    foreach ($liste['members'] as $m) {
        $c = $m['character'];
        if (!preg_match('#/character/([^/?]+)#', $c['key']['href'], $treffer)) continue;
        $slug = $treffer[1];
        $figuren[$slug] = [
            'name'   => trim($c['name'] . ' ' . ($c['surname'] ?? '')),
            'stufe'  => $c['level'],
            'klasse' => $klassen[$c['playable_class']['id']] ?? null,
            'rang'   => $m['rank'],
            'berufe' => [],
        ];
        $urls[$slug] = url("/profile/wow/character/$slug/professions", NS_PROFIL);
    }
    $antworten = holeAlle($urls, $token);

    // 4. Berufe auswerten; Rezept-IDs sammeln
    $rezeptIds = [];
    $ohneDaten = 0;
    foreach ($antworten as $slug => [$code, $d]) {
        if ($code !== 200) { $ohneDaten++; continue; } // 404: Blizzard kennt die Figur (noch) nicht
        foreach (['primaries', 'secondaries'] as $gruppe) {
            foreach ($d[$gruppe] ?? [] as $p) {
                foreach ($p['tiers'] ?? [$p] as $t) {
                    $ids = array_map(function ($r) { return $r['id']; }, $t['known_recipes'] ?? []);
                    foreach ($ids as $id) $rezeptIds[$id] = true;
                    $figuren[$slug]['berufe'][] = [
                        'id'      => $p['profession']['id'],
                        'beruf'   => $p['profession']['name'],
                        'stufe'   => $t['skill_points'] ?? null,
                        'max'     => $t['max_skill_points'] ?? null,
                        'rezepte' => $ids,
                    ];
                }
            }
        }
    }

    // 5. Rezepte, die wir noch nicht kennen: deutscher Name + hergestellter Gegenstand. Ändert sich nie.
    $rezepte = jsonLesen('berufe-api-rezepte.json', []);
    $fehlend = [];
    foreach (array_keys($rezeptIds) as $id) {
        if (!isset($rezepte[$id])) $fehlend[$id] = url("/data/wow/recipe/$id", NS_STATISCH);
    }
    foreach (holeAlle($fehlend, $token) as $id => [$code, $r]) {
        if ($code !== 200) continue;
        $rezepte[$id] = [
            'name'      => $r['name'],
            'gegenstand'=> $r['crafted_item']['id'] ?? null,
            'material'  => array_map(function ($x) {
                return [$x['reagent']['id'], $x['reagent']['name'], $x['quantity']];
            }, $r['reagents'] ?? []),
        ];
    }
    if ($fehlend) jsonSchreiben('berufe-api-rezepte.json', $rezepte);

    // Berufsnamen auf Deutsch kommen aus der Berufe-Antwort nicht immer; Profilnamen ggf. englisch.
    [, $berufIndex] = hole(url('/data/wow/profession/index', NS_STATISCH), $token);
    $berufe = [];
    foreach ($berufIndex['professions'] ?? [] as $b) $berufe[$b['id']] = $b['name'];
    foreach ($figuren as &$f) {
        foreach ($f['berufe'] as &$b) $b['beruf'] = $berufe[$b['id']] ?? $b['beruf'];
    }
    unset($f, $b);

    $ergebnis = [
        'stand'     => date('c'),
        'quelle'    => 'Battle.net-API (Stand jeder Figur: letztes Ausloggen)',
        'figuren'   => array_values($figuren),
        'rezepte'   => $rezepte,
        'statistik' => [
            'figuren'      => count($figuren),
            'ohneDaten'    => $ohneDaten,
            'neueRezepte'  => count($fehlend),
            'sekunden'     => round(microtime(true) - $start, 1),
        ],
    ];
    jsonSchreiben('berufe-api.json', $ergebnis);
    return $ergebnis;
}

// ---------------------------------------------------------------------------------------------------

if (PHP_SAPI === 'cli') {
    try {
        $e = aktualisieren();
        $s = $e['statistik'];
        $mitBeruf = count(array_filter($e['figuren'], function ($f) { return $f['berufe']; }));
        echo "{$s['figuren']} Figuren, $mitBeruf mit Berufen, {$s['ohneDaten']} ohne Daten bei Blizzard, "
            . count($e['rezepte']) . " Rezepte bekannt ({$s['neueRezepte']} neu), {$s['sekunden']} s\n";
    } catch (Throwable $t) {
        fwrite(STDERR, 'Fehler: ' . $t->getMessage() . "\n");
        exit(1);
    }
    return;
}

// Im Browser: ohne Schlüssel nur die letzte Datei ausliefern, mit ?neu=SCHLÜSSEL neu holen.
header('Content-Type: application/json; charset=utf-8');
$schluessel = KONFIG['webSchluessel'];
if ($schluessel !== '' && hash_equals($schluessel, (string) ($_GET['neu'] ?? ''))) {
    try {
        aktualisieren();
    } catch (Throwable $t) {
        http_response_code(502);
        echo json_encode(['fehler' => $t->getMessage()], JSON_UNESCAPED_UNICODE);
        return;
    }
}
$p = datei('berufe-api.json');
if (!is_file($p)) { http_response_code(404); echo '{"fehler":"Noch nicht geholt."}'; return; }
readfile($p);

/*
 * Form von berufe-api.json:
 * {
 *   "stand": "2026-11-14T15:00:00+01:00",
 *   "figuren": [
 *     { "name": "Fox Rabenfels", "stufe": 35, "klasse": "Krieger", "rang": 4,
 *       "berufe": [ { "id": 164, "beruf": "Schmiedekunst", "stufe": 165, "max": 225, "rezepte": [2660, ...] } ] }
 *   ],
 *   "rezepte": { "2660": { "name": "Rauer Wetzstein", "gegenstand": 2862,
 *                          "material": [[2835, "Grober Stein", 1]] } }
 * }
 */
