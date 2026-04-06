import Toybox.Math;
import Toybox.Lang;

//
// MGRSUtil — модуль конвертації координат WGS84 → MGRS.
//
// Алгоритм:
//   1. WGS84 lat/lon → UTM (easting, northing, zone)
//   2. UTM → MGRS (zone + lat-band + 100km-квадрат + цифри)
//
// Діапазон: 80°S – 84°N (стандартний MGRS).
// Полярні шапки (UPS) не підтримуються.
//
// Публічний API:
//   MGRSUtil.encode(latDeg, lonDeg, precision) as String
//     precision 1 = 10 км   (1 цифра)
//     precision 2 = 1 км    (2 цифри)
//     precision 3 = 100 м   (3 цифри)
//     precision 4 = 10 м    (4 цифри)
//     precision 5 = 1 м     (5 цифр)
//
module MGRSUtil {

    // ── WGS84 еліпсоїд ──────────────────────────────────────────────────
    // a  — велика піввісь (м)
    // e2 — перший ексцентриситет у квадраті (e² = 2f − f²)
    // e22— другий ексцентриситет у квадраті (e'² = e² / (1−e²))
    // k0 — масштабний коефіцієнт UTM
    const _A   = 6378137.0d;
    const _E2  = 0.00669437999014d;
    const _E22 = 0.00673949674228d;
    const _K0  = 0.9996d;

    // Коефіцієнти меридіанної дуги (для WGS84, попередньо обчислені)
    const _CM0 = 0.9983242984503243d;  // 1 − e²/4 − 3e⁴/64 − 5e⁶/256
    const _CM1 = 0.0025146330200488d;  // 3e²/8  + 3e⁴/32  + 45e⁶/1024
    const _CM2 = 0.0000026384056000d;  // 15e⁴/256 + 45e⁶/1024
    const _CM3 = 0.0000000034178000d;  // 35e⁶/3072

    // ── Таблиці букв MGRS ────────────────────────────────────────────────
    // 20 широтних зон (кожна 8°, крім X = 12°): C D E F G H J K L M N P Q R S T U V W X
    const _LAT_BANDS = "CDEFGHJKLMNPQRSTUVWX";

    // Колонкові букви (100 км у напрямку E): залежать від (zone − 1) % 3
    const _COL0 = "ABCDEFGH";   // (zone−1)%3 == 0
    const _COL1 = "JKLMNPQR";   // (zone−1)%3 == 1
    const _COL2 = "STUVWXYZ";   // (zone−1)%3 == 2

    // Рядкові букви (100 км у напрямку N): 20-буквений цикл, зсув для парних зон
    const _ROW_ODD  = "ABCDEFGHJKLMNPQRSTUV";  // непарні зони, починають із A
    const _ROW_EVEN = "FGHJKLMNPQRSTUVABCDE";  // парні зони, починають із F

    // ── Коефіцієнти зворотної проєкції (ряди Бесселя для WGS84) ─────────
    // e1 = (1 − √(1−e²)) / (1 + √(1−e²)) ≈ 0.001679
    const _E1   = 0.001679222d;
    const _E1_2 = 0.000002820d;
    const _E1_3 = 0.000000005d;

    // ── Мінімальне UTM-northing для кожного широтного поясу ─────────────
    // Використовується для визначення циклу 2000 км при декодуванні MGRS.
    // Для S-пів. (пояси C–M, індекси 0–9) — значення включають хибний
    // північ 10 000 000 м; для N-пів. (N–X, індекси 10–19) — від екватора.
    const _BAND_MIN_N as Array<Number> = [
         892000,   // C  −80°..−72°  (S-пів., з хибним північ 10M)
        1784000,   // D  −72°..−64°
        2676000,   // E  −64°..−56°
        3565000,   // F  −56°..−48°
        4452000,   // G  −48°..−40°
        5336000,   // H  −40°..−32°
        6218000,   // J  −32°..−24°
        7096000,   // K  −24°..−16°
        7973000,   // L  −16°.. −8°
        8850000,   // M   −8°..  0°
              0,   // N    0°..  8°  (N-пів.)
         888000,   // P    8°.. 16°
        1776000,   // Q   16°.. 24°
        2662000,   // R   24°.. 32°
        3544000,   // S   32°.. 40°
        4424000,   // T   40°.. 48°
        5305000,   // U   48°.. 56°  ← Україна
        6181000,   // V   56°.. 64°
        7054000,   // W   64°.. 72°
        7923000,   // X   72°.. 84°
    ] as Array<Number>;

    // ════════════════════════════════════════════════════════════════════
    // Публічні функції
    // ════════════════════════════════════════════════════════════════════

    //
    // Повертає рядок MGRS, наприклад «37U DB 12345 67890»
    // або порожній рядок, якщо координати поза діапазоном.
    //
    function encode(latDeg as Double, lonDeg as Double, precision as Number) as String {

        // Перевірка допустимого діапазону MGRS
        if (latDeg < -80.0d || latDeg >= 84.0d) {
            return (latDeg >= 84.0d) ? "Пн. полюс" : "UPS (поза MGRS)";
        }

        // ── 1. Зона UTM ──────────────────────────────────────────────
        var zone = _calcZone(latDeg, lonDeg);

        // ── 2. Широтна буква ─────────────────────────────────────────
        var bandChar = _calcLatBand(latDeg);

        // ── 3. WGS84 → UTM ───────────────────────────────────────────
        var utm = _toUTM(latDeg, lonDeg, zone);
        var easting  = utm[0];  // включає хибний схід 500000 м
        var northing = utm[1];  // від екватора; від'ємне для S-пів.

        // Додаємо хибний північ для Південної півкулі
        if (latDeg < 0.0d) {
            northing += 10000000.0d;
        }

        // Захист від виходу за межі через числові похибки
        if (easting < 100000.0d)    { easting  = 100000.0d; }
        if (easting > 899999.0d)    { easting  = 899999.0d; }
        if (northing < 0.0d)        { northing = 0.0d; }
        if (northing > 9999999.0d)  { northing = 9999999.0d; }

        // ── 4. Колонкова буква (100 км по E) ─────────────────────────
        var colChar = _calcColLetter(zone, easting);

        // ── 5. Рядкова буква (100 км по N) ───────────────────────────
        var rowChar = _calcRowLetter(zone, northing);

        // ── 6. Цифрова частина ────────────────────────────────────────
        // Залишок у межах 100-км квадрата (0–99999 м)
        var eRem = _dmod(easting,  100000.0d).toNumber();
        var nRem = _dmod(northing, 100000.0d).toNumber();

        // Скорочення відповідно до точності (1–5 цифр)
        var divisor = 1;
        for (var i = precision; i < 5; i++) { divisor *= 10; }
        var eNum = eRem / divisor;
        var nNum = nRem / divisor;

        var eStr = _zeroPad(eNum, precision);
        var nStr = _zeroPad(nNum, precision);

        return Lang.format("$1$$2$ $3$$4$ $5$ $6$",
                           [ zone, bandChar, colChar, rowChar, eStr, nStr ]);
    }

    //
    // toFields(lat, lon) — розкладає lat/lon у компоненти MGRS-поля.
    // Повертає Dictionary:
    //   "zone"    => Number  (1–60)
    //   "bandIdx" => Number  (0–19, індекс у _LAT_BANDS)
    //   "colIdx"  => Number  (0–7,  індекс у відповідному _COLx)
    //   "rowIdx"  => Number  (0–19, індекс у _ROW_ODD / _ROW_EVEN)
    //   "eHi"     => Number  (0–99, старші дві цифри 4-digit easting)
    //   "eLo"     => Number  (0–99, молодші дві цифри)
    //   "nHi"     => Number  (0–99, старші дві цифри 4-digit northing)
    //   "nLo"     => Number  (0–99, молодші дві цифри)
    //
    function toFields(latDeg as Double, lonDeg as Double) as Dictionary {
        var zone     = _calcZone(latDeg, lonDeg);
        var bandChar = _calcLatBand(latDeg);
        var bandIdx  = _strFind(_LAT_BANDS, bandChar);
        if (bandIdx < 0) { bandIdx = 16; }  // fallback → U

        var utm      = _toUTM(latDeg, lonDeg, zone);
        var easting  = utm[0];
        var northing = utm[1];
        if (latDeg < 0.0d) { northing += 10000000.0d; }

        if (easting  < 100000.0d) { easting  = 100000.0d; }
        if (easting  > 899999.0d) { easting  = 899999.0d; }
        if (northing < 0.0d)      { northing = 0.0d;       }
        if (northing > 9999999.0d){ northing = 9999999.0d; }

        var colIdx   = (easting / 100000.0d).toNumber() - 1;
        if (colIdx < 0) { colIdx = 0; }
        if (colIdx > 7) { colIdx = 7; }

        var rowChar  = _calcRowLetter(zone, northing);
        var rowSet   = (zone % 2 == 1) ? _ROW_ODD : _ROW_EVEN;
        var rowIdx   = _strFind(rowSet, rowChar);
        if (rowIdx < 0) { rowIdx = 0; }

        var eRem = _dmod(easting,  100000.0d).toNumber();
        var nRem = _dmod(northing, 100000.0d).toNumber();
        var e4   = eRem / 10;   // 4-digit при 10 м/крок
        var n4   = nRem / 10;

        return {
            "zone"    => zone,
            "bandIdx" => bandIdx,
            "colIdx"  => colIdx,
            "rowIdx"  => rowIdx,
            "eHi"     => e4 / 100,
            "eLo"     => e4 % 100,
            "nHi"     => n4 / 100,
            "nLo"     => n4 % 100
        } as Dictionary;
    }

    //
    // fromFields(...) — зворотне перетворення MGRS-компонентів → [lat, lon].
    // eHi, eLo — старші та молодші дві цифри 4-digit easting (10 м точність).
    // nHi, nLo — аналогічно для northing.
    // Повертає [latDeg, lonDeg] або [0, 0] при невалідних даних.
    //
    function fromFields(zone    as Number,
                        bandIdx as Number,
                        colIdx  as Number,
                        rowIdx  as Number,
                        eHi     as Number,
                        eLo     as Number,
                        nHi     as Number,
                        nLo     as Number) as Array<Double> {

        // ── UTM Easting ───────────────────────────────────────────────
        var e4       = eHi * 100 + eLo;  // 4-digit (0–9999)
        var easting  = ((colIdx + 1) * 100000 + e4 * 10).toDouble();

        // ── UTM Northing ──────────────────────────────────────────────
        var n4          = nHi * 100 + nLo;
        var row_base    = rowIdx * 100000;
        var min_north   = _BAND_MIN_N[bandIdx];
        var cycle       = min_north / 2000000;
        var north_cand  = row_base + cycle * 2000000;
        // Якщо кандидат занадто малий відносно мінімуму поясу — +1 цикл
        if (north_cand + 100000 < min_north) {
            north_cand += 2000000;
        }
        var northing = (north_cand + n4 * 10).toDouble();

        // S-пів.: видаляємо хибний північ
        if (bandIdx < 10) {
            northing -= 10000000.0d;
        }

        return _utmToLatLon(zone, easting, northing);
    }

    // ════════════════════════════════════════════════════════════════════
    // Внутрішні функції
    // ════════════════════════════════════════════════════════════════════

    // Номер UTM-зони (1–60) з урахуванням виняткових районів Норвегії/Шпіцбергена
    function _calcZone(latDeg as Double, lonDeg as Double) as Number {
        var z = ((lonDeg + 180.0d) / 6.0d).toNumber() + 1;

        // Зона 32V: Норвегія (56°–64°N, 3°–12°E)
        if (latDeg >= 56.0d && latDeg < 64.0d &&
            lonDeg >= 3.0d  && lonDeg < 12.0d) {
            return 32;
        }

        // Зони Шпіцбергена (72°–84°N)
        if (latDeg >= 72.0d && latDeg < 84.0d) {
            if      (lonDeg >=  0.0d && lonDeg <  9.0d)  { return 31; }
            else if (lonDeg >=  9.0d && lonDeg < 21.0d)  { return 33; }
            else if (lonDeg >= 21.0d && lonDeg < 33.0d)  { return 35; }
            else if (lonDeg >= 33.0d && lonDeg < 42.0d)  { return 37; }
        }

        return z;
    }

    // Широтна буква MGRS (C–X, без I та O)
    function _calcLatBand(latDeg as Double) as String {
        var idx = ((latDeg + 80.0d) / 8.0d).toNumber();
        if (idx < 0)  { idx = 0; }
        if (idx > 19) { idx = 19; }
        return _LAT_BANDS.substring(idx, idx + 1);
    }

    // WGS84 lat/lon → [easting, northing] у метрах (без хибного північ для S-пів.)
    function _toUTM(latDeg as Double, lonDeg as Double, zone as Number) as Array<Double> {
        var phi  = Math.toRadians(latDeg);
        var lam  = Math.toRadians(lonDeg);
        var lam0 = Math.toRadians((zone - 1) * 6.0d - 180.0d + 3.0d);  // центральний меридіан

        var sinP = Math.sin(phi);
        var cosP = Math.cos(phi);
        var tanP = Math.tan(phi);

        var N   = _A / Math.sqrt(1.0d - _E2 * sinP * sinP);
        var T   = tanP * tanP;
        var C   = _E22 * cosP * cosP;
        var Av  = cosP * (lam - lam0);

        // Меридіанна дуга від екватора
        var M = _A * (
            _CM0 * phi
          - _CM1 * Math.sin(2.0d * phi)
          + _CM2 * Math.sin(4.0d * phi)
          - _CM3 * Math.sin(6.0d * phi)
        );

        var A2 = Av * Av;
        var A3 = A2 * Av;
        var A4 = A3 * Av;
        var A5 = A4 * Av;
        var A6 = A5 * Av;
        var T2 = T * T;
        var C2 = C * C;

        // Схід (E)
        var x = _K0 * N * (
            Av
          + (1.0d - T + C) * A3 / 6.0d
          + (5.0d - 18.0d*T + T2 + 72.0d*C - 58.0d*_E22) * A5 / 120.0d
        );

        // Північ (N)
        var y = _K0 * (M + N * tanP * (
            A2 / 2.0d
          + (5.0d - T + 9.0d*C + 4.0d*C2) * A4 / 24.0d
          + (61.0d - 58.0d*T + T2 + 600.0d*C - 330.0d*_E22) * A6 / 720.0d
        ));

        x += 500000.0d;  // хибний схід

        return [ x, y ] as Array<Double>;
    }

    // Колонкова буква 100-км квадрата
    function _calcColLetter(zone as Number, easting as Double) as String {
        // Easting 100001–900000 → блок 1–9 → індекс 0–7 (8 можливих букв)
        var col = (easting / 100000.0d).toNumber() - 1;
        if (col < 0) { col = 0; }
        if (col > 7) { col = 7; }
        var colSet = ((zone - 1) % 3 == 0) ? _COL0
                   : ((zone - 1) % 3 == 1) ? _COL1
                   : _COL2;
        return colSet.substring(col, col + 1);
    }

    // Рядкова буква 100-км квадрата (20-буквений цикл на 2000 км)
    function _calcRowLetter(zone as Number, northing as Double) as String {
        var row = (northing / 100000.0d).toNumber() % 20;
        if (row < 0) { row = 0; }
        var rowSet = (zone % 2 == 1) ? _ROW_ODD : _ROW_EVEN;
        return rowSet.substring(row, row + 1);
    }

    // Залишок від ділення двох Double (замінює % для Double)
    function _dmod(a as Double, b as Double) as Double {
        return a - b * Math.floor(a / b);
    }

    //
    // _utmToLatLon — зворотна конформна проєкція Меркатора (UTM → WGS84).
    // Формули за серіями Краруна–Томпсона–Геймера.
    //
    function _utmToLatLon(zone as Number, easting as Double, northing as Double) as Array<Double> {
        var lam0 = Math.toRadians((zone - 1) * 6.0d - 180.0d + 3.0d);
        var x    = easting - 500000.0d;   // видаляємо хибний схід
        var y    = northing;

        // ── Крокова широта (footpoint latitude) ───────────────────────
        var M    = y / _K0;
        var mu   = M / (_A * _CM0);

        var phi1 = mu
            + (1.5d  * _E1  - 27.0d/32.0d * _E1_3) * Math.sin(2.0d * mu)
            + (21.0d/16.0d  * _E1_2)                * Math.sin(4.0d * mu)
            + (151.0d/96.0d * _E1_3)                * Math.sin(6.0d * mu);

        var sinP = Math.sin(phi1);
        var cosP = Math.cos(phi1);
        var tanP = Math.tan(phi1);

        var denom  = 1.0d - _E2 * sinP * sinP;
        var sqrtD  = Math.sqrt(denom);
        var N1     = _A / sqrtD;
        var T1     = tanP * tanP;
        var C1     = _E22 * cosP * cosP;
        var R1     = _A * (1.0d - _E2) / (sqrtD * denom);   // a(1−e²)/denom^1.5
        var D      = x / (N1 * _K0);

        var D2 = D * D;   var D3 = D2 * D;
        var D4 = D3 * D;  var D5 = D4 * D;  var D6 = D5 * D;
        var T2 = T1 * T1; var C2 = C1 * C1;

        // ── Широта ────────────────────────────────────────────────────
        var latRad = phi1 - (N1 * tanP / R1) * (
            D2 / 2.0d
          - (5.0d + 3.0d*T1 + 10.0d*C1 - 4.0d*C2 - 9.0d*_E22)          * D4 / 24.0d
          + (61.0d + 90.0d*T1 + 298.0d*C1 + 45.0d*T2 - 252.0d*_E22 - 3.0d*C2) * D6 / 720.0d
        );

        // ── Довгота ───────────────────────────────────────────────────
        var lonRad = lam0 + (
            D
          - (1.0d + 2.0d*T1 + C1)                                         * D3 / 6.0d
          + (5.0d - 2.0d*C1 + 28.0d*T1 - 3.0d*C2 + 8.0d*_E22 + 24.0d*T2) * D5 / 120.0d
        ) / cosP;

        return [ Math.toDegrees(latRad), Math.toDegrees(lonRad) ] as Array<Double>;
    }

    // Позиція символу ch у рядку str (або -1)
    function _strFind(str as String, ch as String) as Number {
        for (var i = 0; i < str.length(); i++) {
            if (str.substring(i, i + 1).equals(ch)) { return i; }
        }
        return -1;
    }

    // Доповнення нулями зліва до потрібної кількості цифр
    function _zeroPad(n as Number, digits as Number) as String {
        var s = n.format("%d");
        while (s.length() < digits) {
            s = "0" + s;
        }
        // Обрізаємо якщо довше (не має бути, але на всяк випадок)
        if (s.length() > digits) {
            s = s.substring(s.length() - digits, s.length());
        }
        return s;
    }
}
