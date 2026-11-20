import SwiftUI

/// Time and hop count shown beside a message while the thread is swiped left.
struct MessageSwipeDetails: View {
	static let width: CGFloat = 70

	let message: MessageEntity
	let isCurrentUser: Bool

	/// Same rule as Message Details: incoming, not via MQTT, and the sender's hop count is known.
	static func hopsText(isCurrentUser: Bool, viaMqtt: Bool, hopsAway: Int32?) -> String? {
		guard !isCurrentUser, !viaMqtt, let hopsAway else { return nil }
		return hopsAway == 0 ? String(localized: "Direct") : String(localized: "\(hopsAway) hops")
	}

	var body: some View {
		let node = message.fromUser?.userNode
		VStack(alignment: .leading, spacing: 2) {
			Text(message.timestamp.formatted(date: .omitted, time: .shortened))
			if let hops = Self.hopsText(isCurrentUser: isCurrentUser, viaMqtt: node?.viaMqtt ?? false, hopsAway: node?.hopsAway) {
				Text(hops)
			}
		}
		.font(.caption2)
		.foregroundColor(.gray)
		.frame(width: Self.width, alignment: .leading)
		.accessibilityHidden(true) // The swipe is a sighted shortcut; VoiceOver uses Message Details.
	}
}

extension View {
	/// Drag left to slide every row over and show `MessageSwipeDetails`; letting go snaps back.
	func messageSwipeReveal(_ offset: Binding<CGFloat>) -> some View {
		simultaneousGesture(
			DragGesture(minimumDistance: 20)
				.onChanged { value in
					let dx = value.translation.width
					// Ignore vertical scrolls, rightward drags and the edge the back swipe starts from.
					guard dx < 0, abs(dx) > abs(value.translation.height), value.startLocation.x > 20 else { return }
					offset.wrappedValue = max(dx, -MessageSwipeDetails.width)
				}
				.onEnded { _ in
					withAnimation(.spring) { offset.wrappedValue = 0 }
				}
		)
	}
}
