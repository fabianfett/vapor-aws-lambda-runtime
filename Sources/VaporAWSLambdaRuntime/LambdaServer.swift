import AWSLambdaEvents
import AWSLambdaRuntime
import Vapor

// MARK: Application + Lambda

public extension Application {
    var lambda: Lambda {
        .init(application: self)
    }

    struct Lambda {
        public let application: Application
    }
}

public extension Application.Servers.Provider {
    static var lambda: Self {
        .init {
            $0.servers.use { $0.lambda.server.shared }
        }
    }
}

// MARK: Application + Lambda + Server

public extension Application.Lambda {
    var server: Server {
        .init(application: application)
    }

    struct Server {
        let application: Application

        public var shared: LambdaServer {
            if let existing = application.storage[Key.self] {
                return existing
            } else {
                let new = LambdaServer(
                    application: application,
                    responder: application.responder.current,
                    configuration: self.configuration,
                    on: self.application.eventLoopGroup
                )
                self.application.storage[Key.self] = new
                return new
            }
        }

        struct Key: StorageKey {
            typealias Value = LambdaServer
        }

        public var configuration: LambdaServer.Configuration {
            get {
                self.application.storage[ConfigurationKey.self] ?? .init(
                    logger: self.application.logger
                )
            }
            nonmutating set {
                if self.application.storage.contains(Key.self) {
                    self.application.logger.warning("Cannot modify server configuration after server has been used.")
                } else {
                    self.application.storage[ConfigurationKey.self] = newValue
                }
            }
        }

        struct ConfigurationKey: StorageKey {
            typealias Value = LambdaServer.Configuration
        }
    }
}

// MARK: LambdaServer

public class LambdaServer: Server {
    public struct Configuration {
        public enum RequestSource {
            case apiGateway
            case apiGatewayV2
//      case applicationLoadBalancer // not in this release
        }

        var requestSource: RequestSource
        var logger: Logger

        public init(apiService: RequestSource = .apiGatewayV2, logger: Logger) {
            self.requestSource = apiService
            self.logger = logger
        }
    }

    let application: Application
    let responder: Responder
    let configuration: Configuration
    let eventLoop: EventLoop
    let lambdaHandler: ByteBufferLambdaHandler
    let lambdaLifecycle: Lambda.Lifecycle

    init(application: Application,
         responder: Responder,
         configuration: Configuration,
         on eventLoopGroup: EventLoopGroup)
    {
        self.application = application
        self.responder = responder
        self.configuration = configuration

        self.eventLoop = eventLoopGroup.next()

        let handler: ByteBufferLambdaHandler

        switch configuration.requestSource {
        case .apiGateway:
            handler = APIGatewayHandler(application: application, responder: responder)
        case .apiGatewayV2:
            handler = APIGatewayV2Handler(application: application, responder: responder)
        }

        self.lambdaLifecycle = Lambda.Lifecycle(
            eventLoop: self.eventLoop,
            logger: self.application.logger
        ) {
            $0.eventLoop.makeSucceededFuture(handler)
        }
        self.lambdaHandler = handler
    }

    public func start(hostname _: String?, port _: Int?) throws {
        self.eventLoop.execute {
            _ = self.lambdaLifecycle.start()
        }

        self.lambdaLifecycle.shutdownFuture.whenComplete { _ in
            DispatchQueue(label: "shutdown").async {
                self.application.shutdown()
            }
        }
    }

    public var onShutdown: EventLoopFuture<Void> {
        self.lambdaLifecycle.shutdownFuture.map { _ in }
    }

    public func shutdown() {
        self.lambdaLifecycle.shutdown()
    }
}
