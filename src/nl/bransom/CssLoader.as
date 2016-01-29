package nl.bransom {
	
	import flash.events.Event;
	import flash.events.HTTPStatusEvent;
	import flash.events.IEventDispatcher;
	import flash.events.IOErrorEvent;
	import flash.events.SecurityErrorEvent;
	import flash.net.URLRequest;
	import flash.net.URLStream;
	import flash.utils.ByteArray;
	
	import mx.core.UIComponent;
	import mx.events.ModuleEvent;

	public class CssLoader {

		private var url:String;
		private var cssTarget:UIComponent;

		public function CssLoader(url:String, cssTarget:UIComponent = null):void {
			this.url = url;
			this.cssTarget = cssTarget;
		}

		public function load():void {
			var urlStream:URLStream = new URLStream();
			urlStream.addEventListener(IOErrorEvent.IO_ERROR, errorResponseHandler);
			urlStream.addEventListener(IOErrorEvent.NETWORK_ERROR, errorResponseHandler);
			urlStream.addEventListener(SecurityErrorEvent.SECURITY_ERROR, errorResponseHandler);
			urlStream.addEventListener(HTTPStatusEvent.HTTP_STATUS, okResponseHandler);
			urlStream.load(new URLRequest(url));
		}
		
		private function errorResponseHandler(event:Event):void {
			// Ignore all errors.
			// The presence of this event handler prevents errors from being displayed (or crashing the flash player).
			return;
		}
		
		private function okResponseHandler(event:HTTPStatusEvent):void {
			if (event.status == 200) {
				if (cssTarget != null) {
					var eventDispatcher:IEventDispatcher = cssTarget.styleManager.loadStyleDeclarations2(url);
					eventDispatcher.addEventListener(ModuleEvent.ERROR, errorResponseHandler);
				}
			}
		}
	}
}