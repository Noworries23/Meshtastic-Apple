//
//  SessionDataExporter.swift
//  Meshtastic
//

import Foundation
import SwiftData

enum SessionDataExporter {
	private static let schemaVersion = "1.0"
	private static let batchSize = 500

	private struct Manifest: Codable {
		let sessionId: UUID
		let name: String
		let activity: String
		let startedAt: Date
		let endedAt: Date?
		let schemaVersion: String
		let totalGPSCount: Int
		let totalRadioObservationCount: Int
	}

	private struct GPSPoint: Codable {
		let id: UUID
		let sessionId: UUID
		let recordedAt: Date
		let latitude: Double
		let longitude: Double
		let altitude: Double
		let horizontalAccuracy: Double
		let verticalAccuracy: Double
		let speed: Double
		let course: Double

		init(_ observation: GPSObservationEntity) {
			id = observation.id
			sessionId = observation.sessionId
			recordedAt = observation.recordedAt
			latitude = observation.latitude
			longitude = observation.longitude
			altitude = observation.altitude
			horizontalAccuracy = observation.horizontalAccuracy
			verticalAccuracy = observation.verticalAccuracy
			speed = observation.speed
			course = observation.course
		}
	}

	private struct RadioObservation: Codable {
		let id: UUID
		let sessionId: UUID
		let receivedAt: Date
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

		init(_ observation: RadioObservationEntity) {
			id = observation.id
			sessionId = observation.sessionId
			receivedAt = observation.receivedAt
			fromNode = observation.fromNode
			toNode = observation.toNode
			packetId = observation.packetId
			portNum = observation.portNum
			channel = observation.channel
			hopStart = observation.hopStart
			hopLimit = observation.hopLimit
			rssi = observation.rssi
			snr = observation.snr
			viaMqtt = observation.viaMqtt
			rawPayload = observation.rawPayload
		}
	}

	static func export(session: LoggingSessionEntity, context: ModelContext) throws -> URL {
		let gpsPredicate = #Predicate<GPSObservationEntity> { observation in
			observation.sessionId == session.id
		}
		let radioPredicate = #Predicate<RadioObservationEntity> { observation in
			observation.sessionId == session.id
		}
		let gpsCount = try context.fetchCount(FetchDescriptor<GPSObservationEntity>(predicate: gpsPredicate))
		let radioCount = try context.fetchCount(FetchDescriptor<RadioObservationEntity>(predicate: radioPredicate))

		let directory = FileManager.default.temporaryDirectory
			.appendingPathComponent("field-session-\(session.id.uuidString)", isDirectory: true)
		try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

		do {
			let encoder = JSONEncoder()
			encoder.dateEncodingStrategy = .iso8601
			encoder.outputFormatting = [.sortedKeys]

			let manifest = Manifest(
				sessionId: session.id,
				name: session.name,
				activity: session.activity,
				startedAt: session.startedAt,
				endedAt: session.endedAt,
				schemaVersion: schemaVersion,
				totalGPSCount: gpsCount,
				totalRadioObservationCount: radioCount
			)
			try encoder.encode(manifest).write(to: directory.appendingPathComponent("manifest.json"), options: .atomic)

			try writeGPSPoints(
				predicate: gpsPredicate,
				context: context,
				encoder: encoder,
				to: directory.appendingPathComponent("gps_points.jsonl")
			)
			try writeRadioObservations(
				predicate: radioPredicate,
				context: context,
				encoder: encoder,
				to: directory.appendingPathComponent("radio_observations.jsonl")
			)
			return directory
		} catch {
			try? FileManager.default.removeItem(at: directory)
			throw error
		}
	}

	private static func writeGPSPoints(
		predicate: Predicate<GPSObservationEntity>,
		context: ModelContext,
		encoder: JSONEncoder,
		to url: URL
	) throws {
		FileManager.default.createFile(atPath: url.path, contents: nil)
		let handle = try FileHandle(forWritingTo: url)
		defer { try? handle.close() }

		var offset = 0
		while true {
			var descriptor = FetchDescriptor<GPSObservationEntity>(predicate: predicate)
			descriptor.fetchLimit = batchSize
			descriptor.fetchOffset = offset
			descriptor.sortBy = [SortDescriptor(\.recordedAt)]
			let batch = try context.fetch(descriptor)
			guard !batch.isEmpty else { return }
			for observation in batch {
				try handle.write(contentsOf: encoder.encode(GPSPoint(observation)) + Data([0x0A]))
			}
			offset += batch.count
			if batch.count < batchSize { return }
		}
	}

	private static func writeRadioObservations(
		predicate: Predicate<RadioObservationEntity>,
		context: ModelContext,
		encoder: JSONEncoder,
		to url: URL
	) throws {
		FileManager.default.createFile(atPath: url.path, contents: nil)
		let handle = try FileHandle(forWritingTo: url)
		defer { try? handle.close() }

		var offset = 0
		while true {
			var descriptor = FetchDescriptor<RadioObservationEntity>(predicate: predicate)
			descriptor.fetchLimit = batchSize
			descriptor.fetchOffset = offset
			descriptor.sortBy = [SortDescriptor(\.receivedAt)]
			let batch = try context.fetch(descriptor)
			guard !batch.isEmpty else { return }
			for observation in batch {
				try handle.write(contentsOf: encoder.encode(RadioObservation(observation)) + Data([0x0A]))
			}
			offset += batch.count
			if batch.count < batchSize { return }
		}
	}
}
