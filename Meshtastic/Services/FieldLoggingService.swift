//
//  FieldLoggingService.swift
//  Meshtastic
//

import CoreLocation
import Foundation
import SwiftData
import UserNotifications

struct RadioPacketMetaData: Sendable {
	let fromNode: UInt32
	let toNode: UInt32
	let packetId: UInt32
	let portNum: Int
	let channel: Int
	let hopStart: Int?
	let hopLimit: Int?
	let rssi: Int?
	let snr: Float?
	let viaMqtt: Bool
	let rawPayload: Data?
}

@MainActor
final class FieldLoggingService {
	enum StopReason {
		case maxDurationReached
		case maxStorageReached

		var notificationBody: String {
			switch self {
			case .maxDurationReached:
				return String(localized: "The field logging session reached its maximum duration and was stopped.")
			case .maxStorageReached:
				return String(localized: "The field logging session reached its maximum storage limit and was stopped.")
			}
		}
	}

	static let shared = FieldLoggingService(modelContext: PersistenceController.shared.context)

	private static let storageCheckInterval = 25
	private static let durationCheckInterval: Duration = .seconds(30)

	private let modelContext: ModelContext
	private weak var locationManager: CLLocationManager?
	private(set) var activeConfiguration: FieldLoggingConfiguration?

	private(set) var activeSessionId: UUID?
	private var observationCountSinceStorageCheck = 0
	private var durationMonitor: Task<Void, Never>?

	init(modelContext: ModelContext) {
		self.modelContext = modelContext
	}

	func attachLocationManager(_ manager: CLLocationManager) {
		locationManager = manager
	}

	func startSession(config: FieldLoggingConfiguration, name: String) -> LoggingSessionEntity {
		let configurationData: Data?
		do {
			configurationData = try JSONEncoder().encode(config)
		} catch {
			Logger.data.error("Failed to encode field logging configuration: \(error.localizedDescription, privacy: .public)")
			configurationData = nil
		}
		let session = LoggingSessionEntity(
			name: name,
			activity: LoggingPreset.custom.rawValue,
			startedAt: Date(),
			presetRawValue: LoggingPreset.custom.rawValue,
			configurationData: configurationData
		)
		modelContext.insert(session)
		activeSessionId = session.id
		activeConfiguration = config
		observationCountSinceStorageCheck = 0
		startDurationMonitor()
		apply(config: config)
		return session
	}

	func stopActiveSession() {
		stopActiveSession(reason: nil)
	}

	func stopActiveSession(reason: StopReason?) {
		guard let activeSessionId else { return }
		durationMonitor?.cancel()
		durationMonitor = nil

		let descriptor = FetchDescriptor<LoggingSessionEntity>(
			predicate: #Predicate { session in
				session.id == activeSessionId
			}
		)

		do {
			guard let session = try modelContext.fetch(descriptor).first else {
				Logger.data.error("Field logging session \(activeSessionId.uuidString, privacy: .public) could not be found while stopping")
				self.activeSessionId = nil
				activeConfiguration = nil
				resetLocationManager()
				postLimitNotification(for: reason)
				return
			}

			session.endedAt = Date()
			self.activeSessionId = nil
			activeConfiguration = nil
			observationCountSinceStorageCheck = 0
			resetLocationManager()
			postLimitNotification(for: reason)
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
		checkStorageLimitIfNeeded()
	}

	func logRadioObservation(packetMetaData: RadioPacketMetaData) {
		guard let activeSessionId else { return }

		let sessionDescriptor = FetchDescriptor<LoggingSessionEntity>(
			predicate: #Predicate { session in
				session.id == activeSessionId
			}
		)

		do {
			guard let session = try modelContext.fetch(sessionDescriptor).first else {
				Logger.data.error("Could not resolve the active field logging session preset")
				return
			}
			let configuration = activeConfiguration
				?? session.configurationData.flatMap { try? JSONDecoder().decode(FieldLoggingConfiguration.self, from: $0) }
				?? .preset(LoggingPreset(rawValue: session.presetRawValue) ?? .balanced)

			let observation = RadioObservationEntity(
				sessionId: activeSessionId,
				receivedAt: Date(),
				fromNode: packetMetaData.fromNode,
				toNode: packetMetaData.toNode,
				packetId: packetMetaData.packetId,
				portNum: packetMetaData.portNum,
				channel: packetMetaData.channel,
				hopStart: packetMetaData.hopStart,
				hopLimit: packetMetaData.hopLimit,
				rssi: packetMetaData.rssi,
				snr: packetMetaData.snr,
				viaMqtt: packetMetaData.viaMqtt,
				rawPayload: configuration.logRawPayloads ? packetMetaData.rawPayload : nil
			)
			modelContext.insert(observation)
			checkStorageLimitIfNeeded()

			Task { @MainActor [weak self] in
				guard let self else { return }
				do {
					try modelContext.save()
				} catch {
					Logger.data.error("Failed to save field radio observation: \(error.localizedDescription, privacy: .public)")
				}
			}
		} catch {
			Logger.data.error("Failed to load the active field logging session: \(error.localizedDescription, privacy: .public)")
		}
	}

	private func startDurationMonitor() {
		durationMonitor?.cancel()
		durationMonitor = Task { @MainActor [weak self] in
			while !Task.isCancelled {
				do {
					try await Task.sleep(for: Self.durationCheckInterval)
				} catch {
					return
				}
				self?.checkDurationLimit()
			}
		}
	}

	private func checkDurationLimit() {
		guard let activeSessionId,
			  let maxDuration = activeConfiguration?.maxDuration,
			  maxDuration > 0 else { return }

		let descriptor = FetchDescriptor<LoggingSessionEntity>(
			predicate: #Predicate { session in
				session.id == activeSessionId
			}
		)
		guard let session = try? modelContext.fetch(descriptor).first,
			  let session,
			  Date().timeIntervalSince(session.startedAt) >= maxDuration else { return }

		stopActiveSession(reason: .maxDurationReached)
	}

	private func checkStorageLimitIfNeeded() {
		guard activeSessionId != nil,
			  let maxStorageMB = activeConfiguration?.maxStorageMB,
			  maxStorageMB > 0 else { return }

		observationCountSinceStorageCheck += 1
		guard observationCountSinceStorageCheck >= Self.storageCheckInterval else { return }
		observationCountSinceStorageCheck = 0

		guard let activeSessionId,
			  let summary = try? SessionStorageCalculator.summary(sessionId: activeSessionId, context: modelContext),
			  summary.estimatedMegabytes >= Double(maxStorageMB) else { return }

		stopActiveSession(reason: .maxStorageReached)
	}

	private func postLimitNotification(for reason: StopReason?) {
		guard let reason else { return }

		let content = UNMutableNotificationContent()
		content.title = String(localized: "Field Logging Stopped")
		content.body = reason.notificationBody
		content.sound = .default
		let request = UNNotificationRequest(
			identifier: "field-logging-limit-\(UUID().uuidString)",
			content: content,
			trigger: UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
		)

		UNUserNotificationCenter.current().add(request) { error in
			if let error {
				Logger.services.error("Failed to post field logging limit notification: \(error.localizedDescription, privacy: .public)")
			}
		}
	}

	private func apply(config: FieldLoggingConfiguration) {
		locationManager?.desiredAccuracy = config.desiredAccuracy
		locationManager?.distanceFilter = config.distanceFilter
	}

	private func resetLocationManager() {
		locationManager?.desiredAccuracy = kCLLocationAccuracyHundredMeters
		locationManager?.distanceFilter = 10
	}
}
