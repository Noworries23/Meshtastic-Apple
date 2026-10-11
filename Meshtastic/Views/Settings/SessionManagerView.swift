//
//  SessionManagerView.swift
//  Meshtastic
//

import UIKit
import SwiftData
import SwiftUI

struct SessionManagerView: View {
	@Environment(\.modelContext) private var context

	@Query(sort: \LoggingSessionEntity.startedAt, order: .reverse)
	private var sessions: [LoggingSessionEntity]

	@State private var summaries: [UUID: SessionStorageSummary] = [:]
	@State private var totalStorageBytes: Int64 = 0
	@State private var isShowingPruneOptions = false
	@State private var exportingSessionID: UUID?
	@State private var exportedFile: ShareableFile?
	@State private var pendingCleanupSessionID: UUID?
	@State private var pendingCleanupSessionName = ""
	@State private var isShowingCleanupPrompt = false
	@State private var exportError: String?

	var body: some View {
		List {
			storageOverview

			if sessions.isEmpty {
				ContentUnavailableView(
					"No Field Sessions",
					systemImage: "record.circle",
					description: Text("Start a field logging session to see it here.")
				)
			} else {
				ForEach(sessions, id: \.id) { session in
					sessionRow(session)
						.swipeActions(edge: .trailing, allowsFullSwipe: false) {
							Button(role: .destructive) {
								delete(session)
							} label: {
								Label("Delete", systemImage: "trash")
							}
						}
				}
			}
		}
		.navigationTitle("Field Sessions")
		.confirmationDialog(
			"Prune Old Sessions",
			isPresented: $isShowingPruneOptions,
			titleVisibility: .visible
		) {
			Button("Delete Older Than 7 Days", role: .destructive) {
				pruneSessions(olderThan: 7)
			}
			Button("Delete Older Than 30 Days", role: .destructive) {
				pruneSessions(olderThan: 30)
			}
			Button("Delete Older Than 90 Days", role: .destructive) {
				pruneSessions(olderThan: 90)
			}
			Button("Cancel", role: .cancel) {}
		} message: {
			Text("This permanently deletes matching sessions and their recorded observations.")
		}
		.sheet(item: $exportedFile, onDismiss: {
			guard pendingCleanupSessionID != nil else { return }
			isShowingCleanupPrompt = true
		}) { file in
			SessionShareSheet(url: file.url)
		}
		.sheet(isPresented: $isShowingCleanupPrompt, onDismiss: {
			pendingCleanupSessionID = nil
		}) {
			CleanupAfterExportView(
				sessionName: pendingCleanupSessionName,
				onKeep: {
					isShowingCleanupPrompt = false
				},
				onDelete: {
					if let sessionID = pendingCleanupSessionID {
						deleteSession(id: sessionID)
					}
					isShowingCleanupPrompt = false
				}
			)
		}
		.alert("Export Failed", isPresented: Binding(
			get: { exportError != nil },
			set: { if !$0 { exportError = nil } }
		)) {
			Button("OK", role: .cancel) {}
		} message: {
			Text(exportError ?? "The session could not be exported.")
		}
		.task(id: sessions.map(\.id)) {
			refreshSummaries()
		}
	}

	private var storageOverview: some View {
		Section {
			VStack(alignment: .leading, spacing: 8) {
				Label("Field Logging Storage", systemImage: "externaldrive")
					.font(.headline)
				Text(ByteCountFormatter.string(fromByteCount: totalStorageBytes, countStyle: .file))
					.font(.title3)
					.monospacedDigit()
				Button {
					isShowingPruneOptions = true
				} label: {
					Label("Prune Old Sessions", systemImage: "trash")
				}
				.buttonStyle(.bordered)
			}
			.padding(.vertical, 4)
		} footer: {
			Text("Storage is an estimate based on recorded observations and optional raw payloads.")
		}
	}

	private func sessionRow(_ session: LoggingSessionEntity) -> some View {
		let summary = summaries[session.id]

		return VStack(alignment: .leading, spacing: 6) {
			HStack {
				VStack(alignment: .leading, spacing: 2) {
					Text(session.name)
						.font(.headline)
					Text(session.startedAt.formatted(date: .abbreviated, time: .shortened))
						.font(.subheadline)
						.foregroundStyle(.secondary)
				}
				Spacer()
				statusLabel(for: session)
			}

			HStack(spacing: 12) {
				Label(duration(for: session), systemImage: "clock")
				Label("\(summary?.gpsObservationCount ?? 0)", systemImage: "location")
				Label("\(summary?.radioObservationCount ?? 0)", systemImage: "dot.radiowaves.left.and.right")
				Label(storageText(for: summary), systemImage: "internaldrive")
			}
			.font(.caption)
			.foregroundStyle(.secondary)
			.lineLimit(1)

			Button {
				export(session)
			} label: {
				if exportingSessionID == session.id {
					ProgressView()
						.controlSize(.small)
					Text("Exporting…")
				} else {
					Label("Export Session", systemImage: "square.and.arrow.up")
				}
			}
			.buttonStyle(.bordered)
			.disabled(exportingSessionID != nil)
		}
		.padding(.vertical, 4)
	}

	@ViewBuilder
	private func statusLabel(for session: LoggingSessionEntity) -> some View {
		if session.endedAt == nil {
			Label("Active", systemImage: "record.circle.fill")
				.foregroundStyle(.red)
				.font(.caption.weight(.semibold))
		} else {
			Text("Completed")
				.font(.caption)
				.foregroundStyle(.secondary)
		}
	}

	private func duration(for session: LoggingSessionEntity) -> String {
		let end = session.endedAt ?? Date()
		return durationFormatter.string(from: end.timeIntervalSince(session.startedAt))
	}

	private func storageText(for summary: SessionStorageSummary?) -> String {
		guard let summary else { return "—" }
		return ByteCountFormatter.string(fromByteCount: summary.estimatedBytes, countStyle: .file)
	}

	private var durationFormatter: DateComponentsFormatter {
		let formatter = DateComponentsFormatter()
		formatter.allowedUnits = [.day, .hour, .minute]
		formatter.unitsStyle = .abbreviated
		return formatter
	}

	private func refreshSummaries() {
		var refreshedSummaries: [UUID: SessionStorageSummary] = [:]
		for session in sessions {
			do {
				refreshedSummaries[session.id] = try SessionStorageCalculator.summary(
					sessionId: session.id,
					context: context
				)
			} catch {
				Logger.data.error("Failed to calculate field session storage: \(error.localizedDescription, privacy: .public)")
			}
		}
		summaries = refreshedSummaries

		do {
			totalStorageBytes = try SessionStorageCalculator.totalStorageBytes(context: context)
		} catch {
			Logger.data.error("Failed to calculate total field logging storage: \(error.localizedDescription, privacy: .public)")
		}
	}

	private func delete(_ session: LoggingSessionEntity) {
		deleteSession(id: session.id)
	}

	private func deleteSession(id: UUID) {
		do {
			try SessionStorageCalculator.deleteSession(id: id, context: context)
			refreshSummaries()
		} catch {
			Logger.data.error("Failed to delete field logging session: \(error.localizedDescription, privacy: .public)")
		}
	}

	private func pruneSessions(olderThan days: Int) {
		do {
			try SessionStorageCalculator.pruneSessions(olderThan: days, context: context)
			refreshSummaries()
		} catch {
			Logger.data.error("Failed to prune field logging sessions: \(error.localizedDescription, privacy: .public)")
		}
	}

	private func export(_ session: LoggingSessionEntity) {
		guard exportingSessionID == nil else { return }

		exportingSessionID = session.id
		let sessionID = session.id
		let sessionName = session.name
		let container = context.container

		Task {
			do {
				let url = try await Task.detached(priority: .userInitiated) {
					let backgroundContext = ModelContext(container)
					let descriptor = FetchDescriptor<LoggingSessionEntity>(
						predicate: #Predicate { session in
							session.id == sessionID
						}
					)
					guard let session = try backgroundContext.fetch(descriptor).first else {
						throw SessionExportError.sessionNotFound
					}
					return try SessionDataExporter.export(session: session, context: backgroundContext)
				}.value

				exportedFile = ShareableFile(url: url)
				pendingCleanupSessionID = sessionID
				pendingCleanupSessionName = sessionName
			} catch {
				exportError = error.localizedDescription
			}
			exportingSessionID = nil
		}
	}
}

private struct ShareableFile: Identifiable {
	let id = UUID()
	let url: URL
}

private enum SessionExportError: LocalizedError {
	case sessionNotFound

	var errorDescription: String? {
		switch self {
		case .sessionNotFound:
			return "The field logging session is no longer available."
		}
	}
}

private struct SessionShareSheet: UIViewControllerRepresentable {
	let url: URL

	func makeUIViewController(context: Context) -> UIActivityViewController {
		UIActivityViewController(activityItems: [url], applicationActivities: nil)
	}

	func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

private struct CleanupAfterExportView: View {
	@Environment(\.dismiss) private var dismiss
	@State private var cleanupAfterExport = false

	let sessionName: String
	let onKeep: () -> Void
	let onDelete: () -> Void

	var body: some View {
		NavigationStack {
			Form {
				Section {
					Toggle("Cleanup local session storage after export?", isOn: $cleanupAfterExport)
				} footer: {
					Text("Deleting the local session removes its GPS and radio observations.")
				}
			}
			.navigationTitle("Export Complete")
			.navigationBarTitleDisplayMode(.inline)
			.safeAreaInset(edge: .top) {
				Text(sessionName)
					.font(.subheadline)
					.foregroundStyle(.secondary)
					.padding(.top, 8)
			}
			.toolbar {
				ToolbarItem(placement: .cancellationAction) {
					Button("Keep") {
						onKeep()
						dismiss()
					}
				}
				ToolbarItem(placement: .confirmationAction) {
					Button("Done") {
						if cleanupAfterExport {
							onDelete()
						} else {
							onKeep()
						}
						dismiss()
					}
				}
			}
		}
		.presentationDetents([.medium])
	}
}
