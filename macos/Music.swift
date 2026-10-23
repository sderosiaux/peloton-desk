import AppKit
import CoreAudio
import Foundation

private func unit(_ value: Double) -> Double { min(1, max(0, value)) }

// Streaming analysis only: raw audio never leaves the callback and is never saved.
// 20 ms features, up to 12 s of scalar onset history, no model/network dependency.
final class MusicAnalyzer {
    let sampleRate: Double
    private let frameSize: Int
    private var samples = 0, frames = 0
    private var low = 0.0, low2 = 0.0, mid = 0.0
    private let lowAlpha: Double, midAlpha: Double
    private var sum = 0.0, bassSum = 0.0, highSum = 0.0
    private var previousBands = [Double](repeating: 0, count: 3)
    private var fluxHistory = [Double](), fluxRecent = [Double]()
    private var previousFlux = 0.0, previousBassFlux = 0.0
    private var lastOnset = -100.0, lastKick = -100.0, onsetTimes = [Double]()
    private var peakRMS = 0.0005, energy = 0.0, bass = 0.0, treble = 0.0
    private var candidate = 0.0, candidateCount = 0, tempo = 0.0, confidence = 0.0
    private var active = false
    private(set) var snapshot: [String: Any] = [:]

    init(sampleRate: Double) {
        self.sampleRate = sampleRate
        frameSize = max(1, Int(sampleRate * 0.02))
        lowAlpha = 1 - exp(-2 * .pi * 180 / sampleRate)
        midAlpha = 1 - exp(-2 * .pi * 2200 / sampleRate)
    }

    func accept(_ value: Float) {
        let x = value.isFinite ? Double(value) : 0
        low += lowAlpha * (x-low); low2 += lowAlpha * (low-low2)
        mid += midAlpha * (x-mid)
        let high = x-mid
        sum += x*x; bassSum += low2*low2; highSum += high*high
        samples += 1
        if samples >= frameSize { finishFrame() }
    }

    private func finishFrame() {
        frames += 1
        let time = Double(frames) * 0.02
        let rms = sqrt(sum/Double(samples))
        let bassRMS = sqrt(bassSum/Double(samples)), highRMS = sqrt(highSum/Double(samples))
        let bands = [bassRMS, max(0, rms-bassRMS-highRMS*0.3), highRMS]
        // Log compression makes attacks useful across Spotify volume/mastering levels.
        let logs = bands.map { log1p($0*100) }
        let delta = zip(logs,previousBands).map { max(0,$0.0-$0.1) }
        let flux = delta[0]*0.65 + delta[1]*0.25 + delta[2]*0.1
        let baseline = fluxRecent.reduce(0,+)/Double(max(1,fluxRecent.count))
        active = rms > 0.00015
        if active && previousFlux > flux && previousFlux > max(0.018,baseline*1.6)
            && time-lastOnset > 0.16 {
            lastOnset = time-0.02; onsetTimes.append(lastOnset)
            if previousBassFlux > 0.015 || previousFlux > baseline*2.5 { lastKick = lastOnset }
        }
        previousFlux = flux; previousBassFlux = delta[0]; previousBands = logs
        fluxRecent.append(flux); if fluxRecent.count>25 { fluxRecent.removeFirst() }
        fluxHistory.append(active ? flux : 0); if fluxHistory.count>600 { fluxHistory.removeFirst() }
        onsetTimes.removeAll { time-$0 > 8 }
        peakRMS = max(0.0005, rms, peakRMS*0.998)
        let relative = unit(rms/peakRMS)
        let level = unit((20*log10(max(rms,0.000001))+58)/46)
        energy += ((active ? relative*0.7+level*0.3 : 0)-energy)*0.12
        bass += ((active ? unit(bassRMS/max(rms,0.00001)*1.25) : 0)-bass)*0.18
        treble += ((active ? unit(highRMS/max(rms,0.00001)) : 0)-treble)*0.18
        if frames%25 == 0 { estimateTempo(time:time) }
        let certainty = confidence * unit((2.0-(time-lastOnset))/0.8)
        snapshot = ["type":"music-frame", "active":active, "energy":energy,
                    "bass":bass, "treble":treble, "density":unit(Double(onsetTimes.filter { time-$0<2 }.count)/10),
                    "pulse":active ? exp(-max(0,time-lastKick)/0.15) : 0,
                    "confidence":certainty, "bpm":certainty>0.45 && tempo>0 ? tempo : NSNull(),
                    "beatAge":max(0,time-lastKick), "source":"Spotify"]
        samples=0;sum=0;bassSum=0;highSum=0
    }

    private func estimateTempo(time:Double) {
        guard fluxHistory.count>=200, onsetTimes.count>=4, time-lastOnset<1.5 else {
            confidence *= 0.6; return
        }
        let values = Array(fluxHistory.suffix(400))
        func correlation(_ lag:Int) -> Double {
            guard lag>0, values.count>lag else { return 0 }
            var dot=0.0, a=0.0, b=0.0
            for i in lag..<values.count {
                dot += values[i]*values[i-lag];a += values[i]*values[i];b += values[i-lag]*values[i-lag]
            }
            return dot / max(0.0000001,sqrt(a*b))
        }
        // Allow ±20 ms timing jitter; keep the main peak dominant over neighbours.
        var scores=[Int:Double]()
        for lag in 14...52 {
            scores[lag] = correlation(lag)+0.25*(correlation(lag-1)+correlation(lag+1))
        }
        var bestLag=0, bestScore=0.0
        for lag in 16...50 {
            let bpm=3000/Double(lag)
            let continuity = tempo>0 ? exp(-abs(log(bpm/tempo))*5) : exp(-abs(log(bpm/120))*2)
            let score=(scores[lag] ?? 0)*(0.92+0.08*continuity)
            if score>bestScore { bestScore=score;bestLag=lag }
        }
        guard bestLag>0, bestScore>0.32 else { confidence *= 0.75;return }
        let left=scores[bestLag-1] ?? 0, center=scores[bestLag] ?? 0, right=scores[bestLag+1] ?? 0
        let denominator=left-2*center+right
        let shift=abs(denominator)>0.00001 ? min(0.5,max(-0.5,0.5*(left-right)/denominator)) : 0
        let detected=3000/(Double(bestLag)+shift)
        if abs(detected-candidate)<6 { candidateCount += 1 } else { candidateCount=1 }
        candidate=detected
        if tempo==0 || abs(detected-tempo)<7 || candidateCount>=4 {
            tempo=tempo==0 || abs(detected-tempo)>=7 ? detected : tempo*0.75+detected*0.25
            confidence=unit((bestScore-0.2)/0.65)
        } else { confidence *= 0.9 }
    }

    static func selfTest() {
        // Generated PCM in memory: no speakers, microphone, Spotify or audio tap.
        for bpm in [90.0,120.0,168.0] {
            let analyzer=MusicAnalyzer(sampleRate:8000)
            for n in 0..<128000 {
                let t=Double(n)/8000, phase=t.truncatingRemainder(dividingBy:60/bpm)
                let x=phase<0.12 ? 0.5*exp(-phase*35)*sin(2 * .pi * 70*t) : 0
                analyzer.accept(Float(x))
            }
            let result=analyzer.snapshot["bpm"] as? Double ?? 0
            precondition(abs(result-bpm)<4,"Beat estimate \(result) for generated \(bpm) BPM")
            for _ in 0..<32000 { analyzer.accept(0) }
            precondition((analyzer.snapshot["confidence"] as? Double ?? 1)<0.2)
            precondition(analyzer.snapshot["active"] as? Bool == false)
        }
        let steady=MusicAnalyzer(sampleRate:8000)
        for n in 0..<96000 { steady.accept(Float(0.1*sin(2 * .pi * 220*Double(n)/8000))) }
        precondition((steady.snapshot["confidence"] as? Double ?? 1)<0.45,"Steady tone is not a beat")
        let quiet=MusicAnalyzer(sampleRate:8000)
        for n in 0..<64000 {
            let t=Double(n)/8000,phase=t.truncatingRemainder(dividingBy:0.5)
            quiet.accept(Float(0.009*exp(-phase*12)*sin(2 * .pi * 70*t)))
        }
        precondition((quiet.snapshot["confidence"] as? Double ?? 0)>0.58,"Low-volume beat must remain detectable")
        print("Music analysis checks passed: generated beats, silence and sustained tone; no audio capture.")
    }
}

@available(macOS 14.2, *)
final class MusicCapture {
    private var tap:AudioObjectID=0, device:AudioObjectID=0, io:AudioDeviceIOProcID?
    private let queue=DispatchQueue(label:"local.pelotondesk.music",qos:.userInteractive)
    private var analyzer:MusicAnalyzer?
    private var lastFrameAt=0.0, sequence=0
    private var processes=[AudioObjectID](), poll:Timer?, output:Timer?, signals=[DispatchSourceSignal]()
    private var failed=false, phase=""

    private func address(_ selector:AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector:selector,mScope:kAudioObjectPropertyScopeGlobal,mElement:kAudioObjectPropertyElementMain)
    }
    static func spotifyProcesses() -> [AudioObjectID] {
        var property=AudioObjectPropertyAddress(mSelector:kAudioHardwarePropertyProcessObjectList,mScope:kAudioObjectPropertyScopeGlobal,mElement:kAudioObjectPropertyElementMain)
        var size:UInt32=0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject),&property,0,nil,&size)==noErr else { return [] }
        var ids=[AudioObjectID](repeating:0,count:Int(size)/MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject),&property,0,nil,&size,&ids)==noErr else { return [] }
        return ids.filter { id in
            var key=AudioObjectPropertyAddress(mSelector:kAudioProcessPropertyBundleID,mScope:kAudioObjectPropertyScopeGlobal,mElement:kAudioObjectPropertyElementMain)
            var value:Unmanaged<CFString>?;var count=UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
            let result=withUnsafeMutablePointer(to:&value) { AudioObjectGetPropertyData(id,&key,0,nil,&count,$0) }
            guard result==noErr,let bundle=value?.takeRetainedValue() as String? else { return false }
            return bundle=="com.spotify.client" || bundle.hasPrefix("com.spotify.client.")
        }.sorted()
    }
    private func state(_ next:String,_ detail:String) {
        guard next != phase else { return };phase=next
        emit(["type":"music-state","phase":next,"detail":detail,"source":"Spotify"])
    }
    func begin() {
        for number in [SIGTERM,SIGINT] {
            signal(number,SIG_IGN)
            let source=DispatchSource.makeSignalSource(signal:number,queue:.main)
            source.setEventHandler { [weak self] in self?.stop();exit(0) };source.resume();signals.append(source)
        }
        poll=Timer.scheduledTimer(withTimeInterval:2,repeats:true) { [weak self] _ in
            guard getppid() != 1 else { self?.stop();exit(0) };self?.refresh()
        }
        output=Timer.scheduledTimer(withTimeInterval:0.05,repeats:true) { [weak self] _ in self?.publish() }
        refresh()
    }
    private func refresh() {
        guard !failed else { return }
        let ids=Self.spotifyProcesses()
        if ids.isEmpty {
            teardown();processes=[]
            state("waiting","Lancez une musique dans Spotify sur le Mac.");return
        }
        if ids==processes && device != 0 { return }
        teardown();processes=ids
        state("starting","Autorisez l’audio de Peloton Desk Mac si macOS le demande.")
        do { try start(ids);state("listening","Spotify · adaptation automatique") }
        catch {
            teardown();failed=true
            state("error","Capture Spotify indisponible. Autorisez Peloton Desk Mac dans Confidentialité → Enregistrement de l’écran et de l’audio système, puis réessayez.")
        }
    }
    private func check(_ result:OSStatus) throws {
        if result != noErr { throw NSError(domain:"MusicCapture",code:Int(result)) }
    }
    private func start(_ ids:[AudioObjectID]) throws {
        let description=CATapDescription(monoMixdownOfProcesses:ids)
        description.name="Peloton Desk · Spotify"
        description.isPrivate=true;description.muteBehavior = .unmuted
        try check(AudioHardwareCreateProcessTap(description,&tap))
        var format=AudioStreamBasicDescription();var size=UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        var key=address(kAudioTapPropertyFormat)
        try check(AudioObjectGetPropertyData(tap,&key,0,nil,&size,&format))
        guard format.mFormatID==kAudioFormatLinearPCM,format.mFormatFlags & kAudioFormatFlagIsFloat != 0,
              format.mBitsPerChannel==32,format.mSampleRate>0 else { throw NSError(domain:"MusicFormat",code:1) }
        let composition:[String:Any]=[
            kAudioAggregateDeviceNameKey:"Peloton Desk Music",
            kAudioAggregateDeviceUIDKey:UUID().uuidString,
            kAudioAggregateDeviceIsPrivateKey:true,
            kAudioAggregateDeviceTapAutoStartKey:true,
            kAudioAggregateDeviceTapListKey:[[kAudioSubTapUIDKey:description.uuid.uuidString,kAudioSubTapDriftCompensationKey:true]]
        ]
        try check(AudioHardwareCreateAggregateDevice(composition as CFDictionary,&device))
        queue.sync { analyzer=MusicAnalyzer(sampleRate:format.mSampleRate);lastFrameAt=0 }
        try check(AudioDeviceCreateIOProcIDWithBlock(&io,device,queue) { [weak self] _,input,_,_,_ in
            guard let self=self,let analyzer=self.analyzer else { return }
            let buffers=UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating:input))
            guard let first=buffers.first,first.mNumberChannels>0 else { return }
            let frames=Int(first.mDataByteSize)/MemoryLayout<Float>.size/Int(first.mNumberChannels)
            for frame in 0..<frames {
                var mono:Float=0,channels=0
                for buffer in buffers {
                    guard let bytes=buffer.mData else { continue }
                    let count=Int(buffer.mNumberChannels),data=bytes.assumingMemoryBound(to:Float.self)
                    guard (frame+1)*count*MemoryLayout<Float>.size<=Int(buffer.mDataByteSize) else { continue }
                    for c in 0..<count { mono += data[frame*count+c] };channels += count
                }
                if channels>0 { analyzer.accept(mono/Float(channels)) }
            }
            self.lastFrameAt=ProcessInfo.processInfo.systemUptime
        })
        try check(AudioDeviceStart(device,io))
    }
    private func publish() {
        guard device != 0 else { return }
        var frame=[String:Any](),age=0.0
        queue.sync { frame=analyzer?.snapshot ?? [:];age=ProcessInfo.processInfo.systemUptime-lastFrameAt }
        guard !frame.isEmpty,age<0.5 else {
            state("waiting","En attente du son de Spotify…");return
        }
        state("listening","Spotify · adaptation automatique")
        sequence += 1;frame["sequence"]=sequence;frame["at"]=Date().timeIntervalSince1970*1000
        emit(frame)
    }
    private func teardown() {
        if device != 0,let callback=io { AudioDeviceStop(device,callback);AudioDeviceDestroyIOProcID(device,callback) }
        io=nil
        if device != 0 { AudioHardwareDestroyAggregateDevice(device);device=0 }
        if tap != 0 { AudioHardwareDestroyProcessTap(tap);tap=0 }
        queue.sync { analyzer=nil;lastFrameAt=0 }
    }
    func stop() { poll?.invalidate();output?.invalidate();teardown() }
}
