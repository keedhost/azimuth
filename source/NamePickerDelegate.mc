import Toybox.WatchUi;
import Toybox.Lang;

//
// NamePickerDelegate — обробник TextPicker для введення назви нової точки.
//
// _popCount — кількість вью для закриття після збереження:
//   З GPS:    3  (TextPicker + AddMenu + MainMenu)
//   Вручну:   4  (TextPicker + CoordInput + AddMenu + MainMenu)
//
class NamePickerDelegate extends WatchUi.TextPickerDelegate {

    private var _lat      as Double;
    private var _lon      as Double;
    private var _view     as AzimuthView;
    private var _popCount as Number;

    function initialize(lat      as Double,
                        lon      as Double,
                        view     as AzimuthView,
                        popCount as Number) {
        TextPickerDelegate.initialize();
        _lat      = lat;
        _lon      = lon;
        _view     = view;
        _popCount = popCount;
    }

    function onTextPickerComplete(text as String, cancelled as Boolean) as Boolean {
        if (!cancelled) {
            var name = (text != null && text.length() > 0)
                ? text
                : Lang.format("$1$ $2$",
                    [ L.s(Rez.Strings.AutoPointPrefix), CustomObjects.count() + 1 ]);
            _view.addCustomObject(name, _lat, _lon);
        }
        // TextPicker закриває себе сам (return true).
        // Додатково закриваємо решту стека.
        for (var i = 1; i < _popCount; i++) {
            WatchUi.popView(WatchUi.SLIDE_DOWN);
        }
        return true;
    }
}
