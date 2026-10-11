//
//  SessionStorageCalculator.swift
//  Meshtastic
//

import Foundation
import SwiftData

struct SessionStorageSummary: Sendable {
	let gpsObservationCount: Int
	let radioObservationCount: Int
	let estimatedBytes: Int64

	var estimatedMegabytes: Double {
		Double(estimatedBytes) / 1_048_576
	}
}

final class SessionStorageCalculator {
	private static let gpsObservationEstimatedBytes: Int64 = 104
	private static let radioObservationBaseEstimatedBytes: Int64 = 125

	private init() {}

	static func summary(sessionId: UUID, context: ModelContext) throws -> SessionStorageSummary {
		let gpsPredicate = #Predicate<GPSObservationEntity> { observation in
			observation.sessionId == sessionId
		}
		let radioPredicate = #Predicate<RadioObservationEntity> { observation in
			observation.sessionId == sessionId
		}

		let gpsCount = try context.fetchCount(FetchDescriptor(predicate: gpsPredicate))
		let radioObservations = try context.fetch(
			FetchDescriptor<RadioObservationEntity>(predicate: radioPredicate)
		)
		let estimatedRadioBytes = radioObservations.reduce(into: Int64(0)) { total, observation in
			total += radioObservationBaseEstimatedBytes + Int64(observation.rawPayload?.count ?? 0)
		}

		return SessionStorageSummary(
			gpsObservationCount: gpsCount,
			radioObservationCount: radioObservations.count,
			estimatedBytes: Int64(gpsCount) * gpsObservationEstimatedBytes + estimatedRadioBytes
		)
	}

	static func totalStorageBytes(context: ModelContext) throws -> Int64 {
		let sessions = try context.fetch(FetchDescriptor<LoggingSessionEntity>())
		let sessionBytes = sessions.reduce(into: Int64(0)) { total, session in
			total += Int64(session.name.utf8.count + session.activity.utf8.count + session.presetRawValue.utf8.count)
			total += Int64(session.configurationData?.count ?? 0)
		}

		let observationBytes = try sessions.reduce(into: Int64(0)) { total, session in
			total += try summary(sessionId: session.id, context: context).estimatedBytes
		}
		return observationBytes + sessionBytes
	}

	static func deleteSession(id: UUID, context: ModelContext) throws {
		let gpsPredicate = #Predicate<GPSObservationEntity> { observation in
			observation.sessionId == id
		}
		let radioPredicate = #Predicate<RadioObservationEntity> { observation in
			observation.sessionId == id
		}
		let sessionPredicate = #Predicate<LoggingSessionEntity> { session in
			session.id == id
		}

		for observation in try context.fetch(FetchDescriptor<GPSObservationEntity>(predicate: gpsPredicate)) {
			context.delete(observation)
		}
		for observation in try context.fetch(FetchDescriptor<RadioObservationEntity>(predicate: radioPredicate)) {
			context.delete(observation)
		}
		for session in try context.fetch(FetchDescriptor<LoggingSessionEntity>(predicate: sessionPredicate)) {
			context.delete(session)
		}
		try context.save()
	}

	static func pruneSessions(olderThan maxAgeDays: Int, context: ModelContext) throws {
		guard maxAgeDays >= 0 else { return }

		let cutoff = Date(timeIntervalSinceNow: -Double(maxAgeDays) * 86_400)
		let predicate = #Predicate<LoggingSessionEntity> { session in
			session.startedAt < cutoff
		}
		let sessionIDs = try context.fetch(FetchDescriptor<LoggingSessionEntity>(predicate: predicate)).map(\.id)

		for sessionID in sessionIDs {
			try deleteSession(id: sessionID, context: context)
		}
	}
}
