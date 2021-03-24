import AWSLambdaTesting
@testable import AWSLambdaRuntimeCore
@testable import AWSLambdaEvents
import Logging
import NIO
import Vapor
@testable import VaporAWSLambdaRuntime
import XCTest

final class LambdaServerTests: XCTestCase {
    func testLambdaServer() {
        let eventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        defer { XCTAssertNoThrow(try eventLoopGroup.syncShutdownGracefully()) }
        
        let app = Application(.development, .shared(eventLoopGroup))
        defer { XCTAssertNoThrow(app.shutdown()) }

        struct Name: Codable {
          let name: String
        }

        struct Hello: Content {
          let hello: String
        }

        app.get("hello") { (_) -> Hello in
          Hello(hello: "world")
        }

        app.post("hello") { req -> Hello in
          let name = try req.content.decode(Name.self)
          return Hello(hello: name.name)
        }
        
        let server = app.lambda.server.shared
        let handler = server.lambdaHandler as! APIGatewayV2Handler
        
        let request = APIGateway.V2.Request(
            version: "1.1",
            routeKey: "/test/123",
            rawPath: "/test/123",
            rawQueryString: "",
            cookies: nil,
            headers: [:],
            queryStringParameters: nil,
            pathParameters: nil,
            context: .init(
                accountId: "123",
                apiId: "abc",
                domainName: "apigateway.region",
                domainPrefix: "",
                stage: "default",
                requestId: "123",
                http: .init(
                    method: .GET,
                    path: "/test/123",
                    protocol: "https",
                    sourceIp: "127.0.0.1",
                    userAgent: "test-user-agent"
                ),
                authorizer: nil,
                time: "123",
                timeEpoch: UInt64(Date().timeIntervalSince1970)
            ),
            stageVariables: nil,
            body: nil,
            isBase64Encoded: false)
        
        var response: APIGateway.V2.Response?
        XCTAssertNoThrow(response = try Lambda.test(handler, with: request))

//        XCTAssertNoThrow(try server.onShutdown.wait())
    }
}
