import Toybox.Graphics;
import Toybox.WatchUi;
import Toybox.Lang;

//
// CoordInputView — введення координат у форматі MGRS (по-замовчуванню).
//
// 8 полів, wizard-стиль (одне поле за раз):
//   0: Зона      (01–60)
//   1: Пояс      (C–X, індекс у _LAT_BANDS)
//   2: Квадрат E (0–7, буква залежить від зони)
//   3: Квадрат N (0–19, буква залежить від парності зони)
//   4: E старші  (00–99, ×1000 м у межах 100-км квадрата)
//   5: E молодші (00–99, ×10 м)
//   6: N старші  (00–99, ×1000 м)
//   7: N молодші (00–99, ×10 м)
//
// Точність: 4-digit MGRS = 10 м.
//
// UP/DOWN: змінити значення поточного поля (±1)
// SELECT:  перейти до наступного поля / підтвердити на останньому
// BACK:    скасувати / повернутись до попереднього поля
//
// При ініціалізації із AzimuthView підставляє поточну GPS-позицію.
//

class CoordInputView extends WatchUi.View {

    // ── 8 значень полів ───────────────────────────────────────────────
    var fZone  as Number = 36;  // за замовчуванням: зона Kyiv
    var fBand  as Number = 16;  // U  (48°–56°N)
    var fCol   as Number = 2;   // U з набору STUVWXYZ (zone 36)
    var fRow   as Number = 15;  // A з парного набору (zone 36)
    var fEHi   as Number = 12;  // 12__ → Easting ≈ 312__0 м
    var fELo   as Number = 0;
    var fNHi   as Number = 90;  // 90__ → Northing ≈ 559_0__ м
    var fNLo   as Number = 0;

    private var _field as Number = 0;  // 0..7, поточне активне

    function initialize(azimView as AzimuthView) {
        View.initialize();

        // Ініціалізуємо з поточної GPS-позиції (якщо є)
        var lat = azimView.getCurrentLat();
        var lon = azimView.getCurrentLon();
        if (lat != null && lon != null) {
            var f = MGRSUtil.toFields(lat as Double, lon as Double);
            fZone = f["zone"]    as Number;
            fBand = f["bandIdx"] as Number;
            fCol  = f["colIdx"]  as Number;
            fRow  = f["rowIdx"]  as Number;
            fEHi  = f["eHi"]     as Number;
            fELo  = f["eLo"]     as Number;
            fNHi  = f["nHi"]     as Number;
            fNLo  = f["nLo"]     as Number;
        }
    }

    // ── Отримання результату ─────────────────────────────────────────

    function getLat() as Double {
        var r = MGRSUtil.fromFields(fZone, fBand, fCol, fRow, fEHi, fELo, fNHi, fNLo);
        return r[0];
    }

    function getLon() as Double {
        var r = MGRSUtil.fromFields(fZone, fBand, fCol, fRow, fEHi, fELo, fNHi, fNLo);
        return r[1];
    }

    // ── Управління полями ────────────────────────────────────────────

    // Змінити поточне поле на delta (зазвичай ±1)
    function adjust(delta as Number) as Void {
        if      (_field == 0) { fZone = _clamp(fZone + delta, 1,  60); }
        else if (_field == 1) { fBand = _clamp(fBand + delta, 0,  19); }
        else if (_field == 2) { fCol  = _clamp(fCol  + delta, 0,   7); }
        else if (_field == 3) { fRow  = _clamp(fRow  + delta, 0,  19); }
        else if (_field == 4) { fEHi  = _clamp(fEHi  + delta, 0,  99); }
        else if (_field == 5) { fELo  = _clamp(fELo  + delta, 0,  99); }
        else if (_field == 6) { fNHi  = _clamp(fNHi  + delta, 0,  99); }
        else                  { fNLo  = _clamp(fNLo  + delta, 0,  99); }
        WatchUi.requestUpdate();
    }

    // Перейти до наступного поля. true = всі поля заповнено (підтвердити).
    function advance() as Boolean {
        if (_field < 7) { _field++; WatchUi.requestUpdate(); return false; }
        return true;
    }

    // Повернутись до попереднього поля. true = вже перше поле (вийти).
    function retreat() as Boolean {
        if (_field > 0) { _field--; WatchUi.requestUpdate(); return false; }
        return true;
    }

    // ── Допоміжні ────────────────────────────────────────────────────

    private function _clamp(v as Number, lo as Number, hi as Number) as Number {
        return v < lo ? lo : (v > hi ? hi : v);
    }

    // Буква колонки для поточних fZone, fCol
    private function _colChar() as String {
        var s = ((fZone - 1) % 3 == 0) ? MGRSUtil._COL0
              : ((fZone - 1) % 3 == 1) ? MGRSUtil._COL1
              : MGRSUtil._COL2;
        return s.substring(fCol, fCol + 1);
    }

    // Буква рядка для поточних fZone, fRow
    private function _rowChar() as String {
        var s = (fZone % 2 == 1) ? MGRSUtil._ROW_ODD : MGRSUtil._ROW_EVEN;
        return s.substring(fRow, fRow + 1);
    }

    // Буква поясу
    private function _bandChar() as String {
        return MGRSUtil._LAT_BANDS.substring(fBand, fBand + 1);
    }

    // ── Відображення ────────────────────────────────────────────────

    function onUpdate(dc as Graphics.Dc) as Void {
        var w  = dc.getWidth();
        var h  = dc.getHeight();
        var cx = w / 2;

        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.clear();

        // ── MGRS-рядок попереднього перегляду (вгорі) ─────────────────
        // Формат: «36U UA 12 00 90 00»
        // Відображаємо сегментами: активний — жовтий, решта — сірий
        var zStr  = fZone.format("%02d");
        var bStr  = _bandChar();
        var cStr  = _colChar();
        var rStr  = _rowChar();
        var ehStr = fEHi.format("%02d");
        var elStr = fELo.format("%02d");
        var nhStr = fNHi.format("%02d");
        var nlStr = fNLo.format("%02d");

        var segments = [
            [ zStr, 0 ], [ bStr, 1 ], [" ", -1],
            [ cStr, 2 ], [ rStr, 3 ], [" ", -1],
            [ ehStr, 4], [ elStr, 5], [" ", -1],
            [ nhStr, 6], [ nlStr, 7]
        ] as Array< Array >;

        // Обчислюємо x для кожного сегмента (моно-стиль, фіксована ширина)
        // Для FONT_XTINY приблизно 7 пікселів на символ
        var charW = 7;
        var previewStr = zStr + bStr + " " + cStr + rStr + " " + ehStr + elStr + " " + nhStr + nlStr;
        var totalW = previewStr.length() * charW;
        var startX = cx - totalW / 2;

        dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawLine(0, 0, w, 0);

        var px = startX;
        for (var i = 0; i < segments.size(); i++) {
            var seg    = segments[i];
            var segStr = seg[0] as String;
            var segId  = seg[1] as Number;
            var color  = (segId == _field) ? Graphics.COLOR_YELLOW
                       : (segId < 0)       ? Graphics.COLOR_DK_GRAY
                       : Graphics.COLOR_LT_GRAY;
            dc.setColor(color, Graphics.COLOR_TRANSPARENT);
            dc.drawText(px, 3, Graphics.FONT_XTINY, segStr, Graphics.TEXT_JUSTIFY_LEFT);
            px += segStr.length() * charW;
        }

        dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(1);
        dc.drawLine(0, 18, w, 18);

        // ── Назва та значення поточного поля ──────────────────────────
        var fieldNames = [
            L.s(Rez.Strings.FieldZone), L.s(Rez.Strings.FieldBand),
            L.s(Rez.Strings.FieldColE), L.s(Rez.Strings.FieldRowN),
            L.s(Rez.Strings.FieldEHi),  L.s(Rez.Strings.FieldELo),
            L.s(Rez.Strings.FieldNHi),  L.s(Rez.Strings.FieldNLo)
        ] as Array<String>;

        var fieldVals = [
            zStr, bStr, cStr, rStr,
            fEHi.format("%02d"), fELo.format("%02d"),
            fNHi.format("%02d"), fNLo.format("%02d")
        ] as Array<String>;

        var fieldRanges = [
            "1–60", "C–X", "A–Z", "A–V",
            "00–99", "00–99", "00–99", "00–99"
        ] as Array<String>;

        var midY = h / 2 - 20;

        // Назва поля
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, midY - 10, Graphics.FONT_XTINY,
                    fieldNames[_field] + "  (" + fieldRanges[_field] + ")",
                    Graphics.TEXT_JUSTIFY_CENTER);

        // Велике значення
        dc.setColor(Graphics.COLOR_YELLOW, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, midY + 5, Graphics.FONT_LARGE,
                    fieldVals[_field], Graphics.TEXT_JUSTIFY_CENTER);

        // Стрілки ▲ / ▼
        dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(8,     midY + 10, Graphics.FONT_SMALL, "▲", Graphics.TEXT_JUSTIFY_LEFT);
        dc.drawText(w - 8, midY + 10, Graphics.FONT_SMALL, "▼", Graphics.TEXT_JUSTIFY_RIGHT);

        // ── Прогрес-індикатор ─────────────────────────────────────────
        var barY   = h - 42;
        var barW   = w - 16;
        var segLen = barW / 8;
        dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawLine(8, barY, w - 8, barY);
        for (var i = 0; i <= 8; i++) {
            dc.drawLine(8 + i * segLen, barY - 3, 8 + i * segLen, barY);
        }
        dc.setColor(Graphics.COLOR_YELLOW, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(3);
        dc.drawLine(8 + _field * segLen, barY - 3,
                    8 + (_field + 1) * segLen, barY - 3);
        dc.setPenWidth(1);

        // ── Підказки ─────────────────────────────────────────────────
        dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawLine(0, h - 28, w, h - 28);
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        var hint = (_field < 7) ? L.s(Rez.Strings.HintNext)
                                : L.s(Rez.Strings.HintConfirm);
        dc.drawText(cx, h - 24, Graphics.FONT_XTINY, hint, Graphics.TEXT_JUSTIFY_CENTER);
    }
}

// ─────────────────────────────────────────────────────────────────────────────

class CoordInputDelegate extends WatchUi.BehaviorDelegate {

    private var _cv       as CoordInputView;
    private var _azimView as AzimuthView;

    function initialize(cv as CoordInputView, azimView as AzimuthView) {
        BehaviorDelegate.initialize();
        _cv       = cv;
        _azimView = azimView;
    }

    // UP → збільшити
    function onPreviousPage() as Boolean {
        _cv.adjust(+1);
        return true;
    }

    // DOWN → зменшити
    function onNextPage() as Boolean {
        _cv.adjust(-1);
        return true;
    }

    // SELECT → наступне поле або підтвердження
    function onSelect() as Boolean {
        if (_cv.advance()) {
            _pushNamePicker(_cv.getLat(), _cv.getLon());
        }
        return true;
    }

    // BACK → попереднє поле або вихід
    function onBack() as Boolean {
        if (_cv.retreat()) {
            WatchUi.popView(WatchUi.SLIDE_DOWN);
        }
        return true;
    }

    private function _pushNamePicker(lat as Double, lon as Double) as Void {
        if (WatchUi has :TextPickerFactory) {
            var picker = WatchUi.TextPickerFactory.getTextPicker(
                "", WatchUi.TEXT_PICKER_MODE_ALPHA_MIXED, 0
            );
            // 4 pop: TextPicker + CoordInput + AddMenu + MainMenu
            WatchUi.pushView(picker,
                             new NamePickerDelegate(lat, lon, _azimView, 4),
                             WatchUi.SLIDE_UP);
        } else {
            var autoName = Lang.format("$1$ $2$",
                [ L.s(Rez.Strings.AutoPointPrefix), CustomObjects.count() + 1 ]);
            _azimView.addCustomObject(autoName, lat, lon);
            WatchUi.popView(WatchUi.SLIDE_DOWN);
            WatchUi.popView(WatchUi.SLIDE_DOWN);
            WatchUi.popView(WatchUi.SLIDE_DOWN);
        }
    }
}
