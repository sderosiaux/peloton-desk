import AppKit
import AVFoundation
import ApplicationServices
import Carbon.HIToolbox
import Foundation
import ServiceManagement
import WebKit

let outputLock = NSLock()
func emit(_ value: [String: Any]) {
    guard let bytes = try? JSONSerialization.data(withJSONObject: value) else { return }
    outputLock.lock(); defer { outputLock.unlock() }
    FileHandle.standardOutput.write(bytes + Data([10]))
}

func axValue(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
    return value
}
func axElement(_ value: CFTypeRef?) -> AXUIElement? {
    guard let value=value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
    return (value as! AXUIElement)
}
func focusedField() -> AXUIElement? {
    guard let app=NSWorkspace.shared.frontmostApplication else { return nil }
    let application=AXUIElementCreateApplication(app.processIdentifier)
    guard var element=axElement(axValue(AXUIElementCreateSystemWide(), kAXFocusedUIElementAttribute))
        ?? axElement(axValue(application,kAXFocusedUIElementAttribute)) else { return nil }
    for _ in 0..<4 {
        guard let child=axElement(axValue(element,kAXFocusedUIElementAttribute)), !CFEqual(child,element) else { break }
        element=child
    }
    if axValue(element,kAXSubroleAttribute) as? String == "AXSecureTextField" { return nil }
    let role=axValue(element,kAXRoleAttribute) as? String ?? ""
    var writable: DarwinBoolean=false
    AXUIElementIsAttributeSettable(element,kAXSelectedTextAttribute as CFString,&writable)
    guard ["AXTextField","AXTextArea","AXComboBox"].contains(role) || writable.boolValue else { return nil }
    var pid: pid_t=0
    AXUIElementGetPid(element,&pid)
    return pid == app.processIdentifier ? element : nil
}

func cleanTranscript(_ text: String) -> String {
    let clean=text.split(whereSeparator: { $0.isNewline || $0 == "\t" }).joined(separator:" ").trimmingCharacters(in:.whitespaces)
    guard !clean.isEmpty, clean.count < 3000, !clean.hasPrefix("[BLANK_AUDIO]") else { return "" }
    return clean
}

// Resolve the Command shortcut in the user's layout, including AZERTY.
// Approach informed by OpenWhispr's MIT-licensed macos-fast-paste helper.
func pasteKey() -> CGKeyCode? {
    guard let source=TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
          let property=TISGetInputSourceProperty(source,kTISPropertyUnicodeKeyLayoutData) else { return nil }
    let data=Unmanaged<CFData>.fromOpaque(property).takeUnretainedValue() as Data
    return data.withUnsafeBytes { bytes in
        guard let address=bytes.baseAddress else { return nil }
        let layout=address.assumingMemoryBound(to:UCKeyboardLayout.self)
        for code in UInt16(0)..<128 {
            var dead: UInt32=0, count=0
            var chars=[UniChar](repeating:0,count:8)
            let result=UCKeyTranslate(layout,code,UInt16(kUCKeyActionDisplay),UInt32(cmdKey)>>8,
                UInt32(LMGetKbdType()),OptionBits(kUCKeyTranslateNoDeadKeysBit),&dead,chars.count,&count,&chars)
            if result == noErr && String(utf16CodeUnits:chars,count:count) == "v" { return CGKeyCode(code) }
        }
        return nil
    }
}

// One paste operation avoids partial Unicode typing. No Return key is sent.
// A successful result means the paste command was posted, not that the app acknowledged it.
func insert(_ text: String, into expected: AXUIElement) -> Bool {
    func sameField() -> Bool { guard let current=focusedField() else { return false }; return CFEqual(current,expected) }
    let clean=cleanTranscript(text)
    guard !clean.isEmpty, AXIsProcessTrusted(), sameField(), let key=pasteKey(),
          let down=CGEvent(keyboardEventSource:nil,virtualKey:key,keyDown:true),
          let up=CGEvent(keyboardEventSource:nil,virtualKey:key,keyDown:false) else { return false }
    let board=NSPasteboard.general
    let saved=(board.pasteboardItems ?? []).map { item in
        item.types.compactMap { type -> (NSPasteboard.PasteboardType,Data)? in
            guard let data=item.data(forType:type) else { return nil }; return (type,data)
        }
    }
    board.clearContents()
    let wrote=board.setString(clean + " ",forType:.string)
    let generation=board.changeCount
    defer {
        // Keep a newer copy made by the user; never overwrite it with our snapshot.
        if board.changeCount == generation {
            let items=saved.map { values -> NSPasteboardItem in
                let item=NSPasteboardItem(); for (type,data) in values { item.setData(data,forType:type) }; return item
            }
            board.clearContents(); if !items.isEmpty { board.writeObjects(items) }
        }
    }
    guard wrote else { return false }
    Thread.sleep(forTimeInterval:0.05)
    guard sameField() else { return false }
    down.flags = .maskCommand; up.flags = .maskCommand
    down.post(tap:.cgSessionEventTap)
    Thread.sleep(forTimeInterval:0.01)
    up.post(tap:.cgSessionEventTap)
    Thread.sleep(forTimeInterval:0.7)
    return true
}

struct Segmenter {
    var samples: [Float]=[], lead: [Float]=[]
    var speaking=false
    var quietSamples=0, voicedSamples=0
    let threshold: Float=0.008
    mutating func finish() -> [Float] {
        let result=voicedSamples >= 4000 ? samples : []
        self=Segmenter()
        return result
    }
    mutating func accept(_ input: [Float]) -> (began: Bool, completed: [Float]?) {
        guard !input.isEmpty else { return (false,nil) }
        let rms=sqrt(input.reduce(Float(0)) { $0+$1*$1 } / Float(input.count))
        var began=false
        if !speaking {
            if rms >= threshold { speaking=true; began=true; samples=lead; quietSamples=0 }
            else {
                lead.append(contentsOf:input)
                if lead.count > 3200 { lead.removeFirst(lead.count-3200) }
                return (false,nil)
            }
        }
        samples.append(contentsOf:input)
        if rms >= threshold { voicedSamples += input.count }
        quietSamples = rms < threshold ? quietSamples+input.count : 0
        if quietSamples >= 14400 || samples.count >= 320000 { return (began,finish()) }
        return (began,nil)
    }
}

final class Recorder {
    let whisper: String, model: String, engineKind: String
    let engine=AVAudioEngine()
    let work=DispatchQueue(label:"local.pelotondesk.transcribe"), lock=NSLock()
    let capture=DispatchQueue(label:"local.pelotondesk.audio")
    var segmenter=Segmenter(), focus: AXUIElement?
    var pending=0, stopped=false, finishing=false, lastMeter=TimeInterval(0)
    var phrase=0, previewBusy=false, previewAt=TimeInterval(0)
    var asrProcess: Process?, asrInput: FileHandle?, asrOutput: FileHandle?
    var child: Process?, signals: [DispatchSourceSignal]=[]
    let directory=FileManager.default.temporaryDirectory.appendingPathComponent("peloton-desk-"+UUID().uuidString)
    init(whisper:String,model:String,engineKind:String="whisper") { self.whisper=whisper;self.model=model;self.engineKind=engineKind }
    func workerReply() throws -> [String:Any] {
        guard let output=asrOutput else { throw NSError(domain:"Parakeet",code:1) }
        var line=Data()
        while true {
            let byte=output.readData(ofLength:1)
            if byte.isEmpty { throw NSError(domain:"Parakeet",code:2) }
            if byte[0] == 10 {
                if let value=try? JSONSerialization.jsonObject(with:line) as? [String:Any] { return value }
                line.removeAll(keepingCapacity:true)
            } else {
                line.append(byte)
                if line.count > 65536 { throw NSError(domain:"Parakeet",code:3) }
            }
        }
    }
    func prepareWorker() throws {
        if asrProcess?.isRunning == true { return }
        let process=Process(), input=Pipe(), output=Pipe()
        process.executableURL=URL(fileURLWithPath:whisper)
        process.arguments=["--serve",model]
        process.standardInput=input;process.standardOutput=output;process.standardError=FileHandle.nullDevice
        lock.lock()
        if stopped || finishing { lock.unlock();throw NSError(domain:"Cancelled",code:1) }
        asrProcess=process;asrInput=input.fileHandleForWriting;asrOutput=output.fileHandleForReading
        do { try process.run() } catch { lock.unlock();throw error }
        lock.unlock()
        guard try workerReply()["ready"] as? Bool == true else { throw NSError(domain:"Parakeet",code:4) }
    }
    func readyToRecord() {
        if engineKind != "parakeet" { startEngine();return }
        emit(["type":"voice-stage","phase":"loading","message":"Chargement de Parakeet V3…"])
        work.async {
            do { try self.prepareWorker();DispatchQueue.main.async { self.startEngine() } }
            catch { emit(["type":"error","message":"Parakeet V3 n’a pas pu démarrer. Vérifiez le moteur et ses modèles."]);DispatchQueue.main.async { self.stop() } }
        }
    }
    func begin() {
        // Install both handlers before requesting audio, so Stop during startup is safe.
        for number in [SIGTERM,SIGUSR1] {
            signal(number,SIG_IGN)
            let source=DispatchSource.makeSignalSource(signal:number,queue:.main)
            source.setEventHandler { if number == SIGUSR1 { self.finish() } else { self.stop() } }
            source.resume(); signals.append(source)
        }
        AVCaptureDevice.requestAccess(for:.audio) { granted in DispatchQueue.main.async {
            if granted { self.readyToRecord() }
            else { emit(["type":"error","message":"Autorisez le micro pour Peloton Desk Mac dans les réglages du Mac."]); self.stop() }
        } }
    }
    func startEngine() {
        guard !stopped && !finishing else { return }
        do {
            try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true,attributes:[.posixPermissions:0o700])
            let input=engine.inputNode, inputFormat=engine.inputNode.outputFormat(forBus:0)
            guard inputFormat.sampleRate > 0, inputFormat.channelCount > 0,
                  let format=AVAudioFormat(commonFormat:.pcmFormatFloat32,sampleRate:16000,channels:1,interleaved:false),
                  let converter=AVAudioConverter(from:inputFormat,to:format) else { throw NSError(domain:"Microphone indisponible",code:1) }
            input.installTap(onBus:0,bufferSize:2048,format:inputFormat) { buffer,_ in
                let capacity=AVAudioFrameCount(ceil(Double(buffer.frameLength)*16000/inputFormat.sampleRate))+32
                guard let converted=AVAudioPCMBuffer(pcmFormat:format,frameCapacity:capacity) else { return }
                var supplied=false, error:NSError?
                converter.convert(to:converted,error:&error) { _,state in
                    if supplied { state.pointee = .noDataNow;return nil }
                    supplied=true;state.pointee = .haveData;return buffer
                }
                guard error == nil, let channel=converted.floatChannelData?[0] else { return }
                let samples=Array(UnsafeBufferPointer(start:channel,count:Int(converted.frameLength)))
                self.capture.async { self.consume(samples) }
            }
            try engine.start()
            emit(["type":"voice-state","active":true,"phase":"listening","microphone":AVCaptureDevice.default(for:.audio)?.localizedName ?? "Micro par défaut du Mac","accessibility":AXIsProcessTrusted(),"model":engineKind == "parakeet" ? "Parakeet V3" : "Whisper "+URL(fileURLWithPath:model).lastPathComponent.replacingOccurrences(of:"ggml-",with:"").replacingOccurrences(of:".bin",with:"")])
        } catch { emit(["type":"error","message":"Le micro du Mac n’a pas pu démarrer."]);stop() }
    }
    func consume(_ input:[Float]) {
        lock.lock(); defer { lock.unlock() }
        if stopped || finishing { return }
        let result=segmenter.accept(input)
        let now=ProcessInfo.processInfo.systemUptime
        if now-lastMeter >= 0.1 {
            lastMeter=now
            let rms=sqrt(input.reduce(Float(0)) { $0+$1*$1 } / Float(max(1,input.count)))
            emit(["type":"audio-level","rms":rms,"speaking":segmenter.speaking,"threshold":segmenter.threshold])
        }
        if result.began {
            phrase += 1;previewAt=now
            focus=focusedField()
            emit(["type":"voice-stage","phase":"speech","targetFound":focus != nil,"message":focus == nil ? "Parole détectée · texte conservé pour copie (champ non reconnu)." : "Parole détectée · champ de texte reconnu."])
        }
        if let samples=result.completed { enqueue(samples,target:focus);focus=nil }
        else if segmenter.speaking && now-previewAt >= (engineKind == "parakeet" ? 1.0 : 2.0) && !previewBusy && pending == 0 {
            previewBusy=true;previewAt=now
            let samples=segmenter.samples, currentPhrase=phrase
            work.async { self.transcribe(samples,target:nil,preview:currentPhrase) }
        }
    }
    // Caller holds lock. A missing target must never discard recorded speech.
    func enqueue(_ samples:[Float],target:AXUIElement?) {
        guard !samples.isEmpty else { return }
        if pending >= 3 {
            emit(["type":"error","message":"Transcription en retard : cette phrase n’a pas été conservée. Attendez avant de reprendre."]); return
        }
        pending += 1
        let currentPhrase=phrase
        work.async { self.transcribe(samples,target:target,phraseID:currentPhrase) }
    }
    func transcribe(_ samples:[Float],target:AXUIElement?,preview:Int?=nil,phraseID:Int=0) {
        let stem=directory.appendingPathComponent(UUID().uuidString)
        let wav=stem.appendingPathExtension("wav"), txt=stem.appendingPathExtension("txt")
        defer {
            try? FileManager.default.removeItem(at:wav);try? FileManager.default.removeItem(at:txt)
            lock.lock();if preview != nil { previewBusy=false } else { pending -= 1 };child=nil;lock.unlock()
        }
        lock.lock();let cancelled=stopped || (preview != nil && (preview != phrase || finishing));lock.unlock();if cancelled { return }
        let began=ProcessInfo.processInfo.systemUptime
        do {
            guard let format=AVAudioFormat(commonFormat:.pcmFormatFloat32,sampleRate:16000,channels:1,interleaved:false),
                  let buffer=AVAudioPCMBuffer(pcmFormat:format,frameCapacity:AVAudioFrameCount(samples.count)) else { return }
            buffer.frameLength=AVAudioFrameCount(samples.count)
            samples.withUnsafeBufferPointer { src in buffer.floatChannelData![0].update(from:src.baseAddress!,count:samples.count) }
            let settings:[String:Any]=[AVFormatIDKey:kAudioFormatLinearPCM,AVSampleRateKey:16000,AVNumberOfChannelsKey:1,AVLinearPCMBitDepthKey:16,AVLinearPCMIsFloatKey:false,AVLinearPCMIsBigEndianKey:false]
            var file:AVAudioFile?=try AVAudioFile(forWriting:wav,settings:settings,commonFormat:.pcmFormatFloat32,interleaved:false)
            try file?.write(from:buffer);file=nil
            if preview == nil { emit(["type":"voice-stage","phase":"transcribing","message":"Transcription locale…","audioSeconds":Double(samples.count)/16000]) }
            let transcript:String
            if engineKind == "parakeet" {
                try prepareWorker()
                let request=try JSONSerialization.data(withJSONObject:["path":wav.path])
                try asrInput?.write(contentsOf:request+Data([10]))
                guard let result=try workerReply()["text"] as? String else { throw NSError(domain:"Parakeet",code:5) }
                transcript=result
            } else {
                let process=Process();process.executableURL=URL(fileURLWithPath:whisper)
                process.arguments=["-m",model,"-f",wav.path,"-l","auto","-nt","-np","-otxt","-of",stem.path]
                if preview != nil { process.arguments! += ["-bs","1","-bo","1"] }
                process.standardOutput=FileHandle.nullDevice;process.standardError=FileHandle.nullDevice
                lock.lock()
                if stopped { lock.unlock();return }
                child=process
                do { try process.run() } catch { lock.unlock();throw error }
                lock.unlock()
                process.waitUntilExit()
                guard process.terminationStatus == 0 else { throw NSError(domain:"Transcription",code:Int(process.terminationStatus)) }
                transcript=try String(contentsOf:txt,encoding:.utf8)
            }
            let text=cleanTranscript(transcript)
            lock.lock();let mayInsert = !stopped;lock.unlock()
            if let preview=preview {
                lock.lock();let current = !stopped && phrase == preview && segmenter.speaking;lock.unlock()
                if current && !text.isEmpty { emit(["type":"transcription-preview","text":text,"phraseId":preview,"elapsedMs":Int((ProcessInfo.processInfo.systemUptime-began)*1000)]) }
            } else if mayInsert {
                let posted = !text.isEmpty && target.map { insert(text,into:$0) } == true
                let message = text.isEmpty ? "Aucun texte reconnu." : posted ? "Collage envoyé au champ actif." : "Texte reconnu · conservé ici, aucun collage automatique."
                emit(["type":"transcription","phraseId":phraseID,"inserted":posted,"text":text,"message":message,"targetFound":target != nil,"elapsedMs":Int((ProcessInfo.processInfo.systemUptime-began)*1000)])
            }
        } catch {
            lock.lock();let cancelled=stopped;lock.unlock()
            if !cancelled && preview == nil { emit(["type":"error","message":"La transcription locale a échoué.","code":(error as NSError).code]) }
        }
    }
    func finish() {
        engine.stop()
        capture.sync {} // Drain already captured buffers before flushing the last phrase.
        lock.lock()
        if stopped || finishing { lock.unlock();return }
        finishing=true
        let tail=segmenter.finish();enqueue(tail,target:focus);focus=nil
        lock.unlock()
        engine.stop()
        emit(["type":"voice-state","active":false,"phase":"finishing"])
        work.async { DispatchQueue.main.async { self.stop() } }
    }
    func stop() {
        lock.lock()
        if stopped { lock.unlock();return }
        stopped=true;let process=child, worker=asrProcess;lock.unlock()
        engine.stop()
        if process?.isRunning == true { process?.terminate() }
        if worker?.isRunning == true { worker?.terminate() }
        // Let the in-flight paste restore the clipboard before exiting.
        work.async { DispatchQueue.main.async {
            try? FileManager.default.removeItem(at:self.directory)
            emit(["type":"voice-state","active":false,"phase":"idle"])
            exit(0)
        } }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate, NSWindowDelegate {
    var item: NSStatusItem!, server: Process?
    var launcher: Process?, openItem: NSMenuItem!, statusItem: NSMenuItem!, loginItem: NSMenuItem!
    var permissionsItem: NSMenuItem!, permissionsTimer: Timer?
    var signalSource: DispatchSourceSignal?
    var voiceWindow: NSWindow?
    var permissionSignal: DispatchSourceSignal?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        item=NSStatusBar.system.statusItem(withLength:NSStatusItem.variableLength)
        let icon=NSImage(systemSymbolName:"bicycle",accessibilityDescription:"Peloton Desk")
        icon?.isTemplate=true
        icon?.size=NSSize(width:22,height:18)
        item.button?.image=icon
        item.button?.setAccessibilityLabel("Peloton Desk")
        item.button?.toolTip="Peloton Desk — ouvrir le bureau sur le Bike"
        let menu=NSMenu()
        menu.delegate=self
        menu.autoenablesItems=false
        let title=NSMenuItem(title:"Peloton Desk · compagnon Mac",action:nil,keyEquivalent:"");title.isEnabled=false;menu.addItem(title)
        openItem=NSMenuItem(title:"Ouvrir le bureau sur le Bike",action:#selector(openBike),keyEquivalent:"d")
        menu.addItem(openItem)
        statusItem=NSMenuItem(title:"Prêt",action:nil,keyEquivalent:"");statusItem.isEnabled=false;menu.addItem(statusItem)
        menu.addItem(.separator())
        permissionsItem=NSMenuItem(title:"Autorisations de dictée…",action:#selector(permissions),keyEquivalent:"")
        menu.addItem(permissionsItem)
        menu.addItem(NSMenuItem(title:"Tester la dictée sur le Mac…",action:#selector(testVoice),keyEquivalent:"t"))
        loginItem=NSMenuItem(title:"Démarrer avec le Mac",action:#selector(toggleLogin),keyEquivalent:"")
        menu.addItem(loginItem)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title:"Quitter Peloton Desk",action:#selector(quit),keyEquivalent:"q"))
        for option in menu.items { option.target=self };item.menu=menu
        updateLoginItem()
        updatePermissionsItem()
        permissionsTimer=Timer(timeInterval:5,repeats:true) { [weak self] _ in self?.updatePermissionsItem() }
        RunLoop.main.add(permissionsTimer!,forMode:.common)
        signal(SIGTERM,SIG_IGN)
        signalSource=DispatchSource.makeSignalSource(signal:SIGTERM,queue:.main)
        signalSource?.setEventHandler { [weak self] in self?.quit() }
        signalSource?.resume()
        signal(SIGUSR2,SIG_IGN)
        permissionSignal=DispatchSource.makeSignalSource(signal:SIGUSR2,queue:.main)
        permissionSignal?.setEventHandler { [weak self] in self?.permissions() }
        permissionSignal?.resume()
        openDesktop(showErrors:false)
        if !UserDefaults.standard.bool(forKey:"VoicePreviewIntroducedV2") {
            UserDefaults.standard.set(true,forKey:"VoicePreviewIntroducedV2")
            DispatchQueue.main.asyncAfter(deadline:.now()+1) { self.testVoice() }
        }
    }

    func configuration() throws -> (URL,String) {
        guard let root=Bundle.main.object(forInfoDictionaryKey:"PDProjectRoot") as? String else {
            throw NSError(domain:"Installation incomplète",code:1)
        }
        let base=URL(fileURLWithPath:root)
        let connection=try JSONSerialization.jsonObject(with:Data(contentsOf:base.appendingPathComponent(".local/connection.json"))) as? [String:String]
        guard let serial=connection?["serial"], !serial.isEmpty else { throw NSError(domain:"Bike non configuré",code:1) }
        return (base,serial)
    }

    var environment: [String:String] {
        var value=ProcessInfo.processInfo.environment
        value["PATH"]="/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        value["PELOTON_DESK_HELPER"]=Bundle.main.executableURL?.path
        value["PELOTON_DESK_APP_PID"]=String(ProcessInfo.processInfo.processIdentifier)
        return value
    }

    func startServer(base:URL,serial:String) throws {
        if server?.isRunning == true { return }
        let process=Process();process.executableURL=base.appendingPathComponent(".venv/bin/python")
        process.arguments=[base.appendingPathComponent("macos/companion.py").path,"--serial",serial,"--no-open"]
        process.environment=environment
        let log=base.appendingPathComponent(".local/companion.log")
        FileManager.default.createFile(atPath:log.path,contents:nil,attributes:[.posixPermissions:0o600])
        let handle=try FileHandle(forWritingTo:log)
        defer { try? handle.close() }
        process.standardOutput=handle;process.standardError=handle
        process.terminationHandler = { [weak self] finished in
            DispatchQueue.main.async {
                guard let self=self, self.server === finished else { return }
                self.statusItem.title="Compagnon arrêté — cliquez pour relancer"
            }
        }
        server=process
        try process.run()
    }

    @objc func testVoice() {
        do {
            let (base,serial)=try configuration()
            try startServer(base:base,serial:serial)
            if let window=voiceWindow { window.makeKeyAndOrderFront(nil);NSApp.activate(ignoringOtherApps:true);return }
            let token=try String(contentsOf:base.appendingPathComponent(".local/connection-token"),encoding:.utf8).trimmingCharacters(in:.whitespacesAndNewlines)
            guard let url=URL(string:"http://127.0.0.1:8765/voice.html#token="+token) else { return }
            let web=WKWebView(frame:NSRect(x:0,y:0,width:560,height:720))
            let window=NSWindow(contentRect:web.frame,styleMask:[.titled,.closable,.miniaturizable,.resizable],backing:.buffered,defer:false)
            window.title="Peloton Desk · Dictée";window.level = .floating;window.contentView=web;window.isReleasedWhenClosed=false;window.delegate=self
            window.center();window.makeKeyAndOrderFront(nil);voiceWindow=window
            NSApp.activate(ignoringOtherApps:true)
            web.load(URLRequest(url:url))
        } catch { showError("La fenêtre de dictée n’a pas pu s’ouvrir. Relancez le compagnon.") }
    }

    func windowWillClose(_ notification:Notification) {
        guard let window=notification.object as? NSWindow, window === voiceWindow else { return }
        (window.contentView as? WKWebView)?.evaluateJavaScript("window.stopDictation?.()",completionHandler:nil)
    }

    @objc func openBike() { openDesktop(showErrors:true) }

    func openDesktop(showErrors:Bool) {
        guard launcher == nil else { return }
        do {
            let (base,serial)=try configuration()
            try startServer(base:base,serial:serial)
            let process=Process();process.executableURL=base.appendingPathComponent(".venv/bin/python")
            process.arguments=[base.appendingPathComponent("tools/app.py").path,"open","--serial",serial]
            process.environment=environment
            let pipe=Pipe();process.standardOutput=pipe;process.standardError=pipe
            process.terminationHandler = { [weak self] finished in
                let output=String(data:pipe.fileHandleForReading.readDataToEndOfFile(),encoding:.utf8)?.trimmingCharacters(in:.whitespacesAndNewlines) ?? ""
                DispatchQueue.main.async {
                    guard let self=self else { return }
                    self.launcher=nil;self.openItem.isEnabled=true
                    let success=finished.terminationStatus==0 && self.server?.isRunning==true
                    self.statusItem.title=success ? "Bureau ouvert sur le Bike" : "Bike non connecté — réessayer"
                    if !success && showErrors {
                        self.showError(output.isEmpty ? "Allumez le Bike et vérifiez le Wi-Fi et Wireless debugging." : output)
                    }
                }
            }
            launcher=process;openItem.isEnabled=false;statusItem.title="Connexion au Bike…"
            try process.run()
        } catch {
            launcher=nil;openItem.isEnabled=true;statusItem.title="Installation à vérifier"
            if showErrors { showError("Vérifiez que l’installation de Peloton Desk est terminée.") }
        }
    }

    func applicationShouldHandleReopen(_ sender:NSApplication,hasVisibleWindows:Bool) -> Bool {
        openDesktop(showErrors:true)
        return false
    }

    func showError(_ message:String) {
        let alert=NSAlert();alert.messageText="Peloton Desk";alert.informativeText=message;alert.runModal()
    }

    func updateLoginItem() {
        loginItem.state=SMAppService.mainApp.status == .enabled ? .on : .off
    }

    func menuNeedsUpdate(_ menu:NSMenu) {
        updateLoginItem()
        updatePermissionsItem()
    }

    var permissionsURL:URL? {
        guard let root=Bundle.main.object(forInfoDictionaryKey:"PDProjectRoot") as? String else { return nil }
        return URL(fileURLWithPath:root).appendingPathComponent(".local/permissions.json")
    }

    func updatePermissionsItem() {
        let microphone=AVCaptureDevice.authorizationStatus(for:.audio)
        let accessibility=AXIsProcessTrusted()
        let ready=microphone == .authorized && accessibility
        if ready { permissionsItem.title="Dictée autorisée ✓" }
        else if microphone == .authorized { permissionsItem.title="Dictée : autoriser l’accessibilité…" }
        else if accessibility { permissionsItem.title="Dictée : autoriser le micro…" }
        else { permissionsItem.title="Autorisations de dictée…" }
        permissionsItem.isEnabled = !ready
        let microphoneName:String
        switch microphone {
        case .authorized: microphoneName="authorized"
        case .denied: microphoneName="denied"
        case .restricted: microphoneName="restricted"
        case .notDetermined: microphoneName="notDetermined"
        @unknown default: microphoneName="unknown"
        }
        // The installed menu app checks its own TCC identity; the Python gateway
        // must not infer permission from the mere presence of Whisper files.
        let state:[String:Any] = ["microphone":microphoneName,"accessibility":accessibility,
                                 "updatedAt":Date().timeIntervalSince1970]
        if let url=permissionsURL, let data=try? JSONSerialization.data(withJSONObject:state) {
            try? data.write(to:url,options:.atomic)
            try? FileManager.default.setAttributes([.posixPermissions:0o600],ofItemAtPath:url.path)
        }
    }

    @objc func toggleLogin() {
        do {
            if SMAppService.mainApp.status == .enabled { try SMAppService.mainApp.unregister() }
            else { try SMAppService.mainApp.register() }
            updateLoginItem()
            if SMAppService.mainApp.status == .requiresApproval { SMAppService.openSystemSettingsLoginItems() }
        } catch { showError("Le démarrage automatique n’a pas pu être modifié. Vérifiez Réglages Système → Général → Ouverture et extensions.") }
    }

    @objc func permissions() {
        if !AXIsProcessTrusted() {
            let options=[kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String:true] as CFDictionary
            _=AXIsProcessTrustedWithOptions(options)
        }
        switch AVCaptureDevice.authorizationStatus(for:.audio) {
        case .notDetermined:
            AVCaptureDevice.requestAccess(for:.audio) { _ in
                DispatchQueue.main.async { self.updatePermissionsItem() }
            }
        case .denied, .restricted:
            if let url=URL(string:"x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
                NSWorkspace.shared.open(url)
            }
        default: break
        }
        updatePermissionsItem()
    }
    @objc func quit() { NSApp.terminate(nil) }
    func applicationWillTerminate(_ notification:Notification) {
        permissionsTimer?.invalidate()
        if let url=permissionsURL { try? FileManager.default.removeItem(at:url) }
        if launcher?.isRunning == true { launcher?.terminate() }
        if server?.isRunning == true { server?.terminate() }
    }
}

let args=CommandLine.arguments
if args.contains("--self-test") {
    precondition(cleanTranscript("  Bonjour\nça marche\t!  ")=="Bonjour ça marche !")
    precondition(cleanTranscript("[BLANK_AUDIO]").isEmpty)
    var segmenter=Segmenter()
    precondition(!segmenter.accept(Array(repeating:Float(0),count:16000)).began)
    precondition(segmenter.accept(Array(repeating:Float(0.05),count:8000)).began)
    let complete=segmenter.accept(Array(repeating:Float(0),count:16000)).completed
    precondition(complete != nil && complete!.count >= 24000)
    precondition(!segmenter.speaking)
    _=segmenter.accept(Array(repeating:Float(0.1),count:500))
    precondition(segmenter.accept(Array(repeating:Float(0),count:16000)).completed?.isEmpty == true)
    var tail=Segmenter()
    _=tail.accept(Array(repeating:Float(0.01),count:8000))
    precondition(tail.finish().count == 8000)
    precondition(tail.finish().isEmpty)
    print("Voice segmentation checks passed; no microphone or input events used.")
} else if args.count==5 && ["--check-audio","--check-parakeet"].contains(args[1]) {
    // Offline fixture check: no microphone, focus lookup or input injection.
    do {
        let file=try AVAudioFile(forReading:URL(fileURLWithPath:args[4]))
        guard file.processingFormat.sampleRate == 16000, file.processingFormat.channelCount == 1,
              let buffer=AVAudioPCMBuffer(pcmFormat:file.processingFormat,frameCapacity:AVAudioFrameCount(file.length)) else { exit(2) }
        try file.read(into:buffer)
        let recorder=Recorder(whisper:args[2],model:args[3],engineKind:args[1]=="--check-parakeet" ? "parakeet" : "whisper");recorder.pending=1
        try FileManager.default.createDirectory(at:recorder.directory,withIntermediateDirectories:true,attributes:[.posixPermissions:0o700])
        recorder.transcribe(Array(UnsafeBufferPointer(start:buffer.floatChannelData![0],count:Int(buffer.frameLength))),target:nil)
        if recorder.asrProcess?.isRunning == true { recorder.asrProcess?.terminate() }
        try? FileManager.default.removeItem(at:recorder.directory)
    } catch { print("Audio fixture check failed.");exit(1) }
} else if args.count==4 && ["--voice","--voice-parakeet"].contains(args[1]) {
    let recorder=Recorder(whisper:args[2],model:args[3],engineKind:args[1]=="--voice-parakeet" ? "parakeet" : "whisper");recorder.begin();RunLoop.main.run()
} else if args.contains("--enable-login") || args.contains("--login-status") {
    do {
        if args.contains("--enable-login") && SMAppService.mainApp.status != .enabled {
            try SMAppService.mainApp.register()
        }
        switch SMAppService.mainApp.status {
        case .enabled: print("Login item enabled")
        case .requiresApproval: print("Login item requires approval in System Settings"); exit(2)
        case .notRegistered: print("Login item not registered"); exit(1)
        case .notFound: print("Login item bundle not found"); exit(1)
        @unknown default: print("Unknown login item status"); exit(1)
        }
    } catch { print("Login item registration failed: \(error.localizedDescription)"); exit(1) }
} else {
    let delegate=AppDelegate();let app=NSApplication.shared;app.delegate=delegate;app.run()
}
