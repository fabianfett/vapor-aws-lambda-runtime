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

        public struct ConfigurationKey: StorageKey {
            public typealias Value = LambdaServer.Configuration
        }
    }
}

// MARK: LambdaServer

public class LambdaServer: Server {
    public struct Configuration {
        public enum RequestSource {
            case apiGateway
            case apiGatewayV2
            case applicationLoadBalancer
        }

        var requestSource: RequestSource
        var logger: Logger

        public init(apiService: RequestSource = .apiGatewayV2, logger: Logger) {
            self.requestSource = apiService
            self.logger = logger
        }
    }

    private let application: Application
    private let responder: Responder
    private let configuration: Configuration
    private let eventLoop: EventLoop
    private var lambdaLifecycle: Lambda.Lifecycle

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
        case .applicationLoadBalancer:
            handler = ALBHandler(application: application, responder: responder)
        }

        self.lambdaLifecycle = Lambda.Lifecycle(
            eventLoop: self.eventLoop,
            logger: self.application.logger
        ) {
            $0.eventLoop.makeSucceededFuture(handler)
        }
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
        // this should only be executed after someone has called `app.shutdown()`
        // on lambda the ones calling should always be us!
        // If we have called shutdown, the lambda server already is shutdown.
        // That means, we have nothing to do here.
    }
}
