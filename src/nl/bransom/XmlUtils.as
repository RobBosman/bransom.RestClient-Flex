package nl.bransom {
	import flash.xml.XMLNode;

	public class XmlUtils  {
		
		private static const TEMPORARY_ID_PREFIX:String = "T";

		private static var numCreatedObjects:int = 0;
		
		public static function escapeHtml(xmlText:String):String {
			return  new XMLNode(3, xmlText).toString();
		}

		public static function getElements(xmlParent:XML, field:String):XMLList {
			if ((xmlParent == null) || (field == null)) {
				return new XMLList();
			}
			var elements:XMLList = xmlParent.elements(field);
			if (elements.length() == 0) {
				var ns:Namespace = xmlParent.namespace();
				if (ns != null) {
					elements = xmlParent.elements(new QName(ns, field));
				}
			}
			return elements;
		}

		public static function getTextContent(xmlParent:XML, field:String):String {
			if (xmlParent == null) {
				return "";
			}
			var childNodes:XMLList;
			if (field.charAt(0) == '@') {
				childNodes = xmlParent.attribute(field.substr(1));
			} else {
				childNodes = getElements(xmlParent, field);
			}
			if (childNodes.length() > 0) {
				return childNodes[0].toString();
			}
			return "";
		}

		public static function setTextContent(xmlParent:XML, field:String, value:String, asCData:Boolean = false):XML {
			var childNodes:XMLList = getElements(xmlParent, field);
			if (value == null) {
				if (childNodes != null) {
					delete childNodes[0];
				}
				return null;
			}

			if (field.charAt(0) == '@') {
				if (field == "@id") {
					xmlParent.@id = value;
					return xmlParent.@id[0];
				} else {
					throw new Error("Setting attribute '" + field + "' is not really supported...");
				}
			} else {
				var xmlChild:XML;
				// Create the node if necessary.
				if (childNodes.length() == 0) {
					xmlChild = <{field}>{value}</{field}>;
					xmlChild.setNamespace(xmlParent.namespace());
					xmlParent.appendChild(xmlChild);
				} else {
					childNodes[0] = value;
					xmlChild = childNodes[0];
				}
				// Apply the value.
				if ((asCData) && (value.length > 0)) {
					xmlChild.replace("*", new XML("<![CDATA[" + value + "]]>"));
				} else {
					xmlChild.replace("*", value);
				}
				return xmlChild;
			}
		}
		
		public static function addReferenceNode(xmlParent:XML, field:String, refId:String):Boolean {
			for each (var refXml:XML in getElements(xmlParent, field)) {
				if (refXml.@id == refId) {
					// The reference is already present.
					return false;
				}
			}
			// Add the reference.
			var newRefXml:XML = <{field} id={refId} />;
			newRefXml.setNamespace(xmlParent.namespace());
			xmlParent.appendChild(newRefXml);
			return true;
		}
		
		public static function removeReferenceNode(xmlParent:XML, field:String, refId:String):Boolean {
			var hasChanged:Boolean = false;
			// Remove all matching references.
			var siblings:XMLList = xmlParent.children();
			for (var index:int = 0; index < siblings.length(); index++) {
				var refXml:XML = siblings[index];
				if ((refXml.localName() == field) && (refXml.@id == refId)) {
					delete siblings[index];
					hasChanged = true;
				}
			}
			return hasChanged;
		}
		
		public static function compareProperties(xmlA:XML, xmlB:XML, fieldName:String, sortOptions:int = -1):int {
			var propertyA:String = getTextContent(xmlA, fieldName);
			var propertyB:String = getTextContent(xmlB, fieldName);
			return compareStrings(propertyA, propertyB, sortOptions);
		}
		
		public static function compareComboOptions(comboOptions:Array, a:Object, b:Object, fieldName:String,
												   sortOptions:int = -1):int {
			var propertyA:String = getTextContent(a as XML, fieldName);
			var propertyB:String = getTextContent(b as XML, fieldName);
			var comboOption:Object = getComboOption(comboOptions, propertyA);
			if (comboOption != null) {
				propertyA = comboOption.label;
			}
			comboOption = getComboOption(comboOptions, propertyB);
			if (comboOption != null) {
				propertyB = comboOption.label;
			}
			return compareStrings(propertyA, propertyB, sortOptions);
		}
		
		public static function getComboOption(allOptions:Array, optionData:Object):Object {
			for each (var option:Object in allOptions) {
				if (option.data == optionData) {
					return option;
				}
			}
			return null;
		}
		
		private static function compareStrings(a:String, b:String, sortOptions:int):int {
			var compareNumeric:Boolean = false;
			var compareCaseInsensitive:Boolean = false;
			var reverseSortOrder:Boolean = false;
			if (sortOptions != -1) {
				compareNumeric = ((sortOptions & Array.NUMERIC) != 0) as Boolean;
				compareCaseInsensitive = ((sortOptions & Array.CASEINSENSITIVE) != 0) as Boolean;
				reverseSortOrder = ((sortOptions & Array.DESCENDING) != 0) as Boolean;
			}
			// Put empty strings at the front (default) or back of the sorted result.
			var compare:int = 0;
			if ((a == "") && (b == "")) {
				compare = 0;
			} else if (a == "") {
				compare = 1;
			} else if (b == "") {
				compare = -1;
			} else if (compareNumeric) {
				compare = (a as Number) - (b as Number);
			} else {
				if (compareCaseInsensitive) {
					// Compare case-insensitive.
					a = a.toUpperCase();
					b = b.toUpperCase();
				}
				if (a < b) {
					compare = -1;
				} else if (a > b) {
					compare = 1;
				}
			}
			if (reverseSortOrder) {
				// Reverse sorting order.
				compare = -compare;
			}
			return compare;
		}

		public static function createEntityNode(xmlParent:XML, entityName:String, insertIndex:Number = -1):XML {
			// Create a node with an existing or a temporary id.
			var temporaryId:String = TEMPORARY_ID_PREFIX + numCreatedObjects++;
			var xmlCreated:XML = <{entityName} id={temporaryId} />;
			if (xmlParent != null) {
				xmlCreated.setNamespace(xmlParent.namespace());
				if (insertIndex < 0) {
					xmlParent.prependChild(xmlCreated);
				} else {
					var xmlSiblings:XMLList = getElements(xmlParent, entityName);
					if (insertIndex < xmlSiblings.length()) {
						xmlParent.insertChildBefore(xmlSiblings[insertIndex], xmlCreated);
					} else {
						xmlParent.appendChild(xmlCreated);
					}
				}
			}
			return xmlCreated;
		}

		public static function deleteEntityNode(xmlToBeDeleted:XML):XML {
			var deletedXmlRef:XML = null;
			if (xmlToBeDeleted != null) {
				var entityName:String = xmlToBeDeleted.localName();
				var id:String = xmlToBeDeleted.@id;
				deletedXmlRef = <{entityName} id={id} />;
				var xmlParent:XML = xmlToBeDeleted.parent();
				if (xmlParent != null) {
					// Delete the entity node.
					var siblings:XMLList = xmlParent.children();
					for (var index:int = 0; index < siblings.length(); index++) {
						if (siblings[index] == xmlToBeDeleted) {
							delete siblings[index];
							break;
						}
					}
				}
			}
			return deletedXmlRef;
		}
		
		/**
		 * Sorts a list of XML nodes.
		 * 
		 * @param xmlList: collection of XML nodes that will be sorted
		 * @param keyField: name of XML element or attribute that acts as the sort key
		 * @param sortOptions: OR-ed set of sort parameters, e.g. Array.DESCENDING | Array.NUMERIC
		 * see http://help.adobe.com/en_US/FlashPlatform/reference/actionscript/3/Array.html#sortOn()
		 * @param sortNullAtFront: if true, then nodes whoé key is empty or absent are sorted on top of the list
		 * @return sorted copy of XMLList
		 */
		public static function sortXmlList(xmlList:XMLList, keyField:String, sortOptions:int = 0,
										   sortNullAtFront:Boolean = false):XMLList {
			return multiSortXmlList(xmlList, [keyField], [sortOptions], [sortNullAtFront]);
		}

		public static function multiSortXmlList(xmlList:XMLList, keyFields:Array, sortOptionsList:Array = null,
												sortNullAtFrontList:Array = null):XMLList {
			var keyNames:Array = [];
			for (var k:int = 0; k < keyFields.length; k++) {
				keyNames.push("key" + k);
			}

			var xmlArray:Array = [];
			for each (var xmlItem:XML in xmlList) {
				var object:Object = {
					"value":xmlItem
				};
				var i:int = 0;
				for each (var keyField:String in keyFields) {
					var keyName:String = keyNames[i];
					object[keyName] = getTextContent(xmlItem, keyField);
					i++;
				}
				xmlArray.push(object);
			}
			
			// Sort the objects in the array.
			xmlArray.sortOn(keyNames, sortOptionsList);
			
			// Create a XMLListCollection and add all XML items in the correct order.
			var sortedXmlList:XMLList = new XMLList();
			// Note that sortOn() puts null-keys at the end of the collection. So if sortNullAtFront is 'true'...
			if (sortNullAtFrontList != null) {
				// ...then add the null-objects first and remove them from xmlArray.
				var n:int = 0;
				for each (var sortNullAtFront:Boolean in sortNullAtFrontList) {
					if (sortNullAtFront) {
						var nullKeyName:String = keyNames[n];
						for each (var nullObject:Object in xmlArray) {
							if (nullObject[nullKeyName] == "") {
								sortedXmlList += nullObject.value;
								xmlArray.splice(xmlArray.indexOf(nullObject), 1);
							}
						}
					}
					n++;
				}
			}
			// Add all (remaining) XML nodes to the result list.
			for each (var arrayObject:Object in xmlArray) {
				sortedXmlList += arrayObject.value;
			}
			return sortedXmlList;
		}
	}
}