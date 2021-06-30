import Vapor
import VaporAWSLambdaRuntime

let app = Application()

struct Name: Codable {
    let name: String
}

struct Hello: Content {
    let hello: String
}

app.get("hello") { _ -> Hello in
    Hello(hello: "world")
}

app.post("hello") { req -> Hello in
    let name = try req.content.decode(Name.self)
    return Hello(hello: name.name)
}
app.storage[Application.Lambda.Server.ConfigurationKey.self] = .init(apiService: .applicationLoadBalancer,
    logger: app.logger)
app.servers.use(.lambda)
try app.run()


