import Testing

@testable import Meshtastic

@Suite("MessageSwipeDetails.hopsText")
struct MessageSwipeDetailsTests {

	@Test func incomingShowsHops() {
		#expect(MessageSwipeDetails.hopsText(isCurrentUser: false, viaMqtt: false, hopsAway: 3) == "3 hops")
	}

	@Test func oneHopIsSingular() {
		#expect(MessageSwipeDetails.hopsText(isCurrentUser: false, viaMqtt: false, hopsAway: 1) == "1 hop")
	}

	@Test func zeroHopsIsDirect() {
		#expect(MessageSwipeDetails.hopsText(isCurrentUser: false, viaMqtt: false, hopsAway: 0) == "Direct")
	}

	@Test func hiddenWhenOutgoingMqttOrUnknown() {
		#expect(MessageSwipeDetails.hopsText(isCurrentUser: true, viaMqtt: false, hopsAway: 2) == nil)
		#expect(MessageSwipeDetails.hopsText(isCurrentUser: false, viaMqtt: true, hopsAway: 2) == nil)
		#expect(MessageSwipeDetails.hopsText(isCurrentUser: false, viaMqtt: false, hopsAway: nil) == nil)
	}
}
