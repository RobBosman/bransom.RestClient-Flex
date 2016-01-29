package nl.bransom.gui {

	import flash.display.Sprite;
	import flash.utils.setTimeout;
	
	import mx.controls.Alert;
	import mx.core.IFlexModuleFactory;
	import mx.managers.BrowserManager;
	import mx.managers.IBrowserManager;
	import mx.utils.URLUtil;
	
	public class Utils {
		
		public static function getCurrentUrl(title:String):String {
			var browserManager:IBrowserManager = BrowserManager.getInstance();
			browserManager.init("", title);
			return browserManager.url;
		}
		
		public static function getUrlParam(url:String, paramKey:String):String {
			if (url == null) {
				return null;
			}
			// Read the URL parameters.
			var queryParams:Array = url.replace(/.*\?/, "").split(/[&#]/);
			for each (var queryParam:String in queryParams) {
				var keyValue:Array = decodeURIComponent(queryParam).split("=");
				if (keyValue.length > 0 && keyValue[0] == paramKey) {
					if (keyValue.length == 1) {
						return "";
					} else {
						return keyValue[1];
					}
				}
			}
			return null;
		}

		public static function alert(text:String, title:String, flags:uint = Alert.OK, parent:Sprite = null,
									 closeHandler:Function = null, iconClass:Class = null,
									 defaultButtonFlag:uint = Alert.OK, moduleFactory:IFlexModuleFactory = null):Alert {
			var alert:Alert = Alert.show(text, title, flags, parent, closeHandler, iconClass, defaultButtonFlag,
				moduleFactory);
			// Weird bug in Flex 4.6:
			// the modal Alert dialog pops up (the screen gets blurred), but the dialog remains invisible.
			// Work-around: explicitly redraw the alert dialog after a short delay.
			setTimeout(redraw, 500, alert);
			return alert;
		}
		
		private static function redraw(alert:Alert):void {
			if (alert.visible) {
				alert.invalidateDisplayList();
				alert.validateNow();
			}
		}
	}
}