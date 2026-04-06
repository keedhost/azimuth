import Toybox.WatchUi;
import Toybox.Lang;

//
// AzimuthMenuDelegate — обробник головного меню.
//
// ID пункту:  ≥0 → вибрати ціль   |  -1 → «Додати»   |  -2 → «Видалити»
//
class AzimuthMenuDelegate extends WatchUi.Menu2InputDelegate {

    private var _view as AzimuthView;

    function initialize(view as AzimuthView) {
        Menu2InputDelegate.initialize();
        _view = view;
    }

    function onSelect(item as WatchUi.MenuItem) as Void {
        var id = item.getId() as Lang.Number;

        if (id >= 0) {
            // ── Вибір цілі ───────────────────────────────────────────
            _view.selectTarget(id);
            WatchUi.popView(WatchUi.SLIDE_DOWN);

        } else if (id == -1) {
            // ── Підменю «Додати» ──────────────────────────────────────
            var gpsSubtitle = _view.getCurrentLat() != null
                ? L.s(Rez.Strings.MenuGpsReady)
                : L.s(Rez.Strings.MenuGpsWait);

            var addMenu = new WatchUi.Menu2({ :title => L.s(Rez.Strings.MenuAddTitle) });
            addMenu.addItem(new WatchUi.MenuItem(
                L.s(Rez.Strings.MenuFromGps), gpsSubtitle, 0, {}
            ));
            addMenu.addItem(new WatchUi.MenuItem(
                L.s(Rez.Strings.MenuManual), L.s(Rez.Strings.MenuManualHint), 1, {}
            ));
            WatchUi.pushView(addMenu, new AddObjectDelegate(_view), WatchUi.SLIDE_UP);

        } else if (id == -2) {
            // ── Підменю «Видалити» ────────────────────────────────────
            var delMenu = new WatchUi.Menu2({ :title => L.s(Rez.Strings.MenuDeleteTitle) });
            var list    = _view.TARGET_LIST;

            for (var i = 0; i < list.size(); i++) {
                var obj = list[i];
                if (obj.hasKey("custom") && obj["custom"] == true) {
                    var customIndex = i - 8;   // 8 = PRESET_COUNT
                    delMenu.addItem(new WatchUi.MenuItem(
                        obj["name"] as String,
                        MGRSUtil.encode(obj["lat"] as Double, obj["lon"] as Double, 4),
                        customIndex,
                        {}
                    ));
                }
            }
            WatchUi.pushView(delMenu, new DeleteObjectDelegate(_view), WatchUi.SLIDE_UP);
        }
    }

    function onBack() as Void {
        WatchUi.popView(WatchUi.SLIDE_DOWN);
    }
}
