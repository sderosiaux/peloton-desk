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
struct InputTarget {
    let pid: pid_t
    let window: AXUIElement?, element: AXUIElement?
    let mode: String
    func mismatch() -> String? {
        guard let current=inputTarget() else { return "target_unavailable" }
        guard current.pid == pid else { return "application_changed" }
        if let window=window {
            guard let other=current.window, CFEqual(window,other) else { return "window_changed" }
        }
        if let element=element {
            // Web editors may recreate their AX object while retaining keyboard
            // focus. Compare a stable identifier when exposed, not object identity.
            // Without one, the current OS focus in this app/window is authoritative.
            if let other=current.element,
               let identifier=axValue(element,kAXIdentifierAttribute) as? String,!identifier.isEmpty,
               let otherIdentifier=axValue(other,kAXIdentifierAttribute) as? String,!otherIdentifier.isEmpty,
               identifier != otherIdentifier { return "element_changed" }
        }
        return nil
    }
    func isCurrent() -> Bool { mismatch() == nil }
}

struct InputFocus {
    let target: InputTarget?
    let reason: String
}

final class ActiveApplication {
    static let shared=ActiveApplication()
    private let lock=NSLock()
    private var pid:pid_t?
    private var observer:NSObjectProtocol?,timer:Timer?
    func currentPID() -> pid_t? { lock.lock();defer { lock.unlock() };return pid }
    private func set(_ app:NSRunningApplication?) { lock.lock();pid=app?.processIdentifier;lock.unlock() }
    func start() {
        precondition(Thread.isMainThread)
        guard observer == nil else { return }
        // Initialize NSWorkspace and its notification delivery on the main loop.
        // A first access from the audio queue can leave its cached focus stale.
        let workspace=NSWorkspace.shared
        set(workspace.frontmostApplication)
        observer=workspace.notificationCenter.addObserver(forName:NSWorkspace.didActivateApplicationNotification,object:nil,queue:.main) { [weak self] notification in
            self?.set(notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)
        }
        timer=Timer.scheduledTimer(withTimeInterval:0.25,repeats:true) { [weak self] _ in self?.set(workspace.frontmostApplication) }
    }
}

func inputTarget() -> InputTarget? { probeInputFocus().target }

func probeInputFocus() -> InputFocus {
    func blocked(_ reason:String) -> InputFocus { InputFocus(target:nil,reason:reason) }
    guard AXIsProcessTrusted() else { return blocked("accessibility_denied") }
    guard !IsSecureEventInputEnabled() else { return blocked("secure_input") }
    // App activation is tracked by the main loop; query its current AX focus
    // every time. System-wide AXFocusedApplication is unavailable on some Macs.
    let system=AXUIElementCreateSystemWide()
    guard let appPID=ActiveApplication.shared.currentPID() else { return blocked("application_unavailable") }
    let application=AXUIElementCreateApplication(appPID)
    guard NSRunningApplication(processIdentifier:appPID)?.bundleIdentifier != "local.pelotondesk.mac" else { return blocked("companion_focused") }
    let window=axElement(axValue(application,kAXFocusedWindowAttribute))
    var element=axElement(axValue(application,kAXFocusedUIElementAttribute)) ?? axElement(axValue(system,kAXFocusedUIElementAttribute))
    if let first=element {
        var owner:pid_t=0
        if AXUIElementGetPid(first,&owner) != .success || owner != appPID { element=nil }
    }
    guard var focused=element else {
        return InputFocus(target:InputTarget(pid:appPID,window:window,element:nil,mode:"system"),reason:"")
    }
    for _ in 0..<4 {
        guard let child=axElement(axValue(focused,kAXFocusedUIElementAttribute)),!CFEqual(child,focused) else { break }
        focused=child
    }
    if axValue(focused,kAXSubroleAttribute) as? String == "AXSecureTextField" { return blocked("secure_input") }
    let role=axValue(focused,kAXRoleAttribute) as? String ?? ""
    var writable:DarwinBoolean=false
    AXUIElementIsAttributeSettable(focused,kAXSelectedTextAttribute as CFString,&writable)
    if ["AXButton","AXCheckBox","AXRadioButton","AXMenuItem","AXPopUpButton","AXSlider","AXLink","AXStaticText","AXImage","AXToolbar","AXScrollBar"].contains(role) { return blocked("non_editable") }
    var pid:pid_t=0
    guard AXUIElementGetPid(focused,&pid) == .success,pid == appPID else { return blocked("focus_changed") }
    let textField=["AXTextField","AXTextArea","AXComboBox"].contains(role) || writable.boolValue
    return InputFocus(target:InputTarget(pid:pid,window:window,element:focused,mode:textField ? "field" : "system"),reason:"")
}

func cleanTranscript(_ text: String) -> String {
    let clean=text.split(whereSeparator: { $0.isNewline || $0 == "\t" }).joined(separator:" ").trimmingCharacters(in:.whitespaces)
    guard !clean.isEmpty, clean.count < 3000, !clean.hasPrefix("[BLANK_AUDIO]") else { return "" }
    return clean
}

func isNonContentUtterance(_ text:String) -> Bool {
    // Only discard utterances made entirely of known fillers. Short commands,
    // yes/no answers, numbers, and phrases containing a filler remain intact.
    let normalized=text.folding(options:[.diacriticInsensitive,.caseInsensitive],locale:Locale(identifier:"fr_FR"))
    let words=normalized.split(whereSeparator:{ !$0.isLetter && !$0.isNumber }).map(String.init)
    guard !words.isEmpty else { return !text.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty }
    let fillers:Set<String>=["ok","okay","okey","euh","heu","hum","hmm","hm","mm","mmm","ah","ha","eh","he","oh","ho","bah","ben","bon","alors","donc","voila","uh","um","erm"]
    return words.allSatisfy { fillers.contains($0) || $0.range(of:"^(?:ha|ah|he|eh|hi|oh|ho){2,}$",options:.regularExpression) != nil }
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

struct DeliveryResult { var pasted=false, enterPosted=false; var reason="" }

struct PhraseText {
    var parts=[String]()
    func preview(_ text:String) -> String { (parts + [text]).filter { !$0.isEmpty }.joined(separator:" ") }
    mutating func accept(_ text:String,final:Bool) -> String? {
        if !text.isEmpty { parts.append(text) }
        guard final else { return nil }
        let result=parts.joined(separator:" ");parts=[];return result
    }
}

func postReturn(to target:InputTarget,cancelled:()->Bool) -> Bool {
    guard !cancelled(),target.isCurrent() else { return false }
    let source=CGEventSource(stateID:.privateState)
    guard let down=CGEvent(keyboardEventSource:source,virtualKey:CGKeyCode(kVK_Return),keyDown:true),
          let up=CGEvent(keyboardEventSource:source,virtualKey:CGKeyCode(kVK_Return),keyDown:false) else { return false }
    down.flags=[];up.flags=[]
    down.post(tap:.cgSessionEventTap)
    Thread.sleep(forTimeInterval:0.01)
    up.post(tap:.cgSessionEventTap)
    return true
}

// Keep Return dependent on a completed paste and a fresh focus/cancellation check.
// Injected operations also let self-tests check ordering without keyboard events.
func deliver(sendReturn:Bool, ready:()->Bool, paste:()->Bool, settle:()->Void, enter:()->Bool) -> DeliveryResult {
    guard ready(), paste() else { return DeliveryResult() }
    settle()
    return DeliveryResult(pasted:true,enterPosted:sendReturn && ready() && enter())
}

// A posted shortcut is not proof that the destination accepted the text/message.
func insert(_ text: String, into expected: InputTarget, sendReturn:Bool, cancelled:()->Bool) -> DeliveryResult {
    var reason=""
    func ready() -> Bool {
        reason = cancelled() ? "cancelled" : expected.mismatch() ?? ""
        return reason.isEmpty
    }
    let clean=cleanTranscript(text)
    let source=CGEventSource(stateID:.privateState)
    guard !clean.isEmpty else { return DeliveryResult(reason:"empty") }
    guard ready() else { return DeliveryResult(reason:reason) }
    guard let key=pasteKey() else { return DeliveryResult(reason:"keyboard_layout") }
    guard let down=CGEvent(keyboardEventSource:source,virtualKey:key,keyDown:true),
          let up=CGEvent(keyboardEventSource:source,virtualKey:key,keyDown:false) else { return DeliveryResult(reason:"keyboard_event") }
    let board=NSPasteboard.general
    let saved=(board.pasteboardItems ?? []).map { item in
        item.types.compactMap { type -> (NSPasteboard.PasteboardType,Data)? in
            guard let data=item.data(forType:type) else { return nil }; return (type,data)
        }
    }
    board.clearContents()
    let wrote=board.setString(clean + (sendReturn ? "" : " "),forType:.string)
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
    guard wrote else { return DeliveryResult(reason:"clipboard") }
    Thread.sleep(forTimeInterval:0.05)
    var result=deliver(sendReturn:sendReturn,ready:ready,paste:{
        down.flags = .maskCommand; up.flags = .maskCommand
        down.post(tap:.cgSessionEventTap)
        Thread.sleep(forTimeInterval:0.01)
        up.post(tap:.cgSessionEventTap)
        return true
    },settle:{ Thread.sleep(forTimeInterval:0.7) },enter:{ postReturn(to:expected,cancelled:cancelled) })
    result.reason=reason
    return result
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
    mutating func accept(_ input: [Float]) -> (began: Bool, completed: [Float]?, ended:Bool) {
        guard !input.isEmpty else { return (false,nil,false) }
        let rms=sqrt(input.reduce(Float(0)) { $0+$1*$1 } / Float(input.count))
        var began=false
        if !speaking {
            if rms >= threshold { speaking=true; began=true; samples=lead; quietSamples=0 }
            else {
                lead.append(contentsOf:input)
                if lead.count > 3200 { lead.removeFirst(lead.count-3200) }
                return (false,nil,false)
            }
        }
        samples.append(contentsOf:input)
        if rms >= threshold { voicedSamples += input.count }
        quietSamples = rms < threshold ? quietSamples+input.count : 0
        if quietSamples >= 14400 { return (began,finish(),true) }
        if samples.count >= 320000 {
            let chunk=samples
            // Bound ASR work without treating the 20-second boundary as a pause.
            samples=[];voicedSamples=0
            return (began,chunk,false)
        }
        return (began,nil,false)
    }
}

final class Recorder {
    let whisper: String, model: String, engineKind: String
    let sendReturn: Bool
    let engine=AVAudioEngine()
    let work=DispatchQueue(label:"local.pelotondesk.transcribe"), lock=NSLock()
    let capture=DispatchQueue(label:"local.pelotondesk.audio")
    var segmenter=Segmenter()
    var pending=0, stopped=false, finishing=false, lastMeter=TimeInterval(0)
    var phrase=0, previewBusy=false, previewAt=TimeInterval(0)
    var phraseText=PhraseText() // Accessed only on the serial transcription queue.
    var asrProcess: Process?, asrInput: FileHandle?, asrOutput: FileHandle?
    var child: Process?, signals: [DispatchSourceSignal]=[]
    let directory=FileManager.default.temporaryDirectory.appendingPathComponent("peloton-desk-"+UUID().uuidString)
    init(whisper:String,model:String,engineKind:String="whisper",sendReturn:Bool=false) { self.whisper=whisper;self.model=model;self.engineKind=engineKind;self.sendReturn=sendReturn }
    func cancelled() -> Bool { lock.lock();defer { lock.unlock() };return stopped }
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
        ActiveApplication.shared.start()
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
            emit(["type":"voice-state","active":true,"phase":"listening","sendReturn":sendReturn,"microphone":AVCaptureDevice.default(for:.audio)?.localizedName ?? "Micro par défaut du Mac","accessibility":AXIsProcessTrusted(),"model":engineKind == "parakeet" ? "Parakeet V3" : "Whisper "+URL(fileURLWithPath:model).lastPathComponent.replacingOccurrences(of:"ggml-",with:"").replacingOccurrences(of:".bin",with:"")])
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
            emit(["type":"voice-stage","phase":"speech","message":"Parole détectée · sélectionnez votre destination avant la pause."])
        }
        if let samples=result.completed {
            enqueue(samples,focus:probeInputFocus(),endOfUtterance:result.ended)
        }
        else if segmenter.speaking && now-previewAt >= (engineKind == "parakeet" ? 1.0 : 2.0) && !previewBusy && pending == 0 {
            previewBusy=true;previewAt=now
            let samples=segmenter.samples, currentPhrase=phrase
            work.async { self.transcribe(samples,target:nil,preview:currentPhrase) }
        }
    }
    // Caller holds lock. A missing target must never discard recorded speech.
    func enqueue(_ samples:[Float],focus:InputFocus,endOfUtterance:Bool=true) {
        guard !samples.isEmpty || (sendReturn && endOfUtterance) else { return }
        if pending >= 3 {
            emit(["type":"error","message":"Transcription en retard : cette phrase n’a pas été conservée. Attendez avant de reprendre."]); return
        }
        pending += 1
        let currentPhrase=phrase
        work.async { self.transcribe(samples,target:focus.target,phraseID:currentPhrase,endOfUtterance:endOfUtterance,targetReason:focus.reason) }
    }
    func transcribe(_ samples:[Float],target:InputTarget?,preview:Int?=nil,phraseID:Int=0,endOfUtterance:Bool=true,targetReason:String="no_target") {
        let stem=directory.appendingPathComponent(UUID().uuidString)
        let wav=stem.appendingPathExtension("wav"), txt=stem.appendingPathExtension("txt")
        defer {
            try? FileManager.default.removeItem(at:wav);try? FileManager.default.removeItem(at:txt)
            lock.lock();if preview != nil { previewBusy=false } else { pending -= 1 };child=nil;lock.unlock()
        }
        lock.lock();let cancelled=stopped || (preview != nil && (preview != phrase || finishing));lock.unlock();if cancelled { return }
        if samples.isEmpty {
            if endOfUtterance,sendReturn,!phraseText.parts.isEmpty {
                completeTranscript("",target:target,phraseID:phraseID,endOfUtterance:true,targetReason:targetReason,began:ProcessInfo.processInfo.systemUptime)
            }
            return
        }
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
                if current && !text.isEmpty { emit(["type":"transcription-preview","text":sendReturn ? phraseText.preview(text) : text,"phraseId":preview,"elapsedMs":Int((ProcessInfo.processInfo.systemUptime-began)*1000)]) }
            } else if mayInsert {
                completeTranscript(text,target:target,phraseID:phraseID,endOfUtterance:endOfUtterance,targetReason:targetReason,began:began)
            }
        } catch {
            lock.lock();let cancelled=stopped;lock.unlock()
            if !cancelled && preview == nil { emit(["type":"error","message":"La transcription locale a échoué.","code":(error as NSError).code]) }
        }
    }
    func completeTranscript(_ chunk:String,target:InputTarget?,phraseID:Int,endOfUtterance:Bool,targetReason:String,began:TimeInterval) {
        let text:String
        if sendReturn {
            guard let completed=phraseText.accept(chunk,final:endOfUtterance) else {
                emit(["type":"transcription-preview","text":phraseText.preview(""),"phraseId":phraseID]);return
            }
            text=completed
        } else { text=chunk }
        if isNonContentUtterance(text) {
            emit(["type":"transcription-ignored","phraseId":phraseID,"deliveryReason":"non_content","characters":text.count,"message":"Interjection ignorée · à l’écoute."])
            return
        }
        // Unknown containers may be a page background, not an editor.
        let result:DeliveryResult
        if sendReturn && target?.mode == "system" { result=DeliveryResult(reason:"input_not_confirmed") }
        else { result=target.map { insert(text,into:$0,sendReturn:sendReturn && endOfUtterance,cancelled:self.cancelled) } ?? DeliveryResult(reason:targetReason) }
        let message = text.isEmpty ? "Aucun texte reconnu." : result.enterPosted ? "Collage puis Entrée envoyés à l’application active." : result.pasted ? "Collage envoyé au champ actif." : result.reason == "companion_focused" ? "Fenêtre de dictée active · texte conservé ici pour copie." : ["non_editable","input_not_confirmed"].contains(result.reason) ? "Aucun champ de saisie confirmé · texte conservé ici pour copie." : "Focus modifié ou indisponible · texte conservé ici pour copie."
        emit(["type":"transcription","phraseId":phraseID,"inserted":result.pasted,"enterPosted":result.enterPosted,"deliveryReason":result.reason,"text":text,"message":message,"targetFound":target != nil,"targetMode":target?.mode ?? "none","elapsedMs":Int((ProcessInfo.processInfo.systemUptime-began)*1000)])
    }
    func finish() {
        engine.stop()
        capture.sync {} // Drain already captured buffers before flushing the last phrase.
        lock.lock()
        if stopped || finishing { lock.unlock();return }
        finishing=true
        let tail=segmenter.finish();enqueue(tail,focus:probeInputFocus())
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
if args.contains("--check-input-config") {
    // No focus lookup, clipboard access, microphone or input events.
    emit(["accessibility":AXIsProcessTrusted(),"pasteKeyAvailable":pasteKey() != nil])
} else if args.contains("--self-test") {
    MusicAnalyzer.selfTest()
    for text in ["Ha ha.","Ha ha ha.","Okay.","OK… euh, bon.","Hahaha !","Héhéhé.","Euh…","Hmm","Alors, voilà.","..."] {
        precondition(isNonContentUtterance(text),"Unfiltered filler: \(text)")
    }
    for text in ["Continue.","Arrête.","Stop.","Oui.","Non.","42","OK, corrige ce bug.","Euh, affiche les logs.","C’est bon ?","Pourquoi ?","git status","Haha, ça fonctionne !",""] {
        precondition(!isNonContentUtterance(text),"Discarded useful utterance: \(text)")
    }
    var phraseText=PhraseText()
    precondition(phraseText.accept("Un début",final:false) == nil)
    precondition(phraseText.preview("provisoire") == "Un début provisoire")
    precondition(phraseText.accept("puis la suite.",final:true) == "Un début puis la suite.")
    precondition(phraseText.parts.isEmpty)
    _=phraseText.accept("Une phrase finie à la limite du segment.",final:false)
    precondition(phraseText.accept("",final:true) == "Une phrase finie à la limite du segment.")
    var deliveryEvents=[String](), destinationCurrent=true
    func deliveryTest(send:Bool=true,pasteSucceeds:Bool=true,changeFocus:Bool=false) -> DeliveryResult {
        deliveryEvents=[];destinationCurrent=true
        return deliver(sendReturn:send,ready:{ destinationCurrent },paste:{
            deliveryEvents.append("paste");return pasteSucceeds
        },settle:{
            deliveryEvents.append("settle");if changeFocus { destinationCurrent=false }
        },enter:{ deliveryEvents.append("enter");return true })
    }
    precondition(deliveryTest().enterPosted && deliveryEvents == ["paste","settle","enter"])
    let pasteOnly=deliveryTest(send:false)
    precondition(pasteOnly.pasted && !pasteOnly.enterPosted && deliveryEvents == ["paste","settle"])
    precondition(!deliveryTest(pasteSucceeds:false).pasted && deliveryEvents == ["paste"])
    let moved=deliveryTest(changeFocus:true)
    precondition(moved.pasted && !moved.enterPosted && deliveryEvents == ["paste","settle"])
    let cancelled=deliver(sendReturn:true,ready:{ false },paste:{ fatalError("Paste after cancellation") },settle:{},enter:{ fatalError("Return after cancellation") })
    precondition(!cancelled.pasted && !cancelled.enterPosted)
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
    var longPhrase=Segmenter()
    let chunk=longPhrase.accept(Array(repeating:Float(0.05),count:320000))
    precondition(chunk.completed?.count == 320000 && !chunk.ended && longPhrase.speaking)
    let pause=longPhrase.accept(Array(repeating:Float(0),count:16000))
    precondition(pause.ended && pause.completed?.isEmpty == true && !longPhrase.speaking)
    print("Voice segmentation and paste/Return sequencing checks passed; no microphone or input events used.")
} else if args.contains("--music-info") {
    if #available(macOS 14.2, *) {
        emit(["supported":true,"spotifyProcesses":MusicCapture.spotifyProcesses().count])
    } else { emit(["supported":false,"spotifyProcesses":0]) }
} else if args.contains("--music") {
    if #available(macOS 14.2, *) {
        let capture=MusicCapture();capture.begin();RunLoop.main.run()
    } else { emit(["type":"music-state","phase":"error","detail":"Ultra focus nécessite macOS 14.2 ou plus récent."]) }
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
} else if (args.count==4 || (args.count==5 && args[4]=="--send-return")) && ["--voice","--voice-parakeet"].contains(args[1]) {
    let recorder=Recorder(whisper:args[2],model:args[3],engineKind:args[1]=="--voice-parakeet" ? "parakeet" : "whisper",sendReturn:args.contains("--send-return"));recorder.begin();RunLoop.main.run()
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
