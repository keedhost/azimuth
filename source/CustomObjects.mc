import Toybox.Application;
import Toybox.Lang;

//
// CustomObjects — модуль для збереження/завантаження кастомних точок.
//
// Дані зберігаються через Application.Storage під ключем "customObjs".
// Кожен запис: { "name" => String, "lat" => Double, "lon" => Double }
//
// Ліміт MAX записів, щоб не переповнити сховище.
//
module CustomObjects {

    const STORAGE_KEY = "customObjs";
    const MAX         = 20;

    // Завантажує список із Storage. Завжди повертає Array (порожній якщо нічого немає).
    function load() as Array< Dictionary > {
        var raw = Application.Storage.getValue(STORAGE_KEY);
        if (raw instanceof Lang.Array) {
            return raw as Array< Dictionary >;
        }
        return [] as Array< Dictionary >;
    }

    // Зберігає список у Storage.
    function save(list as Array< Dictionary >) as Void {
        Application.Storage.setValue(STORAGE_KEY, list);
    }

    // Додає нову точку. Повертає true якщо успішно, false якщо досягнуто ліміту.
    function add(name as String, lat as Double, lon as Double) as Boolean {
        var list = load();
        if (list.size() >= MAX) { return false; }
        list.add({ "name" => name, "lat" => lat, "lon" => lon } as Dictionary);
        save(list);
        return true;
    }

    // Видаляє точку за індексом у списку кастомних (0-based).
    function remove(customIndex as Number) as Void {
        var list = load();
        if (customIndex < 0 || customIndex >= list.size()) { return; }
        var newList = [] as Array< Dictionary >;
        for (var i = 0; i < list.size(); i++) {
            if (i != customIndex) {
                newList.add(list[i]);
            }
        }
        save(newList);
    }

    // Кількість кастомних точок
    function count() as Number {
        return load().size();
    }
}
