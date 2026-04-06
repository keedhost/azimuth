import Toybox.WatchUi;
import Toybox.Lang;

//
// Обробник кнопок головного екрана.
//
//   MENU   → головне меню (вибір точки / додати / видалити)
//   SELECT → перемикання режиму AZ ↔ MGRS
//   BACK   → вихід із застосунку
//
class AzimuthDelegate extends WatchUi.BehaviorDelegate {

    private var _view as AzimuthView;

    function initialize() {
        BehaviorDelegate.initialize();
        _view = WatchUi.getCurrentView()[0] as AzimuthView;
    }

    function onMenu() as Boolean {
        var menu = new WatchUi.Menu2({ :title => L.s(Rez.Strings.MenuTitle) });
        var list = _view.TARGET_LIST;

        // ── Усі точки (вбудовані + кастомні) ─────────────────────────
        for (var i = 0; i < list.size(); i++) {
            var obj      = list[i];
            var isCustom = (obj.hasKey("custom") && obj["custom"] == true);
            var lat      = obj["lat"] as Double;
            var lon      = obj["lon"] as Double;
            var mgrsStr  = MGRSUtil.encode(lat, lon, 4);
            var prefix   = isCustom ? "* " : "";

            menu.addItem(new WatchUi.MenuItem(
                prefix + (obj["name"] as String),
                mgrsStr,
                i,
                {}
            ));
        }

        // ── Спеціальні дії ───────────────────────────────────────────
        menu.addItem(new WatchUi.MenuItem(
            L.s(Rez.Strings.MenuAdd), null, -1, {}
        ));

        if (_view.customCount() > 0) {
            menu.addItem(new WatchUi.MenuItem(
                L.s(Rez.Strings.MenuDeleteCustom), null, -2, {}
            ));
        }

        WatchUi.pushView(menu, new AzimuthMenuDelegate(_view), WatchUi.SLIDE_UP);
        return true;
    }

    function onSelect() as Boolean {
        _view.toggleDisplayMode();
        return true;
    }

    function onBack() as Boolean {
        WatchUi.popView(WatchUi.SLIDE_DOWN);
        return true;
    }
}
