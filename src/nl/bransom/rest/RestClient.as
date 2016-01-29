package nl.bransom.rest {

	import flash.display.DisplayObject;
	import flash.events.Event;
	import flash.events.TimerEvent;
	import flash.net.URLLoader;
	import flash.net.URLRequest;
	import flash.net.URLRequestHeader;
	import flash.net.URLRequestMethod;
	import flash.net.URLStream;
	import flash.net.URLVariables;
	import flash.net.navigateToURL;
	import flash.utils.Dictionary;
	import flash.utils.Timer;
	
	import mx.binding.utils.BindingUtils;
	import mx.controls.Alert;
	import mx.core.FlexGlobals;
	import mx.utils.UIDUtil;
	
	import nl.bransom.ChainableTask;
	import nl.bransom.PersistencyStatus;
	import nl.bransom.RemoteInvokerHttp;
	import nl.bransom.XmlUtils;
	import nl.bransom.gui.ErrorPopup;

	/**
	 * performs the following tasks:
	 * 
	 * - request the full XML object tree from the REST server
	 * - handle the REST server-response to the read-request
	 *
	 * - set changed-flag to XML-entity
	 * - (re)start delay timer
	 *
	 * - send all changes to the REST server to create/update
	 * - handle the REST server-response to the create/update-request
	 *
	 * - reset changed-flags
	 *
	 * - notify successful save
	 *
	 * - send a publish-request to the REST server
	 * - handle the REST server-response to the publish-request
	 *
	 * - notify successful publish
	 */
	public class RestClient {

		private const AUTOSAVE_INTERVAL_MILLIS:int = 2000;
		private const PROXY_URL:String = "http://localhost:8888";
		private const REST_SESSION_TAG:String = "$clientID";
		
		[Bindable] public var xmlMap:Object = new Object();
		[Bindable] public var status:PersistencyStatus = PersistencyStatus.UNKNOWN;
		[Bindable] public var lastSaved:Date = null;
		[Bindable] public var useAutoSave:Boolean = true;
		[Bindable] public var errorHtmlText:String;
		[Bindable] public var jwt:String = null;
		[Bindable] public var signedInAccountId:String = null;
		public var afterErrorCallback:Function = null;

		public var DEBUG_viaProxy:Boolean = false;
		
		private var appName:String;
		private var restUrl:String;
		private var authUrl:String;
		private var sessionId:String = null;
		private var changeId:int = 0;
		private var deletedSet:XML = <set/>;
		private var timer:Timer = new Timer(AUTOSAVE_INTERVAL_MILLIS);
		private var pendingChangeId:int = -1;

		public function RestClient(restBaseUrl:String, appName:String, authUrl:String = null) {
			this.appName = appName;
			this.restUrl = restBaseUrl + appName + "/";
			this.authUrl = authUrl;

			// Set a unique ID for the REST session.
			this.sessionId = UIDUtil.createUID();
			
			BindingUtils.bindSetter(showError, this, "errorHtmlText");
			BindingUtils.bindSetter(useAutoSaveChanged, this, "useAutoSave");
		}
		
		public function getHttpAuthorizationHeader():URLRequestHeader {
			return (jwt == null ? null : new URLRequestHeader("Authorization", "Bearer " + jwt));
		}
		
		public function signOut():void {
			status = PersistencyStatus.UNKNOWN;
			xmlMap = new Object();
			errorHtmlText = null;
			changeId = 0;
			deletedSet = <set/>;
			timer.stop();
			jwt = null;
			signedInAccountId = null;
		}
		
		public function signIn():void {
			// Reuse the same window.
			navigateToURL(new URLRequest(authUrl), "_self");
		}
		
		public function signInAs(runAsAccountId:String):void {
			// DIRTY HACK!
			// This is possible because the server only checks authentication, not authorisation.
			signedInAccountId = runAsAccountId;
		}
		
		public function getAuthorization():void {
			var url:String = authUrl + "?getAuthorization=" + this.appName;
			var urlLoader:URLLoader = new URLLoader();
			urlLoader.addEventListener(Event.COMPLETE, getAuthorizationHandler);
			urlLoader.load(new URLRequest(url));
		}
		private function getAuthorizationHandler(event:Event):void {
			var data:String = event.target.data;
			if (data != null) {
				var dataParts:Array = data.split("|");
				if (dataParts.length == 2 && dataParts[0].length > 0 && dataParts[1].length > 0) {
					jwt = dataParts[0];
					signedInAccountId = dataParts[1];
				}
			}
		}
		
		private function showError(errorHtml:String):void {
			if ((errorHtml != null) && (errorHtml.length > 0)) {
				var errorPopup:ErrorPopup = new ErrorPopup();
				errorPopup.afterErrorCallback = afterErrorCallback;
				errorPopup.styleName = "error-popup";
				errorPopup.show(FlexGlobals.topLevelApplication as DisplayObject, errorHtml);
				this.errorHtmlText = null;
			}
		}

		private function useAutoSaveChanged(enabled:Boolean):void {
			if (useAutoSave) {
				timer.addEventListener(TimerEvent.TIMER, autoSave);
			} else {
				timer.removeEventListener(TimerEvent.TIMER, autoSave);
			}
		}
		private function autoSave(event:Event = null):void {
			save();
		}

		public function setTextContent(xmlElement:XML, field:String, value:String, asCData:Boolean = false):void {
			if (xmlElement == null) {
				return;
			}
			var oldValue:String = XmlUtils.getTextContent(xmlElement, field);
			if (value != oldValue) {
				XmlUtils.setTextContent(xmlElement, field, value, asCData);
				markAsChanged(xmlElement);
			}
		}

		public function createEntityNode(xmlParent:XML, entityId:String, insertIndex:Number = -1):XML {
			var createdXml:XML = XmlUtils.createEntityNode(xmlParent, entityId, insertIndex);
			createdXml.@created = changeId++;
			notifyChange(xmlParent);
			return createdXml;
		}

		public function deleteEntityNode(xmlToBeDeleted:XML):Boolean {
			var isDeleted:Boolean = false;
			if (xmlToBeDeleted != null) {
				var xmlBereavedParent:XML = xmlToBeDeleted.parent();
				var deletedXmlRef:XML = XmlUtils.deleteEntityNode(xmlToBeDeleted);
				if (deletedXmlRef != null) {
					// Mark the node for deletion if it is persistent (no @created attribute) or is not being saved.
					if ((XmlUtils.getTextContent(xmlToBeDeleted, "@created").length == 0)
						|| (xmlToBeDeleted.@created <= pendingChangeId)) {
						deletedXmlRef.@deleted = changeId++;
						deletedSet.appendChild(deletedXmlRef);
					}
					notifyChange(xmlBereavedParent);
					isDeleted = true;
				}
			}
			return isDeleted;
		}
		
		public function canPublish(xmlToBePublished:XML, status:PersistencyStatus):Boolean {
			return ((XmlUtils.getTextContent(xmlToBePublished, "@published") == "false")
				&& ((status == PersistencyStatus.UNCHANGED) || (status == PersistencyStatus.CHANGED)
					|| (status == PersistencyStatus.SAVED)));
		}
		
		public function markAsChanged(xmlElement:XML):void {
			// Set changed-flag of the XML-entity.
			xmlElement.@changed = changeId++;
			notifyChange(xmlElement);
		}

		private function notifyChange(xmlElement:XML):void {
			// (Re)start delay timer.
			timer.stop();
			timer.start();
			// Reset the 'published' flag of the current node and of all its ancestors.
			while ((xmlElement != null) && (xmlElement.@published == "true")) {
				xmlElement.@published = "false";
				xmlElement.@changed = changeId++;
				xmlElement = xmlElement.parent();
			}
			status = PersistencyStatus.CHANGED;
		}
		
		private function newRemoteInvokerHttp(method:String, restTarget:String = "",
											  params:Object = null):RemoteInvokerHttp {
			var remoteInvoker:RemoteInvokerHttp = new RemoteInvokerHttp();
			remoteInvoker.authorizationHeader = getHttpAuthorizationHeader();
			remoteInvoker.method = method;
			// Compose the URL.
			var url:String = (DEBUG_viaProxy ? PROXY_URL : "") + restUrl + restTarget;
			var queryString:String = "";
			if (method != URLRequestMethod.GET) {
				queryString += "&" + REST_SESSION_TAG + "=" + sessionId;
			}
			if (params != null) {
				for (var param:String in params) {
					queryString += "&" + encodeURIComponent(param) + "=" + encodeURIComponent(params[param]);
				}
			}
			if (queryString.length > 0) {
				url += "?" + queryString.substr(1);
			}
			remoteInvoker.url = url;
			return remoteInvoker;
		}
		
		public function read(contextId:String, restTarget:String, params:Object, setXmlCallback:Function):void {
			// Request the full XML object tree from the REST server.
			var remoteInvoker:RemoteInvokerHttp = newRemoteInvokerHttp(URLRequestMethod.GET, restTarget + ".xml",
				params);
			remoteInvoker.errorCallback = readErrorCallback;
			remoteInvoker.okCallback = readOkCallback;
			remoteInvoker.context.contextId = contextId;
			remoteInvoker.context.setXmlCallback = setXmlCallback;
			remoteInvoker.send();
			status = PersistencyStatus.READING;
		}
		private function readErrorCallback(remoteInvoker:RemoteInvokerHttp):void {
			// Handle the REST server-response to the read-request.
			status = PersistencyStatus.UNKNOWN;
			// Check if a time-out occurred and the user was automatically logged out.
			if (remoteInvoker.getResponseCode() == 403) {
				Alert.show("Helaas, je bent niet (meer) ingelogd.", "FOUT").invalidateDisplayList();
				signOut();
			} else {
				errorHtmlText = remoteInvoker.getErrorResponseHtml();
			}
		}
		private function readOkCallback(remoteInvoker:RemoteInvokerHttp):void {
			// Handle the REST server-response to the read-request.
			var xml:XML = remoteInvoker.getResponseXml();
			if ((xml != null) && (remoteInvoker.context.setXmlCallback != null)) {
				remoteInvoker.context.setXmlCallback(xml);
			}
			xmlMap[remoteInvoker.context.contextId] = xml;
			status = PersistencyStatus.UNCHANGED;
		}

		private function collectDeletedEntities(deletedXmlRefs:XMLList, changedSet:XML, maxChangeId:int):void {
			for each (var xmlRef:XML in deletedXmlRefs) {
				if ((XmlUtils.getTextContent(xmlRef, "@deleted").length > 0) && (xmlRef.@deleted <= maxChangeId)) {
					changedSet.appendChild(xmlRef.copy());
				}
			}
		}

		private function collectChangedEntities(xmlElement:XML, changedSet:XML, maxChangeId:int):void {
			var changedEntity:XML = null;
			// Check if it is an entity node.
			if (XmlUtils.getTextContent(xmlElement, "@id").length > 0) {
				var parentXml:XML = xmlElement.parent();
				// If so, then see it it has been newly created.
				if ((XmlUtils.getTextContent(xmlElement, "@created").length > 0)
					&& (xmlElement.@created <= maxChangeId)) {
					// Yes, it's new. Copy the node tree...
					changedEntity = xmlElement.copy();
					changedSet.appendChild(changedEntity);
					// ...add a reference to the the parent entity if applicable...
					if ((parentXml != null) && (XmlUtils.getTextContent(parentXml, "@id").length > 0)) {
						changedEntity.appendChild(<{parentXml.localName()} id={parentXml.@id} />);
					}
					// ...and we're done.
					return;
				}
				// Check if the content was changed.
				if ((XmlUtils.getTextContent(xmlElement, "@changed").length > 0)
					&& (xmlElement.@changed <= maxChangeId)) {
					// If so, then add an reference-copy to the changedSet...
					changedEntity = <{xmlElement.localName()} id={xmlElement.@id} changed={xmlElement.@changed} />;
					// ...copy the scope if applicable...
					if (XmlUtils.getTextContent(xmlElement, "@scope").length > 0) {
						changedEntity.@scope = xmlElement.@scope;
					}
					// ...and add a reference to the the parent entity if applicable.
					if ((parentXml != null) && (XmlUtils.getTextContent(parentXml, "@id").length > 0)) {
						changedEntity.appendChild(<{parentXml.localName()} id={parentXml.@id} />);
					}
				}
			}
			// For each entity that has changed...
			for each (var childNode:XML in xmlElement.elements()) {
				// ...check if the child node is a property (i.e. it has no @id attribute)...
				if (XmlUtils.getTextContent(childNode, "@id").length == 0) {
					// ...and if its parent (entity) node has changed.
					if (changedEntity != null) {
						// If so, then add the property to the changedEntity node.
						changedEntity.appendChild(childNode.copy());
					}
				} else {
					// ...or a (reference to a) related entity.
					if (changedEntity != null) {
						// Add a reference to preserve foreign key relationships.
						changedEntity.appendChild(<{childNode.localName()} id={childNode.@id} />);
					}
					// Recurse the entities down the object tree.
					collectChangedEntities(childNode, changedSet, maxChangeId);
				}
			}

			if (changedEntity != null) {
				changedSet.appendChild(changedEntity);
			}
		}
		
		public function save(event:Event = null, nextTask:ChainableTask = null):void {
			timer.stop();
			if (status != PersistencyStatus.CHANGED) {
				if (nextTask != null) {
					nextTask.execute();
				}
				return;
			}
			
			var maxChangeId:int = changeId;
			var changedSet:XML = <set/>;
			for each (var xml:XML in xmlMap) {
				changedSet.setNamespace(xml.namespace());
				collectChangedEntities(xml, changedSet, maxChangeId);
			}
			collectDeletedEntities(deletedSet.elements(), changedSet, maxChangeId);
			
			// Send all changes to the REST server to create/update.
			var remoteInvoker:RemoteInvokerHttp = newRemoteInvokerHttp(URLRequestMethod.POST);
			remoteInvoker.errorCallback = saveErrorCallback;
			remoteInvoker.okCallback = saveOkCallback;
			remoteInvoker.requestXml = changedSet;
			remoteInvoker.context.changeId = maxChangeId;
			remoteInvoker.context.nextTask = nextTask;
			remoteInvoker.send();
			
			status = PersistencyStatus.SAVING;
			pendingChangeId = changeId;
		}
		private function saveErrorCallback(remoteInvoker:RemoteInvokerHttp):void {
			// Handle the REST server-response to the create/update-request.
			if (pendingChangeId <= remoteInvoker.context.changeId) {
				pendingChangeId = -1;
			}
			status = PersistencyStatus.CHANGED;
			// Check if a time-out occurred and the user was automatically logged out.
			if (remoteInvoker.getResponseCode() == 403) {
				Alert.show("Helaas, je bent niet (meer) ingelogd.", "FOUT").invalidateDisplayList();
				signOut();
			} else {
				errorHtmlText = remoteInvoker.getErrorResponseHtml();
			}
		}
		private function saveOkCallback(remoteInvoker:RemoteInvokerHttp):void {
			// Handle the REST server-response to the create/update-request.
			var context:Object = remoteInvoker.context;
			if (pendingChangeId <= context.changeId) {
				pendingChangeId = -1;
			}
			var responseXml:XML = remoteInvoker.getResponseXml();
			// Fill a entityTemporaryIdMap with the respons data
			var entityTemporaryIdMap:Object = {};
			for each (var responseElement:XML in responseXml.elements()) {
				var entityId:String = responseElement.localName();
				entityTemporaryIdMap[entityId] = {};
				for each (var id:XML in responseElement.id) {
					entityTemporaryIdMap[entityId][id.@temporary.toString()] = id.toString();
				}
			}
			// Reset changed-flags.
			for each (var xml:XML in xmlMap) {
				substituteTemporaryIdsAndResetFlags(xml, entityTemporaryIdMap, context.changeId);
			}

			// Remove deleted elements from the deletedSet.
			var i:int = 0;
			while (i < deletedSet.elements().length()) {
				if (deletedSet.elements()[i].@deleted <= context.changeId) {
					delete deletedSet.elements()[i];
				} else {
					i++;
				}
			}

			// Notify successful save.
			if (context.changeId == changeId) {
				lastSaved = new Date();
				status = PersistencyStatus.SAVED;
			}

			// Continue with any follow-up task, e.g. publishing data that had to be saved first.
			if (context.nextTask != null) {
				context.nextTask.execute(responseXml);
			}
		}

		// Reset changed-flags.
		private function substituteTemporaryIdsAndResetFlags(xmlElement:XML, entityTemporaryIdMap:Object,
															 maxChangeId:int):void {
			if (XmlUtils.getTextContent(xmlElement, "@id").length > 0) {
				// Reset any 'created' and 'changed' flags.
				if ((XmlUtils.getTextContent(xmlElement, "@created").length > 0)
						&& (xmlElement.@created <= maxChangeId)) {
					delete xmlElement.@created;
				}
				if ((XmlUtils.getTextContent(xmlElement, "@changed").length > 0)
						&& (xmlElement.@changed <= maxChangeId)) {
					delete xmlElement.@changed;
				}

				var temporaryObjectIdMap:Object = entityTemporaryIdMap[xmlElement.localName()];
				if (temporaryObjectIdMap != null) {
					var orgId:String = xmlElement.@id;
					var id:String = temporaryObjectIdMap[orgId];
					if (id != null) {
						xmlElement.@id = id;
					}
				}
			}
			// Recurse the node tree.
			for each (var xmlChild:XML in xmlElement.elements()) {
				substituteTemporaryIdsAndResetFlags(xmlChild, entityTemporaryIdMap, maxChangeId);
			}
		}
		
		public function saveAndPublish(xmlToBePublished:XML, nextTask:ChainableTask = null):void {
			// Save any changes to the REST server and publish the XML data.
			var publishRestTask:ChainableTask = new ChainableTask();
			publishRestTask.oneArgChainableMethod = publish;
			publishRestTask.argument = xmlToBePublished;
			publishRestTask.nextTask = nextTask;
			// Execute the chain.
			save(null, publishRestTask);
		}
		
		// Send a publish-request to the REST server.
		public function publish(xmlToBePublished:XML, nextTask:ChainableTask = null):void {
			if ((xmlToBePublished == null) || (xmlToBePublished.@published == "true")) {
				return;
			}

			if ((status == PersistencyStatus.CHANGED) || (status == PersistencyStatus.SAVING)) {
				throw Error("Some changes have not yet been saved; I won't publish unsaved data.");
			}
			status = PersistencyStatus.PUBLISHING;
			// Create a request XML indicating what is to be published.
			var publishedSet:XML =
				<set>
					<{xmlToBePublished.localName()} id={xmlToBePublished.@id} published='true' />
				</set>;

			// Request the REST server to publish the data.
			var remoteInvoker:RemoteInvokerHttp = newRemoteInvokerHttp(URLRequestMethod.POST);
			remoteInvoker.errorCallback = publishErrorCallback;
			remoteInvoker.okCallback = publishOkCallback;
			remoteInvoker.requestXml = publishedSet;
			remoteInvoker.context.xmlToBePublished = xmlToBePublished;
			remoteInvoker.context.nextTask = nextTask;
			remoteInvoker.context.changeId = changeId;
			remoteInvoker.send();
		}
		private function publishErrorCallback(remoteInvoker:RemoteInvokerHttp):void {
			// Restore the situation to the state it had before the request was issued.
			status = PersistencyStatus.UNCHANGED;
			// Check if a time-out occurred and the user was automatically logged out.
			if (remoteInvoker.getResponseCode() == 403) {
				Alert.show("Helaas, je bent niet (meer) ingelogd.", "FOUT").invalidateDisplayList();
				signOut();
			} else {
				errorHtmlText = remoteInvoker.getErrorResponseHtml();
			}
		}
		private function publishOkCallback(remoteInvoker:RemoteInvokerHttp):void {
			// Handle the REST server-response to the publish-request.
			var context:Object = remoteInvoker.context;
			setPublishedFlags(context.xmlToBePublished, context.changeId);
			
			// Notify successful publish.
			status = PersistencyStatus.SAVED;
			
			// Continue with any follow-up task.
			if (context.nextTask != null) {
				context.nextTask.execute();
			}
		}

		// Set published-flags.
		private function setPublishedFlags(xmlEntity:XML, maxChangeId:int):void {
			if ((XmlUtils.getTextContent(xmlEntity, "@id").length > 0) && (xmlEntity.@published != "true")
				&& ((xmlEntity.@created <= maxChangeId) || (xmlEntity.@changed <= maxChangeId))) {
				xmlEntity.@published = "true";
				// For each entity that has changed...
				for each (var node:XML in xmlEntity.elements()) {
					// ...recurse down the node tree.
					setPublishedFlags(node, maxChangeId);
				}
			}
		}
	}
}