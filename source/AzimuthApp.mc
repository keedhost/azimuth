import Toybox.Application;
import Toybox.Lang;
import Toybox.WatchUi;

//
// Головний клас застосунку «Azimuth».
// Запускає View + InputDelegate.
//
class AzimuthApp extends Application.AppBase {

    function initialize() {
        AppBase.initialize();
    }

    function onStart(state as Lang.Dictionary?) as Void {
    }

    function onStop(state as Lang.Dictionary?) as Void {
    }

    function getInitialView() as [ WatchUi.Views ] or [ WatchUi.Views, WatchUi.InputDelegates ] {
        return [ new AzimuthView(), new AzimuthDelegate() ];
    }
}

function getApp() as AzimuthApp {
    return Application.getApp() as AzimuthApp;
}
