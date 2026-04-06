import Toybox.WatchUi;
import Toybox.Lang;

//
// L — скорочений хелпер для завантаження локалізованих рядків.
//
// Використання:  L.s(Rez.Strings.FieldZone)
//
// SDK автоматично обирає правильний рядок з потрібного мовного файлу
// відповідно до налаштувань мови на пристрої.
//
module L {
    function s(id as Lang.ResourceId) as String {
        return WatchUi.loadResource(id) as String;
    }
}
