import Foundation
import Network

// This bounded discovery-only server rejects scan jobs and never opens USB.
let capabilities = """
<?xml version="1.0" encoding="UTF-8"?>
<scan:ScannerCapabilities xmlns:scan="http://schemas.hp.com/imaging/escl/2011/05/03" xmlns:pwg="http://www.pwg.org/schemas/2010/12/sm">
<pwg:Version>2.0</pwg:Version><pwg:MakeAndModel>Canon BJC-85 IS-12 Native Discovery Test</pwg:MakeAndModel>
<pwg:SerialNumber>IS12-NATIVE-DISCOVERY</pwg:SerialNumber><scan:Manufacturer>Canon</scan:Manufacturer>
<scan:UUID>00000000-0000-4000-8000-00000000000d</scan:UUID>
<scan:Adf><scan:AdfSimplexInputCaps><scan:MinWidth>1</scan:MinWidth><scan:MaxWidth>2400</scan:MaxWidth><scan:MinHeight>1</scan:MinHeight><scan:MaxHeight>3240</scan:MaxHeight>
<scan:SettingProfiles><scan:SettingProfile><scan:ColorModes><scan:ColorMode>RGB24</scan:ColorMode><scan:ColorMode>Grayscale8</scan:ColorMode></scan:ColorModes>
<scan:DocumentFormats><pwg:DocumentFormat>image/jpeg</pwg:DocumentFormat><pwg:DocumentFormat>image/png</pwg:DocumentFormat></scan:DocumentFormats>
<scan:SupportedResolutions><scan:DiscreteResolutions>
<scan:DiscreteResolution><scan:XResolution>90</scan:XResolution><scan:YResolution>90</scan:YResolution></scan:DiscreteResolution>
<scan:DiscreteResolution><scan:XResolution>180</scan:XResolution><scan:YResolution>180</scan:YResolution></scan:DiscreteResolution>
<scan:DiscreteResolution><scan:XResolution>360</scan:XResolution><scan:YResolution>360</scan:YResolution></scan:DiscreteResolution>
</scan:DiscreteResolutions></scan:SupportedResolutions></scan:SettingProfile></scan:SettingProfiles>
<scan:SupportedIntents><scan:Intent>Document</scan:Intent><scan:Intent>Photo</scan:Intent></scan:SupportedIntents>
</scan:AdfSimplexInputCaps><scan:AdfOptions><scan:AdfOption>DetectPaperLoaded</scan:AdfOption></scan:AdfOptions><scan:Justification><scan:XImagePosition>Left</scan:XImagePosition><scan:YImagePosition>Top</scan:YImagePosition></scan:Justification></scan:Adf>
</scan:ScannerCapabilities>
"""
let scannerStatus = """
<?xml version="1.0" encoding="UTF-8"?>
<scan:ScannerStatus xmlns:scan="http://schemas.hp.com/imaging/escl/2011/05/03" xmlns:pwg="http://www.pwg.org/schemas/2010/12/sm"><pwg:Version>2.0</pwg:Version><pwg:State>Idle</pwg:State><scan:AdfState>ScannerAdfLoaded</scan:AdfState></scan:ScannerStatus>
"""
final class Request {
    let connection: NWConnection
    var bytes = Data()
    var responded = false
    init(_ connection: NWConnection) { self.connection = connection }
    func start() {
        connection.start(queue: .main)
        DispatchQueue.main.asyncAfter(deadline: .now()+10) { if !self.responded { self.connection.cancel() } }
        receive()
    }
    func receive() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16384) { data, _, complete, error in
            if let data { self.bytes.append(data) }
            if self.bytes.count > 65536 { self.connection.cancel(); return }
            if let range = self.bytes.range(of: Data("\r\n\r\n".utf8)) {
                let header = String(decoding: self.bytes[..<range.lowerBound], as: UTF8.self)
                let request = header.components(separatedBy: "\r\n").first ?? ""
                print(request); fflush(stdout)
                let parts = request.split(separator: " ")
                var body = "", code = "404 Not Found"
                if parts.count == 3 && parts[0] == "GET" {
                    if parts[1] == "/eSCL/ScannerCapabilities" { body = capabilities; code = "200 OK" }
                    else if parts[1] == "/eSCL/ScannerStatus" { body = scannerStatus; code = "200 OK" }
                } else if parts.count == 3 && parts[0] == "POST" {
                    code = "503 Service Unavailable"; body = "Discovery test: image acquisition is disabled."
                }
                let payload = Data(body.utf8)
                var response = Data("HTTP/1.1 \(code)\r\nContent-Type: text/xml; charset=utf-8\r\nContent-Length: \(payload.count)\r\nConnection: close\r\n\r\n".utf8)
                response.append(payload); self.responded = true
                self.connection.send(content: response, completion: .contentProcessed { _ in self.connection.cancel() })
            } else if error == nil && !complete { self.receive() }
            else { self.connection.cancel() }
        }
    }
}
let parameters = NWParameters.tcp
parameters.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback), port: 8640)
let listener = try NWListener(using: parameters)
listener.newConnectionHandler = { Request($0).start() }
listener.stateUpdateHandler = { state in print("listener: \(state)"); fflush(stdout) }
listener.start(queue: .main)
DispatchQueue.main.asyncAfter(deadline: .now()+600) { listener.cancel(); exit(0) }
dispatchMain()
