import AWSLambdaEvents
@testable import AWSLambdaRuntimeCore
import Logging
import NIO
import Vapor
@testable import VaporAWSLambdaRuntime
import XCTest

final class ALBTests: XCTestCase {
    func testALBRequest() throws {
        let requestdata = """
        {
            "requestContext": {
                "elb": {
                    "targetGroupArn": "arn:aws:elasticloadbalancing:us-east-2:123456789012:targetgroup/lambda-279XGJDqGZ5rsrHC2Fjr/49e9d65c45c6791a"
                }
            },
            "httpMethod": "GET",
            "path": "/lambda",
            "queryStringParameters": {
                "query": "1234ABCD"
            },
            "headers": {
                "accept": "text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,image/apng,*/*;q=0.8",
                "accept-encoding": "gzip",
                "accept-language": "en-US,en;q=0.9",
                "connection": "keep-alive",
                "host": "lambda-alb-123578498.us-east-2.elb.amazonaws.com",
                "upgrade-insecure-requests": "1",
                "user-agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/71.0.3578.98 Safari/537.36",
                "x-amzn-trace-id": "Root=1-5c536348-3d683b8b04734faae651f476",
                "x-forwarded-for": "72.12.164.125",
                "x-forwarded-port": "80",
                "x-forwarded-proto": "http",
                "x-imforwards": "20"
            },
            "body": "",
            "isBase64Encoded": false
        }
        """
        let decoder = JSONDecoder()
        let request = try decoder.decode(ALB.TargetGroupRequest.self, from: requestdata.data(using: .utf8)!)
        print("F: ", request)
    }

    func testCreateALBResponse() {
        let eventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        defer { XCTAssertNoThrow(try eventLoopGroup.syncShutdownGracefully()) }
        let eventLoop = eventLoopGroup.next()
        let allocator = ByteBufferAllocator()
        let logger = Logger(label: "test")

        let body = #"{"hello": "world"}"#
        let vaporResponse = Vapor.Response(
            status: .ok,
            headers: HTTPHeaders([
                ("Content-Type", "application/json"),
            ]),
            body: .init(string: body)
        )

        let context = Lambda.Context(
            requestID: "abc123",
            traceID: AmazonHeaders.generateXRayTraceID(),
            invokedFunctionARN: "function-arn",
            deadline: .now() + .seconds(3),
            logger: logger,
            eventLoop: eventLoop,
            allocator: allocator
        )

        var response: ALB.TargetGroupResponse?
        XCTAssertNoThrow(response = try ALB.TargetGroupResponse.from(response: vaporResponse, in: context).wait())

        XCTAssertEqual(response?.body, body)
        XCTAssertEqual(response?.headers?.count, 2)
        XCTAssertEqual(response?.headers?["Content-Type"], "application/json")
        XCTAssertEqual(response?.headers?["content-length"], String(body.count))
    }
}
