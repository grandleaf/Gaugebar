//
//  DB.swift
//  Kit
//
//  Created by Serhiy Mytrovtsiy on 03/02/2024
//  Using Swift 5.0
//  Running on macOS 14.3
//
//  Copyright © 2024 Serhiy Mytrovtsiy. All rights reserved.
//

import Foundation

public class DB {
    public static let shared = DB()
    
    private var lldb: LLDB? = nil
    private let queue = DispatchQueue(label: "io.github.grandleaf.db")
    private let ttl: Int = 60*60
    
    public var _writeTS: [String: Date] = [:]
    public var writeTS: [String: Date] {
        get { self.queue.sync { self._writeTS } }
        set { self.queue.sync { self._writeTS = newValue } }
    }
    
    private var _values: [String: Codable] = [:]
    public var values: [String: Codable] {
        get { self.queue.sync { self._values } }
        set { self.queue.sync { self._values = newValue } }
    }
    
    init() {
        let fileManager = FileManager.default
        let supportPath = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!.appendingPathComponent("Gaugebar")
        let tmpPath = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("Gaugebar")
        
        for path in [supportPath, tmpPath] {
            try? fileManager.createDirectory(at: path, withIntermediateDirectories: true, attributes: nil)
            if let lldb = LLDB(path.appendingPathComponent("lldb").path) {
                self.lldb = lldb
                return
            }
        }
        
        print("ERROR INITIALIZE DB")
    }
    
    deinit {
        self.lldb?.close()
    }
    
    public func setup<T: Codable>(_ type: T.Type, _ key: String) {
        self.clean(key)
        if let raw = self.lldb?.findOne(key), let value = try? JSONDecoder().decode(type, from: Data(raw.utf8)) {
            self.queue.sync { self._values[key] = value }
        }
    }
    
    public func insert(key: String, value: Codable, force: Bool = false) {
        self.queue.sync { self._values[key] = value }
        guard let blobData = try? JSONEncoder().encode(value), let str = String(data: blobData, encoding: .utf8) else { return }
        
        let now = Date()
        let shouldWrite: Bool = self.queue.sync {
            if !force, let ts = self._writeTS[key], (now.timeIntervalSince1970-ts.timeIntervalSince1970) < 30 {
                return false
            }
            self._writeTS[key] = now
            return true
        }
        guard shouldWrite else { return }
        
        self.lldb?.insert(key, value: str)
    }
    
    public func findOne<T: Decodable>(_ dynamicType: T.Type, key: String) -> T? {
        return self.values[key] as? T
    }
    
    private func clean(_ key: String) {
        guard let keys = self.lldb?.keys(key) as? [String] else { return }
        let maxLiveTS = Date().currentTimeSeconds() - self.ttl
        var toDeleteKeys: [String] = []
        
        keys.forEach { (key: String) in
            if let ts = key.split(separator: "@").last, let ts = Int(ts), ts < maxLiveTS {
                toDeleteKeys.append(key)
            }
        }
        
        self.lldb?.deleteMany(toDeleteKeys)
    }
}
