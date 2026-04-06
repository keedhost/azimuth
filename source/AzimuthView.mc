import Toybox.Graphics;
import Toybox.WatchUi;
import Toybox.Position;
import Toybox.Sensor;
import Toybox.Math;
import Toybox.Lang;
import Toybox.Application;
import Toybox.System;

//
// Головний екран застосунку.
//
// Кнопка SELECT перемикає два режими нижньої панелі:
//   MODE_AZIMUTH — назва обʼєкта, прямий/зворотній азимут, відстань
//   MODE_MGRS    — MGRS поточної позиції + MGRS цілі + азимути
//
// Компасне коло та стрілки відображаються в обох режимах.
//
class AzimuthView extends WatchUi.View {

    // ── Режими нижньої панелі ─────────────────────────────────────────
    const MODE_AZIMUTH = 0;
    const MODE_MGRS    = 1;

    // ── Вбудовані точки (незмінні) ───────────────────────────────────
    private const PRESET_LIST as Array< Dictionary > = [
        { "name" => "Київ",          "lat" => 50.4501d, "lon" => 30.5234d },
        { "name" => "Суми",          "lat" => 50.9077d, "lon" => 34.7981d },
        { "name" => "Ізюм",          "lat" => 49.2077d, "lon" => 37.2609d },
        { "name" => "Краматорськ",   "lat" => 48.7239d, "lon" => 37.5878d },
        { "name" => "Костянтинівка", "lat" => 48.5299d, "lon" => 37.7108d },
        { "name" => "Гуляй-Поле",   "lat" => 47.6616d, "lon" => 36.2685d },
        { "name" => "Нікополь",      "lat" => 47.5724d, "lon" => 34.3998d },
        { "name" => "Херсон",        "lat" => 46.6354d, "lon" => 32.6169d },
    ] as Array< Dictionary >;

    // ── Об'єднаний список (preset + custom), завжди актуальний ───────
    // Кастомні точки позначені "custom" => true
    var TARGET_LIST as Array< Dictionary > = [] as Array< Dictionary >;

    private const PRESET_COUNT as Number = 8;
    private const EARTH_R      as Double = 6371.0d;

    // ── Поточний стан GPS/Compass ─────────────────────────────────────
    private var _currentLat  as Double or Null = null;
    private var _currentLon  as Double or Null = null;
    private var _heading     as Double = 0.0d;
    private var _hasGps      as Boolean = false;
    private var _hasCompass  as Boolean = false;
    private var _gpsAccuracy as Number = 0;

    // ── Вибраний обʼєкт та режим ─────────────────────────────────────
    var targetIndex  as Number = 0;
    var displayMode  as Number = 1;  // MODE_AZIMUTH або MODE_MGRS (за замовчуванням MGRS)

    // ── Розраховані значення (кеш) ────────────────────────────────────
    private var _targetAzimuth  as Double = 0.0d;
    private var _reverseAzimuth as Double = 0.0d;
    private var _distanceKm     as Double = 0.0d;
    private var _myMgrs         as String = "---";
    private var _tgtMgrs        as String = "---";

    // ── Геометрія екрана ──────────────────────────────────────────────
    private var _cx as Number = 100;
    private var _cy as Number = 100;
    private var _r  as Number = 55;
    private var _w  as Number = 200;
    private var _h  as Number = 200;

    function initialize() {
        View.initialize();
        _rebuildTargetList();

        var saved = Application.Properties.getValue("targetIndex");
        if (saved instanceof Lang.Number) {
            targetIndex = saved as Number;
            if (targetIndex < 0 || targetIndex >= TARGET_LIST.size()) {
                targetIndex = 0;
            }
        }
        _updateTargetMgrs();
    }

    function onLayout(dc as Graphics.Dc) as Void {
        _w  = dc.getWidth();
        _h  = dc.getHeight();
        _cx = _w / 2;
        _r  = (_w < _h ? _w : _h) * 35 / 100;
        _cy = _r + (_h * 8 / 100);

        Position.enableLocationEvents(
            Position.LOCATION_CONTINUOUS,
            method(:onPosition)
        );
        Sensor.setEnabledSensors([ Sensor.SENSOR_COMPASS ] as Array<Sensor.SensorType>);
        Sensor.enableSensorEvents(method(:onSensor));
    }

    // ── Сенсорні колбеки ─────────────────────────────────────────────

    function onPosition(info as Position.Info) as Void {
        _gpsAccuracy = info.accuracy;
        if (info.accuracy >= Position.QUALITY_USABLE) {
            var loc = info.position.toDegrees();
            _currentLat = loc[0] as Double;
            _currentLon = loc[1] as Double;
            _hasGps = true;
            _recalculate();
        }
        WatchUi.requestUpdate();
    }

    function onSensor(sensorInfo as Sensor.Info) as Void {
        if ((sensorInfo has :heading) && sensorInfo.heading != null) {
            _heading    = sensorInfo.heading as Double;
            _hasCompass = true;
        }
        WatchUi.requestUpdate();
    }

    // ── Математика ───────────────────────────────────────────────────

    private function _bearing(lat1 as Double, lon1 as Double,
                               lat2 as Double, lon2 as Double) as Double {
        var φ1   = Math.toRadians(lat1);
        var φ2   = Math.toRadians(lat2);
        var dλ   = Math.toRadians(lon2 - lon1);
        var y    = Math.sin(dλ) * Math.cos(φ2);
        var x    = Math.cos(φ1) * Math.sin(φ2)
                 - Math.sin(φ1) * Math.cos(φ2) * Math.cos(dλ);
        return (Math.toDegrees(Math.atan2(y, x)) + 360.0d) % 360.0d;
    }

    private function _haversine(lat1 as Double, lon1 as Double,
                                 lat2 as Double, lon2 as Double) as Double {
        var φ1 = Math.toRadians(lat1);
        var φ2 = Math.toRadians(lat2);
        var dφ = Math.toRadians(lat2 - lat1);
        var dλ = Math.toRadians(lon2 - lon1);
        var a  = Math.sin(dφ/2.0d)*Math.sin(dφ/2.0d) +
                 Math.cos(φ1)*Math.cos(φ2)*Math.sin(dλ/2.0d)*Math.sin(dλ/2.0d);
        return EARTH_R * 2.0d * Math.atan2(Math.sqrt(a), Math.sqrt(1.0d - a));
    }

    // Перераховує всі кешовані значення при оновленні позиції
    private function _recalculate() as Void {
        if (_currentLat == null || _currentLon == null) { return; }
        var lat = _currentLat as Double;
        var lon = _currentLon as Double;
        var tgt = TARGET_LIST[targetIndex];

        _targetAzimuth  = _bearing(lat, lon, tgt["lat"] as Double, tgt["lon"] as Double);
        _reverseAzimuth = (_targetAzimuth + 180.0d) % 360.0d;
        _distanceKm     = _haversine(lat, lon, tgt["lat"] as Double, tgt["lon"] as Double);

        // MGRS поточної позиції (точність 5 = 1 м)
        _myMgrs = MGRSUtil.encode(lat, lon, 5);
    }

    // Оновлює MGRS цілі (викликається при зміні targetIndex)
    private function _updateTargetMgrs() as Void {
        var tgt = TARGET_LIST[targetIndex];
        _tgtMgrs = MGRSUtil.encode(tgt["lat"] as Double, tgt["lon"] as Double, 5);
    }

    // ── Публічні методи, які викликає Delegate ────────────────────────

    function selectTarget(index as Number) as Void {
        targetIndex = index;
        Application.Properties.setValue("targetIndex", index);
        _updateTargetMgrs();
        _recalculate();
        WatchUi.requestUpdate();
    }

    function toggleDisplayMode() as Void {
        displayMode = (displayMode == MODE_AZIMUTH) ? MODE_MGRS : MODE_AZIMUTH;
        WatchUi.requestUpdate();
    }

    // ── Доступ до поточної позиції (для AddObjectDelegate) ───────────

    function getCurrentLat() as Double or Null { return _currentLat; }
    function getCurrentLon() as Double or Null { return _currentLon; }

    // ── Управління кастомними точками ─────────────────────────────────

    // Перебудовує TARGET_LIST = PRESET_LIST + кастомні з CustomObjects
    function _rebuildTargetList() as Void {
        var combined = [] as Array< Dictionary >;
        for (var i = 0; i < PRESET_LIST.size(); i++) {
            combined.add(PRESET_LIST[i]);
        }
        var customs = CustomObjects.load();
        for (var i = 0; i < customs.size(); i++) {
            var c = customs[i];
            combined.add({
                "name"   => c["name"],
                "lat"    => c["lat"],
                "lon"    => c["lon"],
                "custom" => true
            } as Dictionary);
        }
        TARGET_LIST = combined;
    }

    // Додає кастомну точку, перебудовує список, вибирає нову точку
    function addCustomObject(name as String, lat as Double, lon as Double) as Void {
        CustomObjects.add(name, lat, lon);
        _rebuildTargetList();
        // Автоматично переключаємось на щойно додану точку
        selectTarget(TARGET_LIST.size() - 1);
    }

    // Видаляє кастомну точку за її індексом у підсписку кастомних (0-based)
    function deleteCustomObject(customIndex as Number) as Void {
        var wasSelected = (targetIndex == PRESET_COUNT + customIndex);
        CustomObjects.remove(customIndex);
        _rebuildTargetList();
        // Якщо видалили вибрану — переходимо на першу вбудовану
        if (wasSelected || targetIndex >= TARGET_LIST.size()) {
            selectTarget(0);
        } else {
            // Якщо індекс виявився зсунутим після видалення
            if (targetIndex > PRESET_COUNT + customIndex) {
                targetIndex--;
            }
            Application.Properties.setValue("targetIndex", targetIndex);
            _updateTargetMgrs();
            _recalculate();
            WatchUi.requestUpdate();
        }
    }

    // Повертає кількість кастомних точок у TARGET_LIST
    function customCount() as Number {
        return TARGET_LIST.size() - PRESET_COUNT;
    }

    // ── Малювання ────────────────────────────────────────────────────

    private function _drawArrow(dc  as Graphics.Dc,
                                 cx  as Number, cy as Number,
                                 ang as Double,
                                 len as Number,
                                 col as Number) as Void {
        var rad  = Math.toRadians(ang);
        var sinA = Math.sin(rad);
        var cosA = Math.cos(rad);

        var tipX  = cx + (len * sinA).toNumber();
        var tipY  = cy - (len * cosA).toNumber();
        var tail  = len * 40 / 100;
        var tailX = cx - (tail * sinA).toNumber();
        var tailY = cy + (tail * cosA).toNumber();

        var wing  = len * 28 / 100;
        var wa1   = Math.toRadians(ang + 145.0d);
        var wa2   = Math.toRadians(ang - 145.0d);
        var w1x   = tipX + (wing * Math.sin(wa1)).toNumber();
        var w1y   = tipY - (wing * Math.cos(wa1)).toNumber();
        var w2x   = tipX + (wing * Math.sin(wa2)).toNumber();
        var w2y   = tipY - (wing * Math.cos(wa2)).toNumber();

        dc.setColor(col, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(3);
        dc.drawLine(tailX, tailY, tipX, tipY);
        dc.drawLine(tipX, tipY, w1x, w1y);
        dc.drawLine(tipX, tipY, w2x, w2y);
        dc.setPenWidth(1);
        dc.fillCircle(cx, cy, 5);
    }

    private function _text(dc      as Graphics.Dc,
                            x       as Number, y as Number,
                            font    as Graphics.FontDefinition,
                            str     as String,
                            justify as Number,
                            color   as Number) as Void {
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_TRANSPARENT);
        dc.drawText(x + 1, y + 1, font, str, justify);
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        dc.drawText(x, y, font, str, justify);
    }

    // Компасна троянда (верхня частина екрана) — однакова для обох режимів
    private function _drawCompass(dc as Graphics.Dc) as Void {
        // Зовнішнє кільце
        dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(2);
        dc.drawCircle(_cx, _cy, _r);

        // Кардинальні напрямки
        var cardinals = [
            ["N", 0.0d], ["E", 90.0d], ["S", 180.0d], ["W", 270.0d]
        ] as Array< Array >;
        for (var i = 0; i < cardinals.size(); i++) {
            var lbl = cardinals[i][0] as String;
            var brg = cardinals[i][1] as Double;
            var sa  = (brg - _heading + 360.0d) % 360.0d;
            var rr  = Math.toRadians(sa);
            var lx  = _cx + ((_r - 12) * Math.sin(rr)).toNumber();
            var ly  = _cy - ((_r - 12) * Math.cos(rr)).toNumber();
            _text(dc, lx, ly - 8, Graphics.FONT_XTINY, lbl,
                  Graphics.TEXT_JUSTIFY_CENTER,
                  lbl.equals("N") ? Graphics.COLOR_RED : Graphics.COLOR_LT_GRAY);
        }

        // Риски кожні 30°
        dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(1);
        for (var t = 0; t < 12; t++) {
            var sa   = (t * 30.0d - _heading + 360.0d) % 360.0d;
            var rr   = Math.toRadians(sa);
            var sinR = Math.sin(rr);
            var cosR = Math.cos(rr);
            var inn  = (t % 3 == 0) ? _r - 8 : _r - 5;
            dc.drawLine(
                _cx + (inn * sinR).toNumber(), _cy - (inn * cosR).toNumber(),
                _cx + (_r  * sinR).toNumber(), _cy - (_r  * cosR).toNumber()
            );
        }

        if (!_hasCompass) {
            _text(dc, _cx, _cy - 10, Graphics.FONT_SMALL,
                  L.s(Rez.Strings.MsgCompass), Graphics.TEXT_JUSTIFY_CENTER, Graphics.COLOR_YELLOW);
            return;
        }

        // Синя стрілка → Географічний Пн. полюс (завжди 0°)
        var northSA = (0.0d - _heading + 360.0d) % 360.0d;
        _drawArrow(dc, _cx, _cy, northSA, _r - 10, Graphics.COLOR_BLUE);

        if (_hasGps) {
            // Червона стрілка → Обʼєкт природи
            var tgtSA = (_targetAzimuth - _heading + 360.0d) % 360.0d;
            _drawArrow(dc, _cx, _cy, tgtSA, _r - 10, Graphics.COLOR_RED);
        }
    }

    // Легенда (верхній лівий кут)
    private function _drawLegend(dc as Graphics.Dc) as Void {
        dc.setColor(Graphics.COLOR_BLUE, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(10, 10, 5);
        _text(dc, 20, 3, Graphics.FONT_XTINY,
              L.s(Rez.Strings.LabelNorthPole), Graphics.TEXT_JUSTIFY_LEFT, Graphics.COLOR_BLUE);

        dc.setColor(Graphics.COLOR_RED, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(10, 24, 5);
        _text(dc, 20, 17, Graphics.FONT_XTINY,
              L.s(Rez.Strings.LabelObject), Graphics.TEXT_JUSTIFY_LEFT, Graphics.COLOR_RED);
    }

    // Індикатор активного режиму (верхній правий кут)
    private function _drawModeIndicator(dc as Graphics.Dc) as Void {
        var modeStr = (displayMode == MODE_MGRS) ? "MGRS" : "AZ";
        var color   = (displayMode == MODE_MGRS) ? Graphics.COLOR_ORANGE : Graphics.COLOR_LT_GRAY;
        _text(dc, _w - 4, 3, Graphics.FONT_XTINY,
              modeStr, Graphics.TEXT_JUSTIFY_RIGHT, color);
    }

    // ── Нижня панель: режим АЗИМУТ ────────────────────────────────────
    private function _drawAzimuthPanel(dc as Graphics.Dc) as Void {
        var infoY = _cy + _r + 6;
        var lineH = _h * 13 / 100;
        var tgt   = TARGET_LIST[targetIndex];

        _text(dc, _cx, infoY, Graphics.FONT_XTINY,
              tgt["name"] as String, Graphics.TEXT_JUSTIFY_CENTER, Graphics.COLOR_RED);
        infoY += lineH;

        if (_hasGps) {
            _text(dc, 8, infoY, Graphics.FONT_XTINY,
                  L.s(Rez.Strings.LabelDirAz), Graphics.TEXT_JUSTIFY_LEFT, Graphics.COLOR_LT_GRAY);
            _text(dc, _w - 8, infoY, Graphics.FONT_XTINY,
                  Lang.format("$1$°", [ _targetAzimuth.format("%.1f") ]),
                  Graphics.TEXT_JUSTIFY_RIGHT, Graphics.COLOR_RED);
            infoY += lineH;

            _text(dc, 8, infoY, Graphics.FONT_XTINY,
                  L.s(Rez.Strings.LabelRevAz), Graphics.TEXT_JUSTIFY_LEFT, Graphics.COLOR_LT_GRAY);
            _text(dc, _w - 8, infoY, Graphics.FONT_XTINY,
                  Lang.format("$1$°", [ _reverseAzimuth.format("%.1f") ]),
                  Graphics.TEXT_JUSTIFY_RIGHT, Graphics.COLOR_WHITE);
            infoY += lineH;

            var distStr = _distanceKm >= 1000.0d
                ? Lang.format("$1$ $2$", [ (_distanceKm / 1000.0d).format("%.1f"), L.s(Rez.Strings.SuffixThousandKm) ])
                : Lang.format("$1$ $2$", [ _distanceKm.format("%.0f"),              L.s(Rez.Strings.SuffixKm) ]);
            _text(dc, _cx, infoY, Graphics.FONT_XTINY,
                  distStr, Graphics.TEXT_JUSTIFY_CENTER, Graphics.COLOR_GREEN);
        } else {
            var msg = (_gpsAccuracy == Position.QUALITY_NOT_AVAILABLE)
                ? L.s(Rez.Strings.MsgNoGps)
                : L.s(Rez.Strings.MsgWaitGps);
            _text(dc, _cx, infoY, Graphics.FONT_XTINY,
                  msg, Graphics.TEXT_JUSTIFY_CENTER, Graphics.COLOR_YELLOW);
        }
    }

    // ── Нижня панель: режим MGRS ──────────────────────────────────────
    private function _drawMGRSPanel(dc as Graphics.Dc) as Void {
        var infoY = _cy + _r + 4;
        var lineH = _h * 12 / 100;

        // ── Рядок «Ви:» ──────────────────────────────────────────────
        _text(dc, 8, infoY, Graphics.FONT_XTINY,
              L.s(Rez.Strings.LabelYou), Graphics.TEXT_JUSTIFY_LEFT, Graphics.COLOR_LT_GRAY);
        infoY += lineH - 2;

        var myStr = _hasGps ? _myMgrs : L.s(Rez.Strings.MsgWaitGps);
        var myCol = _hasGps ? Graphics.COLOR_CYAN : Graphics.COLOR_YELLOW;
        _text(dc, _cx, infoY, Graphics.FONT_XTINY,
              myStr, Graphics.TEXT_JUSTIFY_CENTER, myCol);
        infoY += lineH;

        // ── Роздільник ───────────────────────────────────────────────
        dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(1);
        dc.drawLine(8, infoY, _w - 8, infoY);
        infoY += 4;

        // ── Рядок «Ціль:» ─────────────────────────────────────────────
        var tgtName = TARGET_LIST[targetIndex]["name"] as String;
        _text(dc, 8, infoY, Graphics.FONT_XTINY,
              tgtName + ":", Graphics.TEXT_JUSTIFY_LEFT, Graphics.COLOR_RED);
        infoY += lineH - 2;

        _text(dc, _cx, infoY, Graphics.FONT_XTINY,
              _tgtMgrs, Graphics.TEXT_JUSTIFY_CENTER, Graphics.COLOR_ORANGE);
        infoY += lineH;

        // ── Роздільник ───────────────────────────────────────────────
        dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(1);
        dc.drawLine(8, infoY, _w - 8, infoY);
        infoY += 4;

        // ── Азимути (якщо є GPS) ─────────────────────────────────────
        if (_hasGps) {
            _text(dc, 8, infoY, Graphics.FONT_XTINY,
                  L.s(Rez.Strings.LabelDirAz), Graphics.TEXT_JUSTIFY_LEFT, Graphics.COLOR_LT_GRAY);
            _text(dc, _w - 8, infoY, Graphics.FONT_XTINY,
                  Lang.format("$1$°", [ _targetAzimuth.format("%.1f") ]),
                  Graphics.TEXT_JUSTIFY_RIGHT, Graphics.COLOR_RED);
            infoY += lineH;

            _text(dc, 8, infoY, Graphics.FONT_XTINY,
                  L.s(Rez.Strings.LabelRevAz), Graphics.TEXT_JUSTIFY_LEFT, Graphics.COLOR_LT_GRAY);
            _text(dc, _w - 8, infoY, Graphics.FONT_XTINY,
                  Lang.format("$1$°", [ _reverseAzimuth.format("%.1f") ]),
                  Graphics.TEXT_JUSTIFY_RIGHT, Graphics.COLOR_WHITE);
        }
    }

    // ── onUpdate ─────────────────────────────────────────────────────

    function onUpdate(dc as Graphics.Dc) as Void {
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.clear();

        _drawCompass(dc);
        _drawLegend(dc);
        _drawModeIndicator(dc);

        if (displayMode == MODE_MGRS) {
            _drawMGRSPanel(dc);
        } else {
            _drawAzimuthPanel(dc);
        }
    }

    function onHide() as Void {
        Position.enableLocationEvents(Position.LOCATION_DISABLE, method(:onPosition));
        Sensor.setEnabledSensors([] as Array<Sensor.SensorType>);
        Sensor.enableSensorEvents(null);
    }
}
