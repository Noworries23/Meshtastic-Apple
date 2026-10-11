//
//  FieldLoggingService.swift
//  Meshtastic
//

import CoreLocation
import Foundation
import SwiftData

typealias LoggingPreset = FieldLoggingPreset

@MainActor
final class FieldLoggingService {
	private let modelContext: ModelContext

	private(set) var activeSessionId: UUID?

	init(modelContext: ModelContext) {
		self.modelContext = modelContext
	}

	func startSession(preset: LoggingPreset, name: String) -> LoggingSessionEntity {
		let session = LoggingSessionEntity(
			name: name,
			activity: preset.rawValue,
			startedAt: Date(),
			presetRawValue: preset.rawValue
		)
		modelContext.insert(session)
		activeSessionId = session.id
		return session
	}

	func stopActiveSession() {
		guard let activeSessionId else { return }

		let descriptor = FetchDescriptor<LoggingSessionEntity>(
			predicate: #Predicate { session in
				session.id == activeSessionId
			}
		)

		do {
			guard let session = try modelContext.fetch(descriptor).first else {
				Logger.data.error("Field logging session \(activeSessionId.uuidString, privacy: .public) could not be found while stopping")
				self.activeSessionId = nil
				return
			}

			session.endedAt = Date()
			self.activeSessionId = nil
		} catch {
			Logger.data.error("Failed to stop field logging session: \(error.localizedDescription, privacy: .public)")
		}
	}

	func logGPSPoint(_ location: CLLocation) {
		guard let activeSessionId else { return }

		let observation = GPSObservationEntity(
			sessionId: activeSessionId,
			recordedAt: location.timestamp,
			latitude: location.coordinate.latitude,
			longitude: location.coordinate.longitude,
			altitude: location.altitude,
			horizontalAccuracy: location.horizontalAccuracy,
			verticalAccuracy: location.verticalAccuracy,
			speed: location.speed,
			course: location.course
		)
		modelContext.insert(observation)
	}
}
