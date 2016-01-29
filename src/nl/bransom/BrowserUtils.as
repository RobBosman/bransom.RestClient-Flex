package nl.bransom {
	
	public class BrowserUtils {
		
		import flash.external.ExternalInterface;
		
		private static const BROWSER_VERSION:XML = <![CDATA[
				function() { 
					return {
						appCodeName: navigator.appCodeName,
						appName: navigator.appName,
						appVersion: navigator.appVersion,
						platform: navigator.platform,
						userAgent: navigator.userAgent
					};
				}
			]]>;

		private static var browserVersion:Object = null;
		
		public static function getNavigatorData():Object {
			if ((browserVersion == null)) {
				if (ExternalInterface.available) {
					browserVersion = ExternalInterface.call(BROWSER_VERSION);
				} else {
					browserVersion = {};
				}
			}
			return browserVersion;
		}
	}
}