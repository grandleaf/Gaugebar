import Foundation
import IOKit

// OS-boundary replacements used only by run-smc-tests.py's disposable source copy.
// No test links an SMC operation to the real driver, including open and close.
final class FakeSMC {
    struct Entry {
        var type: String
        var bytes: [UInt8]
    }
    static var current = FakeSMC()
    let lock = NSLock()
    var entries: [String: Entry] = [:]
    var firmwareErrors: [String: UInt8] = [:]
    var transportErrors: Set<String> = []
    var transientFailures: [String: Int] = [:]
    var calls: [String] = []
    var keys: [String] = []
    var openResult = kIOReturnSuccess
    var matchingResult = kIOReturnSuccess
    var device: io_object_t = 2
    var releases: [io_object_t] = []
    var opened = 0
    var closed = 0

    func put(_ key: String, _ type: String, _ bytes: [UInt8]) {
        entries[key] = Entry(type: type, bytes: bytes)
    }
    func put(_ key: String, _ bytes: [UInt8]) { put(key, "ui8 ", bytes) }
    func count(_ command: String) -> Int { calls.filter { $0 == command }.count }
}

func mockIOServiceMatching(_ name: String) -> CFMutableDictionary {
    CFDictionaryCreateMutable(nil, 0, nil, nil)
}
func mockIOServiceGetMatchingServices(
    _ port: mach_port_t, _ dictionary: CFMutableDictionary,
    _ iterator: UnsafeMutablePointer<io_iterator_t>
) -> kern_return_t {
    iterator.pointee = 1
    return FakeSMC.current.matchingResult
}
func mockIOIteratorNext(_ iterator: io_iterator_t) -> io_object_t { FakeSMC.current.device }
@discardableResult
func mockIOObjectRelease(_ object: io_object_t) -> kern_return_t {
    FakeSMC.current.releases.append(object)
    return kIOReturnSuccess
}
func mockIOServiceOpen(_ service: io_service_t, _ task: task_port_t, _ type: UInt32,
                       _ connection: UnsafeMutablePointer<io_connect_t>) -> kern_return_t {
    FakeSMC.current.opened += 1
    connection.pointee = 3
    return FakeSMC.current.openResult
}
func mockIOServiceClose(_ connection: io_connect_t) -> kern_return_t {
    FakeSMC.current.closed += 1
    return kIOReturnSuccess
}
// Match the IOKit function signature so the test runner can replace calls directly.
// swiftlint:disable:next function_parameter_count
func mockIOConnectCallStructMethod(
    _ connection: io_connect_t, _ selector: UInt32,
    _ input: UnsafePointer<SMCKeyData_t>, _ inputSize: Int,
    _ output: UnsafeMutablePointer<SMCKeyData_t>,
    _ outputSize: UnsafeMutablePointer<Int>
) -> kern_return_t {
    let fake = FakeSMC.current
    fake.lock.lock()
    defer { fake.lock.unlock() }
    precondition(selector == 2 && inputSize == MemoryLayout<SMCKeyData_t>.stride)
    let request = input.pointee
    output.pointee = SMCKeyData_t()
    let key = request.key.toString()
    let command = request.data8
    let name = command == 8 ? "index:\(request.data32)" : "\(command):\(key)"
    fake.calls.append(name)
    if fake.transportErrors.contains(name) { return kIOReturnError }
    if let remaining = fake.transientFailures[name], remaining > 0 {
        fake.transientFailures[name] = remaining - 1
        output.pointee.result = 1
        return kIOReturnSuccess
    }
    if let failure = fake.firmwareErrors[name] {
        output.pointee.result = failure
        return kIOReturnSuccess
    }
    switch command {
    case 8:
        guard Int(request.data32) < fake.keys.count else {
            output.pointee.result = 0x84
            return kIOReturnSuccess
        }
        output.pointee.key = FourCharCode(fromString: fake.keys[Int(request.data32)])
    case 5, 9:
        guard let entry = fake.entries[key] else {
            output.pointee.result = 0x84
            return kIOReturnSuccess
        }
        if command == 9 {
            output.pointee.keyInfo.dataSize = UInt32(entry.bytes.count)
            output.pointee.keyInfo.dataType = FourCharCode(fromString: entry.type)
        } else {
            withUnsafeMutableBytes(of: &output.pointee.bytes) { $0.copyBytes(from: entry.bytes.prefix(32)) }
        }
    default:
        preconditionFailure("Unexpected SMC command \(command)")
    }
    return kIOReturnSuccess
}

import XCTest

final class SMCTests: XCTestCase {
    var fake: FakeSMC { FakeSMC.current }
    var smc: SMC!

    override func setUp() {
        super.setUp()
        FakeSMC.current = FakeSMC()
        smc = SMC()
    }
    override func tearDown() {
        smc = nil
        super.tearDown()
    }

    func testConnectionOpensAndReleasesObjects() {
        XCTAssertEqual(fake.opened, 1)
        XCTAssertEqual(fake.releases, [1, 2])
        smc = nil
        XCTAssertEqual(fake.closed, 1)
    }
    func testMatchingFailureDoesNotOpen() {
        smc = nil
        FakeSMC.current = FakeSMC()
        fake.matchingResult = kIOReturnError
        smc = SMC()
        XCTAssertEqual(fake.opened, 0)
        XCTAssertTrue(fake.releases.isEmpty)
    }
    func testMissingDeviceReleasesIterator() {
        smc = nil
        FakeSMC.current = FakeSMC()
        fake.device = 0
        smc = SMC()
        XCTAssertEqual(fake.opened, 0)
        XCTAssertEqual(fake.releases, [1])
    }
    func testFailedOpenReleasesDevice() {
        smc = nil
        FakeSMC.current = FakeSMC()
        fake.openResult = kIOReturnError
        smc = SMC()
        XCTAssertEqual(fake.releases, [1, 2])
    }
    func testUnsignedDecoders() {
        for (type, bytes, expected): (String, [UInt8], Double) in [
            ("ui8 ", [255], 255), ("ui16", [0x12, 0x34], 4660),
            ("ui32", [0x12, 0x34, 0x56, 0x78], 305419896),
            ("ui32", [255, 255, 255, 255], 4294967295)
        ] {
            let reader = SMC()
            fake.put("TEST", type, bytes)
            XCTAssertEqual(reader.getValue("TEST"), expected)
        }
    }
    func testPositiveFixedPointDecoders() {
        for (type, divisor): (String, Double) in [
            ("sp1e", 16384), ("sp3c", 4096), ("sp4b", 2048),
            ("sp5a", 1024), ("sp69", 512), ("sp78", 256),
            ("sp87", 128), ("sp96", 64), ("spa5", 32), ("spb4", 16), ("spf0", 1)
        ] {
            let reader = SMC()
            fake.put("TEST", type, [0x12, 0x34])
            XCTAssertEqual(reader.getValue("TEST"), 4660 / divisor, type)
        }
    }
    func testFloatDecoder() {
        for value: Float in [-12.5, 1.25, 6000] {
            fake.put("TEST", "flt ", withUnsafeBytes(of: value, Array.init))
            XCTAssertEqual(smc.getValue("TEST"), Double(value))
        }
    }
    func testAllZeroValuesReturnNil() {
        fake.put("TEST", "ui16", [0, 0])
        XCTAssertNil(smc.getValue("TEST"))
    }
    func testUnknownNumericTypeReturnsNil() {
        fake.put("TEST", "xxxx", [1, 2, 3, 4])
        XCTAssertNil(smc.getValue("TEST"))
    }
    func testFanDescription() {
        fake.put("F0ID", "{fds", [0, 0, 0, 0] + Array("  Left Fan  ".utf8))
        XCTAssertEqual(smc.getStringValue("F0ID"), "Left Fan")
    }
    func testUnsupportedStringTypeReturnsNil() {
        fake.put("F0ID", "ui8 ", [1])
        XCTAssertNil(smc.getStringValue("F0ID"))
    }
    func testMetadataFirmwareErrorStopsRead() {
        fake.put("F0Md", [0])
        fake.firmwareErrors["9:F0Md"] = 1
        XCTAssertNil(smc.getValue("F0Md"))
        XCTAssertEqual(fake.calls, ["9:F0Md"])
    }
    func testMetadataTransportErrorStopsRead() {
        fake.transportErrors.insert("9:F0Md")
        XCTAssertNil(smc.getValue("F0Md"))
        XCTAssertEqual(fake.calls, ["9:F0Md"])
    }
    func testValueFirmwareErrorReturnsNil() {
        fake.put("F0Md", [0])
        fake.firmwareErrors["5:F0Md"] = 1
        XCTAssertNil(smc.getValue("F0Md"))
    }
    func testValueTransportErrorReturnsNil() {
        fake.put("TEST", [42])
        fake.transportErrors.insert("5:TEST")
        XCTAssertNil(smc.getValue("TEST"))
    }
    func testStringReadFailureReturnsNil() {
        fake.put("F0ID", "{fds", [0, 0, 0, 0] + Array("  Left Fan  ".utf8))
        fake.firmwareErrors["5:F0ID"] = 1
        XCTAssertNil(smc.getStringValue("F0ID"))
    }
    func testMetadataIsCachedButValuesAreFresh() {
        fake.put("TEST", [1])
        XCTAssertEqual(smc.getValue("TEST"), 1)
        fake.put("TEST", [2])
        XCTAssertEqual(smc.getValue("TEST"), 2)
        XCTAssertEqual(fake.count("9:TEST"), 1)
        XCTAssertEqual(fake.count("5:TEST"), 2)
    }
    func testFirmwareFailureEvictsMetadata() {
        fake.put("TEST", [1])
        XCTAssertEqual(smc.getValue("TEST"), 1)
        fake.firmwareErrors["5:TEST"] = 1
        XCTAssertNil(smc.getValue("TEST"))
        fake.firmwareErrors = [:]
        fake.put("TEST", "ui16", [1, 0])
        XCTAssertEqual(smc.getValue("TEST"), 256)
        XCTAssertEqual(fake.count("9:TEST"), 2)
    }
    func testTransportFailureEvictsMetadata() {
        fake.put("TEST", [1])
        XCTAssertEqual(smc.getValue("TEST"), 1)
        fake.transportErrors.insert("5:TEST")
        XCTAssertNil(smc.getValue("TEST"))
        fake.transportErrors = []
        XCTAssertEqual(smc.getValue("TEST"), 1)
        XCTAssertEqual(fake.count("9:TEST"), 2)
    }
    func testMissingKeysAreNotCached() {
        XCTAssertNil(smc.getValue("TEST"))
        fake.put("TEST", [42])
        XCTAssertEqual(smc.getValue("TEST"), 42)
        XCTAssertEqual(fake.count("9:TEST"), 2)
    }
    func testMissingStringKeyCanBecomeAvailable() {
        XCTAssertNil(smc.getStringValue("F0ID"))
        fake.put("F0ID", "{fds", [0, 0, 0, 0] + Array("  Left Fan  ".utf8))
        XCTAssertEqual(smc.getStringValue("F0ID"), "Left Fan")
        XCTAssertEqual(fake.count("9:F0ID"), 2)
    }
    func testKeyDisappearingDuringReadEvictsMetadata() {
        fake.put("TEST", [1])
        XCTAssertEqual(smc.getValue("TEST"), 1)
        fake.entries.removeValue(forKey: "TEST")
        XCTAssertNil(smc.getValue("TEST"))
        fake.put("TEST", "ui16", [1, 0])
        XCTAssertEqual(smc.getValue("TEST"), 256)
        XCTAssertEqual(fake.count("9:TEST"), 2)
    }
    func testCachesAreIndependentAcrossInstances() {
        fake.put("TEST", [1])
        XCTAssertEqual(smc.getValue("TEST"), 1)
        XCTAssertEqual(SMC().getValue("TEST"), 1)
        XCTAssertEqual(fake.count("9:TEST"), 2)
    }
    func testConcurrentReadsShareMetadataCache() {
        fake.put("TEST", [42])
        DispatchQueue.concurrentPerform(iterations: 100) { _ in
            XCTAssertEqual(self.smc.getValue("TEST"), 42)
        }
        XCTAssertEqual(fake.count("9:TEST"), 1)
        XCTAssertEqual(fake.count("5:TEST"), 100)
    }
    func testInvalidKeysNeverReachDriver() {
        for key in ["", "abc", "abcde", "éabc", "😀abc", "e\u{301}abc"] {
            XCTAssertNil(smc.getValue(key))
            XCTAssertNil(smc.getStringValue(key))
        }
        XCTAssertTrue(fake.calls.isEmpty)
    }
    func testEnumerationUsesExactlyTheKeyCount() {
        fake.keys = ["AAAA", "BBBB", "CCCC"]
        fake.put("#KEY", "ui32", [0, 0, 0, 3])
        XCTAssertEqual(smc.getAllKeys(), fake.keys)
        XCTAssertEqual(fake.calls.filter { $0.hasPrefix("index:") }, ["index:0", "index:1", "index:2"])
    }
    func testEnumerationSkipsFirmwareAndTransportErrors() {
        fake.keys = ["AAAA", "BBBB", "CCCC", "DDDD"]
        fake.put("#KEY", "ui32", [0, 0, 0, 4])
        fake.firmwareErrors["index:1"] = 1
        fake.transportErrors.insert("index:2")
        XCTAssertEqual(smc.getAllKeys(), ["AAAA", "DDDD"])
    }
    func testEnumerationWithoutCountDoesNotReadIndices() {
        XCTAssertTrue(smc.getAllKeys().isEmpty)
        XCTAssertFalse(fake.calls.contains { $0.hasPrefix("index:") })
    }
    func testEnumerationWithZeroCountDoesNotReadIndices() {
        fake.put("#KEY", "ui32", [0, 0, 0, 0])
        XCTAssertTrue(smc.getAllKeys().isEmpty)
        XCTAssertFalse(fake.calls.contains { $0.hasPrefix("index:") })
    }

    #if TEST_ARM64
    #else
    #endif
}
