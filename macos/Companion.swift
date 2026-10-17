import AppKit
import AVFoundation
import ApplicationServices
import Foundation

let outputLock = NSLock()
func emit(_ value: [String: Any]) {
    guard let bytes = try? JSONSerialization.data(withJSONObject: value) else { return }
    outputLock.lock(); defer { outputLock.unlock() }
    FileHandle.standardOutput.write(bytes + Data([10]))
}

func focusedField() -> AXUIElement? {
    var result: CFTypeRef?
    guard AXUIElementCopyAttributeValue(AXUIElementCreateSystemWide(), kAXFocusedUIElementAttribute as CFString, &result) == .success,
          let result = result, CFGetTypeID(result) == AXUIElementGetTypeID() else { return nil }
    let element = result as! AXUIElement
    var role: CFTypeRef?
    AXUIElementCopyAttributeValue(element, kAXSubroleAttribute as CFString, &role)
    if (role as? String) == "AXSecureTextField" { return nil }
    AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &role)
    guard let name = role as? String, ["AXTextField", "AXTextArea", "AXComboBox"].contains(name) else { return nil }
    return element
}

// Keep each keyboard payload small and never split a UTF-16 surrogate pair.
func keyboardChunks(_ text: String) -> [[UniChar]] {
    var chunks: [[UniChar]] = [], current: [UniChar] = []
    for scalar in text.unicodeScalars {
        let units = Array(String(scalar).utf16)
        if current.count + units.count > 20 { chunks.append(current); current=[] }
        current.append(contentsOf:units)
    }
    if !current.isEmpty { chunks.append(current) }
    return chunks
}

func insert(_ text: String, into expected: AXUIElement) -> Bool {
    guard let current = focusedField(), CFEqual(current, expected) else { return false }
    let clean = text.split(whereSeparator: { $0.isNewline }).joined(separator: " ").trimmingCharacters(in: .whitespaces)
    guard !clean.isEmpty, clean.count < 3000, !clean.hasPrefix("[BLANK_AUDIO]") else { return false }
    for units in keyboardChunks(clean + " ") {
        guard let current = focusedField(), CFEqual(current, expected),
              let down = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: true),
              let up = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: false) else { return false }
        units.withUnsafeBufferPointer { ptr in
            down.keyboardSetUnicodeString(stringLength: units.count, unicodeString: ptr.baseAddress)
            up.keyboardSetUnicodeString(stringLength: units.count, unicodeString: ptr.baseAddress)
        }
        down.post(tap: .cghidEventTap); up.post(tap: .cghidEventTap)
    }
    return true
}

struct Segmenter {
    var samples: [Float] = [], lead: [Float] = []
    var speaking = false
    var quietSamples = 0, voicedSamples = 0
    let threshold: Float = 0.014
    mutating func accept(_ input: [Float]) -> (began: Bool, completed: [Float]?) {
        guard !input.isEmpty else { return (false, nil) }
        let rms = sqrt(input.reduce(Float(0)) { $0 + $1 * $1 } / Float(input.count))
        var began = false
        if !speaking {
            if rms >= threshold {
                speaking = true; began = true; samples = lead; quietSamples = 0
            } else {
                lead.append(contentsOf: input)
                if lead.count > 3200 { lead.removeFirst(lead.count - 3200) }
                return (false, nil)
            }
        }
        samples.append(contentsOf: input)
        if rms >= threshold { voicedSamples += input.count }
        quietSamples = rms < threshold ? quietSamples + input.count : 0
        if quietSamples >= 14400 || samples.count >= 320000 {
            let result = samples
            let voiced = voicedSamples
            self = Segmenter()
            return (began, voiced >= 4000 ? result : [])
        }
        return (began, nil)
    }
}

final class Recorder {
    let whisper: String, model: String
    let engine = AVAudioEngine()
    let work = DispatchQueue(label: "local.pelotondesk.transcribe")
    let lock = NSLock()
    var segmenter = Segmenter()
    var focus: AXUIElement?
    var pending = 0, stopped = false
    var child: Process?
    var signalSource: DispatchSourceSignal?
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("peloton-desk-" + UUID().uuidString)
    init(whisper: String, model: String) { self.whisper = whisper; self.model = model }

    func begin() {
        guard AXIsProcessTrusted() else {
            emit(["type":"error", "message":"Sur le Mac, autorisez Peloton Desk Mac dans Confidentialité et sécurité → Accessibilité pour insérer la dictée."])
            exit(1)
        }
        AVCaptureDevice.requestAccess(for: .audio) { granted in
            DispatchQueue.main.async {
                if granted { self.startEngine() }
                else { emit(["type":"error", "message":"Autorisez le micro pour Peloton Desk Mac dans les réglages du Mac."]); exit(1) }
            }
        }
    }

    func startEngine() {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            let input = engine.inputNode
            let inputFormat = input.outputFormat(forBus: 0)
            guard inputFormat.sampleRate > 0, inputFormat.channelCount > 0,
                  let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16000, channels: 1, interleaved: false),
                  let converter = AVAudioConverter(from: inputFormat, to: format) else { throw NSError(domain:"Microphone indisponible", code:1) }
            input.installTap(onBus: 0, bufferSize: 2048, format: inputFormat) { buffer, _ in
                let capacity = AVAudioFrameCount(ceil(Double(buffer.frameLength) * 16000 / inputFormat.sampleRate)) + 32
                guard let converted = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else { return }
                var supplied = false
                var error: NSError?
                converter.convert(to: converted, error: &error) { _, state in
                    if supplied { state.pointee = .noDataNow; return nil }
                    supplied = true; state.pointee = .haveData; return buffer
                }
                guard error == nil, let channel = converted.floatChannelData?[0] else { return }
                self.consume(Array(UnsafeBufferPointer(start: channel, count: Int(converted.frameLength))))
            }
            try engine.start()
            signal(SIGTERM, SIG_IGN)
            signalSource = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
            signalSource?.setEventHandler { self.stop() }
            signalSource?.resume()
            emit(["type":"voice-state", "active":true])
        } catch {
            emit(["type":"error", "message":"Le micro du Mac n’a pas pu démarrer."])
            stop()
        }
    }

    func consume(_ input: [Float]) {
        lock.lock()
        if stopped { lock.unlock(); return }
        let result = segmenter.accept(input)
        if result.began { focus = focusedField() }
        guard let samples = result.completed else { lock.unlock(); return }
        guard !samples.isEmpty, let target = focus else { focus=nil; lock.unlock(); return }
        if pending >= 2 {
            focus=nil;lock.unlock()
            emit(["type":"error","message":"La transcription prend du retard. Attendez la fin de la phrase précédente avant de reprendre."])
            return
        }
        focus=nil; pending += 1; lock.unlock()
        work.async { self.transcribe(samples, target: target) }
    }

    func transcribe(_ samples: [Float], target: AXUIElement) {
        let stem = directory.appendingPathComponent(UUID().uuidString)
        let wav = stem.appendingPathExtension("wav"), txt = stem.appendingPathExtension("txt")
        defer {
            try? FileManager.default.removeItem(at: wav); try? FileManager.default.removeItem(at: txt)
            lock.lock(); pending -= 1; child=nil; lock.unlock()
        }
        lock.lock(); let cancelled=stopped; lock.unlock()
        if cancelled { return }
        do {
            guard let format = AVAudioFormat(commonFormat:.pcmFormatFloat32,sampleRate:16000,channels:1,interleaved:false),
                  let buffer = AVAudioPCMBuffer(pcmFormat:format,frameCapacity:AVAudioFrameCount(samples.count)) else { return }
            buffer.frameLength=AVAudioFrameCount(samples.count)
            samples.withUnsafeBufferPointer { src in buffer.floatChannelData![0].update(from:src.baseAddress!,count:samples.count) }
            let settings:[String:Any] = [AVFormatIDKey:kAudioFormatLinearPCM,AVSampleRateKey:16000,AVNumberOfChannelsKey:1,AVLinearPCMBitDepthKey:16,AVLinearPCMIsFloatKey:false,AVLinearPCMIsBigEndianKey:false]
            var file: AVAudioFile? = try AVAudioFile(forWriting:wav,settings:settings,commonFormat:.pcmFormatFloat32,interleaved:false)
            try file?.write(from:buffer)
            file = nil // Finalize the WAV header before whisper reads it.
            emit(["type":"notice","message":"Transcription locale…"])
            let process=Process(); process.executableURL=URL(fileURLWithPath:whisper)
            process.arguments=["-m",model,"-f",wav.path,"-l","auto","-nt","-np","-otxt","-of",stem.path]
            process.standardOutput=FileHandle.nullDevice; process.standardError=FileHandle.nullDevice
            lock.lock(); if stopped { lock.unlock(); return }; child=process; lock.unlock()
            try process.run(); process.waitUntilExit()
            guard process.terminationStatus == 0 else { throw NSError(domain:"Transcription échouée",code:2) }
            let text=try String(contentsOf:txt,encoding:.utf8)
            lock.lock(); let mayInsert = !stopped; lock.unlock()
            if mayInsert {
                let inserted=insert(text,into:target)
                emit(["type":"transcription","inserted":inserted,"text":inserted ? "" : text,"message":inserted ? "Texte inséré." : "Le champ a changé ou la phrase est vide : aucun texte inséré."])
            }
        } catch { emit(["type":"error","message":"La transcription locale a échoué. La dictée reste à l’écoute."]) }
    }

    func stop() {
        lock.lock(); stopped=true; let process=child; lock.unlock()
        engine.stop()
        if process?.isRunning == true { process?.terminate() }
        try? FileManager.default.removeItem(at:directory)
        emit(["type":"voice-state","active":false])
        exit(0)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    var item: NSStatusItem!, server: Process?
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        item=NSStatusBar.system.statusItem(withLength:NSStatusItem.variableLength)
        item.button?.title="PD"
        let menu=NSMenu()
        let title=NSMenuItem(title:"Peloton Desk · compagnon Mac",action:nil,keyEquivalent:"");title.isEnabled=false;menu.addItem(title)
        menu.addItem(NSMenuItem(title:"Autorisations de dictée…",action:#selector(permissions),keyEquivalent:""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title:"Quitter Peloton Desk",action:#selector(quit),keyEquivalent:"q"))
        for option in menu.items { option.target=self };item.menu=menu
        startServer()
    }
    func startServer() {
        guard let root=Bundle.main.object(forInfoDictionaryKey:"PDProjectRoot") as? String else { return }
        do {
            let base=URL(fileURLWithPath:root)
            let connection=try JSONSerialization.jsonObject(with:Data(contentsOf:base.appendingPathComponent(".local/connection.json"))) as? [String:String]
            guard let serial=connection?["serial"] else { throw NSError(domain:"Bike non configuré",code:1) }
            let process=Process();process.executableURL=base.appendingPathComponent(".venv/bin/python")
            process.arguments=[base.appendingPathComponent("macos/companion.py").path,"--serial",serial]
            var environment=ProcessInfo.processInfo.environment
            environment["PATH"]="/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin"
            environment["PELOTON_DESK_HELPER"]=Bundle.main.executableURL?.path
            process.environment=environment
            let log=base.appendingPathComponent(".local/companion.log")
            FileManager.default.createFile(atPath:log.path,contents:nil,attributes:[.posixPermissions:0o600])
            let handle=try FileHandle(forWritingTo:log)
            process.standardOutput=handle;process.standardError=handle
            try process.run();server=process
        } catch { let alert=NSAlert();alert.messageText="Le compagnon n’a pas pu démarrer.";alert.informativeText="Vérifiez que le Bike est connecté et que l’installation est terminée.";alert.runModal() }
    }
    @objc func permissions() {
        let options=[kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String:true] as CFDictionary
        _=AXIsProcessTrustedWithOptions(options)
        AVCaptureDevice.requestAccess(for:.audio) { _ in }
    }
    @objc func quit() { server?.terminate(); NSApp.terminate(nil) }
    func applicationWillTerminate(_ notification:Notification) { server?.terminate() }
}

let args=CommandLine.arguments
if args.contains("--self-test") {
    let example=String(repeating:"é",count:19)+"🚲"+String(repeating:"a",count:45)
    let chunks=keyboardChunks(example)
    precondition(chunks.allSatisfy { $0.count <= 20 })
    precondition(chunks.map { String(decoding:$0,as:UTF16.self) }.joined()==example)
    var segmenter=Segmenter()
    precondition(!segmenter.accept(Array(repeating:Float(0),count:16000)).began)
    precondition(segmenter.accept(Array(repeating:Float(0.05),count:8000)).began)
    let complete=segmenter.accept(Array(repeating:Float(0),count:16000)).completed
    precondition(complete != nil && complete!.count >= 24000)
    precondition(!segmenter.speaking)
    _=segmenter.accept(Array(repeating:Float(0.1),count:500))
    precondition(segmenter.accept(Array(repeating:Float(0),count:16000)).completed?.isEmpty == true)
    print("Voice segmentation checks passed; no microphone or input events used.")
} else if args.count==4 && args[1]=="--voice" {
    let recorder=Recorder(whisper:args[2],model:args[3]);recorder.begin();RunLoop.main.run()
} else {
    let delegate=AppDelegate();let app=NSApplication.shared;app.delegate=delegate;app.run()
}
