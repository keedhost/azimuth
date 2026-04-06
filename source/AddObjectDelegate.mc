import Toybox.WatchUi;
import Toybox.Lang;

//
// AddObjectDelegate — обробник підменю «Додати точку».
//
//   ID 0: «З поточної позиції»
//   ID 1: «Ввести координати MGRS»
//
class AddObjectDelegate extends WatchUi.Menu2InputDelegate {

    private var _view as AzimuthView;

    function initialize(view as AzimuthView) {
        Menu2InputDelegate.initialize();
        _view = view;
    }

    function onSelect(item as WatchUi.MenuItem) as Void {
        var id = item.getId() as Lang.Number;

        if (id == 0) {
            // ── З поточної GPS-позиції ────────────────────────────────
            var lat = _view.getCurrentLat();
            var lon = _view.getCurrentLon();

            if (lat == null || lon == null) {
                var msg = new WatchUi.Confirmation(L.s(Rez.Strings.MsgGpsError));
                WatchUi.pushView(msg, new WatchUi.ConfirmationDelegate(), WatchUi.SLIDE_UP);
                return;
            }

            if (WatchUi has :TextPickerFactory) {
                var picker = WatchUi.TextPickerFactory.getTextPicker(
                    "", WatchUi.TEXT_PICKER_MODE_ALPHA_MIXED, 0
                );
                // 3 pop: TextPicker + AddMenu + MainMenu
                WatchUi.pushView(picker,
                                 new NamePickerDelegate(lat as Double, lon as Double, _view, 3),
                                 WatchUi.SLIDE_UP);
            } else {
                var autoName = Lang.format("$1$ $2$",
                    [ L.s(Rez.Strings.AutoPointPrefix), CustomObjects.count() + 1 ]);
                _view.addCustomObject(autoName, lat as Double, lon as Double);
                WatchUi.popView(WatchUi.SLIDE_DOWN);
                WatchUi.popView(WatchUi.SLIDE_DOWN);
            }

        } else {
            // ── Ввести координати MGRS вручну ────────────────────────
            var coordView = new CoordInputView(_view);
            var coordDlg  = new CoordInputDelegate(coordView, _view);
            WatchUi.pushView(coordView, coordDlg, WatchUi.SLIDE_UP);
        }
    }

    function onBack() as Void {
        WatchUi.popView(WatchUi.SLIDE_DOWN);
    }
}
