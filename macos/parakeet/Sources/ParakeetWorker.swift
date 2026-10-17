import Foundation
import FluidAudio

func reply(_ value: [String: Any]) {
    if let data=try? JSONSerialization.data(withJSONObject:value) {
        FileHandle.standardOutput.write(data+Data([10]))
    }
}

@main struct ParakeetWorker {
    static func main() async {
        let args=CommandLine.arguments
        guard args.count >= 3 else { exit(2) }
        let directory=URL(fileURLWithPath:args[2],isDirectory:true)
        do {
            if args[1] == "--prepare" {
                _ = try await AsrModels.downloadAndLoad(to:directory,version:.v3)
                reply(["ready":true]);return
            }
            ModelHub.offlineMode=true
            let models=try await AsrModels.load(from:directory,configuration:nil,version:.v3,encoderPrecision:.int8)
            let manager=AsrManager(config:.default)
            try await manager.loadModels(models)
            reply(["ready":true,"model":"Parakeet V3"])
            while let line=readLine() {
                guard let data=line.data(using:.utf8),
                      let request=try? JSONSerialization.jsonObject(with:data) as? [String:Any],
                      let path=request["path"] as? String else { reply(["error":"Invalid request"]);continue }
                do {
                    var decoder=TdtDecoderState.make(decoderLayers:await manager.decoderLayerCount)
                    let result=try await manager.transcribe(URL(fileURLWithPath:path),decoderState:&decoder)
                    reply(["text":result.text])
                } catch { reply(["error":"Local transcription failed"] ) }
            }
        } catch {
            reply(["error":"Parakeet models could not be loaded"])
            FileHandle.standardError.write(Data((error.localizedDescription+"\n").utf8))
            exit(1)
        }
    }
}
