import Toybox.WatchUi;
import Toybox.Lang;

//
// DeleteObjectDelegate — обробник підменю видалення кастомної точки.
//
// Кожен пункт меню має ID = індекс у списку кастомних точок (0-based).
// Після видалення закриває підменю та головне меню.
//
class DeleteObjectDelegate extends WatchUi.Menu2InputDelegate {

    private var _view as AzimuthView;

    function initialize(view as AzimuthView) {
        Menu2InputDelegate.initialize();
        _view = view;
    }

    function onSelect(item as WatchUi.MenuItem) as Void {
        var customIndex = item.getId() as Lang.Number;
        _view.deleteCustomObject(customIndex);
        // Закрити DeleteMenu + MainMenu
        WatchUi.popView(WatchUi.SLIDE_DOWN);
        WatchUi.popView(WatchUi.SLIDE_DOWN);
    }

    function onBack() as Void {
        WatchUi.popView(WatchUi.SLIDE_DOWN);
    }
}
