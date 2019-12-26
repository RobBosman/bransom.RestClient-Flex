package nl.bransom {

	import flash.events.Event;
	import flash.events.HTTPStatusEvent;
	import flash.events.IOErrorEvent;
	import flash.events.ProgressEvent;
	import flash.events.SecurityErrorEvent;
	import flash.net.URLLoader;
	import flash.net.URLRequest;
	import flash.net.URLRequestHeader;
	import flash.net.URLRequestMethod;
	import flash.utils.ByteArray;
	
	import mx.netmon.NetworkMonitor;

	/**
	 * Wrapper for HTTPService
	 */
	public class RemoteInvokerHttp {

		private const REQUEST_CONTENT_ENCODING:String = "UTF-8";
		private const REQUEST_CONTENT_TYPE:String = "text/xml";
		
		public var method:String;
		public var url:String;
		public var authorizationHeader:URLRequestHeader;
		public var requestXml:XML;
		public var requestFormData:String;
		public var errorCallback:Function;
		public var okCallback:Function;
		public var context:Object = new Object();
		
		private var urlLoader:URLLoader;
		private var responseCode:int = -1;
		private var responseBytes:String;
		private var responseXml:XML;

		public function send():void {
			if (urlLoader != null) {
				throw Error("BUG: the request has already been sent.");
			}
			
			var urlRequest:URLRequest = new URLRequest();
			urlRequest.url = url;
			if (authorizationHeader != null) {
				urlRequest.requestHeaders.push(authorizationHeader);
			}
			// Flex bug: special (authorization) headers are not sent when using method 'GET'.
			urlRequest.method = URLRequestMethod.POST;
			if (urlRequest.method != method) {
				// Now here we have to tell the REST server that we intended to use another HTTP-method.
				urlRequest.url += (urlRequest.url.indexOf("?") < 0 ? "?" : "&") + "$method=" + method;
			}
			if (requestXml != null) {
				urlRequest.contentType = REQUEST_CONTENT_TYPE;
				var bytes:ByteArray = new ByteArray();
				bytes.writeMultiByte(requestXml.toXMLString(), REQUEST_CONTENT_ENCODING);
				urlRequest.data = bytes;
				urlRequest.requestHeaders.push(new URLRequestHeader("Content-Encoding", REQUEST_CONTENT_ENCODING));
			} else {
				urlRequest.data = requestFormData;
			}
			if (urlRequest.data == null) {
				// Bug in Flex: if the body is empty, the HTTP-method will be reset to 'GET'.
				// As a work-around the body is filled with dummy data!
				urlRequest.data = "dummy=true";
			}

			urlLoader = new URLLoader();
			urlLoader.addEventListener(IOErrorEvent.IO_ERROR, ioErrorHandler);
			urlLoader.addEventListener(IOErrorEvent.NETWORK_ERROR, ioErrorHandler);
			urlLoader.addEventListener(Event.OPEN, openHandler);
			urlLoader.addEventListener(SecurityErrorEvent.SECURITY_ERROR, securityErrorHandler);
			urlLoader.addEventListener(ProgressEvent.PROGRESS, progressHandler);
			urlLoader.addEventListener(HTTPStatusEvent.HTTP_STATUS, httpStatusHandler);
			urlLoader.addEventListener(Event.COMPLETE, completeHandler);
			urlLoader.load(urlRequest);
		}
		
		public function getResponseCode():int {
			if (urlLoader == null) {
				throw Error("BUG: the request has not yet been sent.");
			}
			return responseCode;
		}
		
		public function getResponseText():String {
			if (urlLoader == null) {
				throw Error("BUG: the request has not yet been sent.");
			}
			return responseBytes;
		}
		
		public function getResponseXml():XML {
			if (urlLoader == null) {
				throw Error("BUG: the request has not yet been sent.");
			}
			return responseXml;
		}
		
		public function getErrorResponseHtml():String {
			var errorMsg:String = getResponseText();
			if (errorMsg.indexOf("Error #2032: Stream Error.") == 0) {
				errorMsg = "<b>Netwerkfout (response code " + getResponseCode() + ")</b>\n" + errorMsg;
				if (requestXml != null) {
					errorMsg += "\nPosted XML:\n" + XmlUtils.escapeHtml(requestXml.toXMLString());
				}
			} else if (getResponseXml() != null) {
				// Get the message text from HTML content.
				var htmlBody:XML = XmlUtils.getElements(getResponseXml(), "body")[0];
				if (htmlBody != null) {
					errorMsg = htmlBody.children().toXMLString();
				}
				// Append request and context info.
				errorMsg += "<p/>" + XmlUtils.escapeHtml(url);
				if (requestXml != null) {
					errorMsg += "\n" + XmlUtils.escapeHtml(requestXml.toString());
				}
			}
			errorMsg += "\n" + new Date();
			// Convert to 'HTML'.
			return "<html><body>" + errorMsg + "</body></html>";
		}
		
		private function ioErrorHandler(event:IOErrorEvent):void {
//			Alert.show("ioErrorHandler: " + event, "DEBUG");
			readResponseFromStream();
			if ((responseBytes == null) || (responseBytes.length == 0)) {
				responseBytes = event.text;
			}
			if (errorCallback != null) {
				errorCallback(this);
			} else {
				throw new Error(getResponseText());
			}
		}
		private function openHandler(event:Event):void {
//			Alert.show("openHandler: " + event, "DEBUG");
		}
		private function securityErrorHandler(event:SecurityErrorEvent):void {
//			Alert.show("Security error: " + event, "DEBUG");
			throw new Error("Security error: " + event);
		}
		private function progressHandler(event:ProgressEvent):void {
//			Alert.show("progressHandler loaded:" + event.bytesLoaded + " total: " + event.bytesTotal, "DEBUG");
		}
		private function httpStatusHandler(event:HTTPStatusEvent):void {
//			Alert("httpStatusHandler: " + event, "DEBUG");
			responseCode = event.status;
		}
		private function completeHandler(event:Event):void {
//			Alert.show("completeHandler: " + event, "DEBUG");
			responseCode = 200;
			readResponseFromStream();
			if (okCallback != null) {
				okCallback(this);
			}
		}
		
		private function readResponseFromStream():void {
			responseBytes = urlLoader.data;
			responseXml = new XML();
			if ((responseBytes != null) && (responseBytes.length > 0)) {
				try {
					responseXml = new XML(responseBytes);
				} catch (e:Error) {
					// It's not XML! Ignore the exception.
				}
			}
		}

	}
}