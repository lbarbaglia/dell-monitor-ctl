// ddcvcp — minimal DDC/CI VCP get/set for external displays on Apple Silicon Macs.
// Uses the private IOAVService I2C API (same approach as m1ddc / MonitorControl).
//
// Build:  swiftc -O -o ddcvcp ddcvcp.swift -framework IOKit -framework Foundation
// Usage:  ddcvcp list
//         ddcvcp [-d N] get <vcp-hex>            -> prints "cur max" (decimal)
//         ddcvcp [-d N] set <vcp-hex> <value>    -> value decimal or 0x-hex, 16-bit
//         ddcvcp [-d N] scan [from] [to]         -> dump readable VCP codes

import Foundation
import IOKit

typealias IOAVService = CFTypeRef

@_silgen_name("IOAVServiceCreateWithService")
func IOAVServiceCreateWithService(_ allocator: CFAllocator?, _ service: io_service_t) -> Unmanaged<IOAVService>?

@_silgen_name("IOAVServiceReadI2C")
func IOAVServiceReadI2C(_ service: IOAVService, _ chipAddress: UInt32, _ offset: UInt32,
                        _ outputBuffer: UnsafeMutableRawPointer, _ outputBufferSize: UInt32) -> IOReturn

@_silgen_name("IOAVServiceWriteI2C")
func IOAVServiceWriteI2C(_ service: IOAVService, _ chipAddress: UInt32, _ dataAddress: UInt32,
                         _ inputBuffer: UnsafeRawPointer, _ inputBufferSize: UInt32) -> IOReturn

let DDC_ADDR: UInt32 = 0x37
let DDC_HOST: UInt8 = 0x51
let DDC_SRC: UInt8 = 0x6E

func die(_ msg: String, _ code: Int32 = 1) -> Never {
    FileHandle.standardError.write((msg + "\n").data(using: .utf8)!)
    exit(code)
}

func parseNum(_ s: String) -> UInt16? {
    let t = s.lowercased()
    if t.hasPrefix("0x") { return UInt16(t.dropFirst(2), radix: 16) }
    return UInt16(t) ?? UInt16(t, radix: 16)
}

struct ExtDisplay {
    let service: IOAVService
    let name: String
}

func externalServices() -> [ExtDisplay] {
    var out: [ExtDisplay] = []
    var iter: io_iterator_t = 0
    guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("DCPAVServiceProxy"), &iter) == KERN_SUCCESS else { return out }
    var svc = IOIteratorNext(iter)
    while svc != 0 {
        defer { IOObjectRelease(svc); svc = IOIteratorNext(iter) }
        guard let loc = IORegistryEntryCreateCFProperty(svc, "Location" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? String,
              loc == "External" else { continue }
        guard let av = IOAVServiceCreateWithService(kCFAllocatorDefault, svc)?.takeRetainedValue() else { continue }
        var pathBuf = [CChar](repeating: 0, count: 512)
        IORegistryEntryGetPath(svc, kIOServicePlane, &pathBuf)
        out.append(ExtDisplay(service: av, name: String(cString: pathBuf)))
    }
    IOObjectRelease(iter)
    return out
}

func ddcWrite(_ av: IOAVService, vcp: UInt8, value: UInt16) -> Bool {
    var data: [UInt8] = [0x84, 0x03, vcp, UInt8(value >> 8), UInt8(value & 0xFF), 0]
    data[5] = DDC_SRC ^ DDC_HOST ^ data[0] ^ data[1] ^ data[2] ^ data[3] ^ data[4]
    for _ in 0..<3 {
        if IOAVServiceWriteI2C(av, DDC_ADDR, UInt32(DDC_HOST), data, UInt32(data.count)) == KERN_SUCCESS {
            usleep(50_000)
            return true
        }
        usleep(20_000)
    }
    return false
}

// Returns (current, max) or nil.
func ddcRead(_ av: IOAVService, vcp: UInt8) -> (UInt16, UInt16)? {
    var req: [UInt8] = [0x82, 0x01, vcp, 0]
    req[3] = DDC_SRC ^ DDC_HOST ^ req[0] ^ req[1] ^ req[2]
    for _ in 0..<4 {
        guard IOAVServiceWriteI2C(av, DDC_ADDR, UInt32(DDC_HOST), req, UInt32(req.count)) == KERN_SUCCESS else { usleep(20_000); continue }
        usleep(50_000)
        var reply = [UInt8](repeating: 0, count: 11)
        guard IOAVServiceReadI2C(av, DDC_ADDR, UInt32(DDC_HOST), &reply, UInt32(reply.count)) == KERN_SUCCESS else { usleep(20_000); continue }
        // reply: [src][len][0x02][rc][vcp][type][maxH][maxL][curH][curL][chk]
        var chk: UInt8 = 0x50
        for i in 0..<10 { chk ^= reply[i] }
        if chk == reply[10] && reply[2] == 0x02 && reply[4] == vcp && reply[3] == 0x00 {
            return (UInt16(reply[8]) << 8 | UInt16(reply[9]), UInt16(reply[6]) << 8 | UInt16(reply[7]))
        }
        usleep(40_000)
    }
    return nil
}

var args = Array(CommandLine.arguments.dropFirst())
var displayIndex = 0
if args.count >= 2 && args[0] == "-d" {
    displayIndex = (Int(args[1]) ?? 1) - 1
    args.removeFirst(2)
}
guard let cmd = args.first else {
    die("usage: ddcvcp [-d N] list | get <vcp> | set <vcp> <value> | scan [from] [to]")
}

let displays = externalServices()
if cmd == "list" {
    for (i, d) in displays.enumerated() { print("\(i + 1): \(d.name)") }
    exit(0)
}
guard displayIndex >= 0 && displayIndex < displays.count else {
    die("no external DDC-capable display at index \(displayIndex + 1) (found \(displays.count))", 2)
}
let av = displays[displayIndex].service

switch cmd {
case "get":
    guard args.count >= 2, let vcp = parseNum(args[1]), vcp <= 0xFF else { die("usage: get <vcp-hex>") }
    guard let (cur, mx) = ddcRead(av, vcp: UInt8(vcp)) else { die("read failed for VCP 0x\(String(vcp, radix: 16))", 3) }
    print("\(cur) \(mx)")
case "set":
    guard args.count >= 3, let vcp = parseNum(args[1]), vcp <= 0xFF, let val = parseNum(args[2]) else { die("usage: set <vcp-hex> <value>") }
    guard ddcWrite(av, vcp: UInt8(vcp), value: val) else { die("write failed for VCP 0x\(String(vcp, radix: 16))", 3) }
case "scan":
    let from = args.count > 1 ? Int(parseNum(args[1]) ?? 0) : 0
    let to = args.count > 2 ? Int(parseNum(args[2]) ?? 0xFF) : 0xFF
    for code in from...to {
        if let (cur, mx) = ddcRead(av, vcp: UInt8(code)) {
            print(String(format: "0x%02X: cur=0x%04X (%d) max=0x%04X (%d)", code, cur, cur, mx, mx))
        }
    }
default:
    die("unknown command \(cmd)")
}
