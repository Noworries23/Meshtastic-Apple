import Foundation
import Testing

@testable import Meshtastic

// MARK: - FountainCodec receive path

@Suite("FountainCodec handleIncomingPacket")
struct FountainCodecTests {

	/// A data block as it arrives off the mesh: magic, 24-bit transfer id, seed, K, total length, 220-byte payload.
	private func dataBlock(transferId: UInt32, seed: UInt16 = 0, blockCount: UInt8, totalLength: UInt16) -> Data {
		var packet = Data(FountainConstants.magic)
		packet.append(contentsOf: [UInt8(transferId >> 16 & 0xFF), UInt8(transferId >> 8 & 0xFF), UInt8(transferId & 0xFF)])
		packet.append(contentsOf: [UInt8(seed >> 8), UInt8(seed & 0xFF)])
		packet.append(blockCount)
		packet.append(contentsOf: [UInt8(totalLength >> 8), UInt8(totalLength & 0xFF)])
		packet.append(Data(repeating: 0x41, count: FountainConstants.blockSize))
		return packet
	}

	@Test func zeroBlockCount_isRejected() {
		let packet = dataBlock(transferId: 0xA10001, blockCount: 0, totalLength: 10)
		#expect(FountainCodec.shared.handleIncomingPacket(packet, senderNodeId: 1) == nil)
	}

	@Test func singleBlockCount_decodes() throws {
		let packet = dataBlock(transferId: 0xA10002, blockCount: 1, totalLength: 10)
		let result = try #require(FountainCodec.shared.handleIncomingPacket(packet, senderNodeId: 1))
		#expect(result.data == Data(repeating: 0x41, count: 10))
	}

	@Test func encodedTransfer_roundTrips() throws {
		let original = Data((0..<600).map { UInt8($0 % 251) })
		let transferId: UInt32 = 0xA10003
		var decoded: Data?
		for packet in FountainCodec.shared.encode(data: original, transferId: transferId) {
			if let result = FountainCodec.shared.handleIncomingPacket(packet, senderNodeId: 1) {
				decoded = result.data
				break
			}
		}
		#expect(decoded == original)
	}
}
