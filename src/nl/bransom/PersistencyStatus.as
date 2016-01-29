package nl.bransom {

	public class PersistencyStatus {

		public static const UNKNOWN:PersistencyStatus = new PersistencyStatus(UNKNOWN, 'onbekend');
		public static const READING:PersistencyStatus = new PersistencyStatus(READING, 'bezig met ophalen...');
		public static const UNCHANGED:PersistencyStatus = new PersistencyStatus(UNCHANGED, 'geen wijzigingen');
		public static const CHANGED:PersistencyStatus = new PersistencyStatus(CHANGED, 'gewijzigd');
		public static const SAVING:PersistencyStatus = new PersistencyStatus(SAVING, 'bezig met opslaan...');
		public static const SAVED:PersistencyStatus = new PersistencyStatus(SAVED, 'opgeslagen');
		public static const PUBLISHING:PersistencyStatus = new PersistencyStatus(PUBLISHING, 'bezig met publiceren...');

		private var label:String;

		public function PersistencyStatus(s:PersistencyStatus, label:String) {
			// constructor that accepts a 'copy' of itself for the recursive assignment to work
			this.label = label;
		}

		public function toString():String {
			return label;
		}
	}
}