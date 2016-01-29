package nl.bransom {

	public class ChainableTask {

		public var oneArgChainableMethod:Function;
		public var argument:*;
		public var nextTask:ChainableTask;
		
		public function ChainableTask(oneArgChainableMethod:Function = null) {
			this.oneArgChainableMethod = oneArgChainableMethod;
		}
		
		public function execute(arg:* = null):void {
			if (argument == null) {
				argument = arg;
			}
			oneArgChainableMethod(argument, nextTask);
		}

	}
}