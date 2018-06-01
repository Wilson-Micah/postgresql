/// A PostgreSQL frontend client.
public final class PostgreSQLConnection: DatabaseConnection, BasicWorker {
    /// See `DatabaseConnection`.
    public typealias Database = PostgreSQLDatabase
    
    /// See `BasicWorker`.
    public var eventLoop: EventLoop {
        return channel.eventLoop
    }

    /// If non-nil, will log queries.
    public var logger: DatabaseLogger?

    /// See `DatabaseConnection`.
    public var isClosed: Bool

    /// See `Extendable`.
    public var extend: Extend
    
    /// Handles enqueued PostgreSQL commands and responses.
    internal let queue: QueueHandler<PostgreSQLMessage, PostgreSQLMessage>
    
    /// The channel
    internal let channel: Channel

    /// In-flight `send(...)` futures.
    private var currentSend: Promise<Void>?

    /// The current query running, if one exists.
    private var pipeline: Future<Void>

    /// Block type to be called on close of connection
    internal typealias CloseHandler = ((PostgreSQLConnection) -> Future<Void>)
    /// Called on close of the connection
    internal var closeHandlers = [CloseHandler]()
    /// Handler type for Notifications
    internal typealias NotificationHandler = (String) throws -> Void
    /// Handlers to be stored by channel name
    internal var notificationHandlers: [String: NotificationHandler] = [:]

    /// Creates a new PostgreSQL client on the provided data source and sink.
    init(queue: QueueHandler<PostgreSQLMessage, PostgreSQLMessage>, channel: Channel) {
        self.queue = queue
        self.channel = channel
        self.isClosed = false
        self.extend = [:]
        self.pipeline = channel.eventLoop.newSucceededFuture(result: ())
        channel.closeFuture.always {
            self.isClosed = true
            if let current = self.currentSend {
                current.fail(error: closeError)
            }
        }
    }
    
    /// Sends `PostgreSQLMessage` to the server.
    func send(_ message: [PostgreSQLMessage]) -> Future<[PostgreSQLMessage]> {
        var responses: [PostgreSQLMessage] = []
        return send(message) { response in
            responses.append(response)
        }.map(to: [PostgreSQLMessage].self) {
            return responses
        }
    }

    /// Sends `PostgreSQLMessage` to the server.
    func send(_ messages: [PostgreSQLMessage], onResponse: @escaping (PostgreSQLMessage) throws -> ()) -> Future<Void> {
        // if currentSend is not nil, previous send has not completed
        assert(currentSend == nil, "Attempting to call `send(...)` again before previous invocation has completed.")

        // ensure the connection is not closed
        guard !isClosed else {
            return eventLoop.newFailedFuture(error: closeError)
        }

        // create a new promise and store it
        let promise = eventLoop.newPromise(Void.self)
        currentSend = promise

        // cascade this enqueue to the newly created promise
        var error: Error?
        queue.enqueue(messages) { message in
            switch message {
            case .readyForQuery:
                if let e = error { throw e }
                return true
            case .error(let e): error = PostgreSQLError.errorResponse(e)
            case .notice(let n): debugOnly { WARNING("\(n)") }
            default: try onResponse(message)
            }
            return false // request until ready for query
        }.cascade(promise: promise)

        // when the promise completes, remove the reference to it
        promise.futureResult.always { self.currentSend = nil }

        // return the promise's future result (same as `queue.enqueue`)
        return promise.futureResult
    }

    /// Submits an async task to be pipelined.
    internal func operation(_ work: @escaping () -> Future<Void>) -> Future<Void> {
        /// perform this work when the current pipeline future is completed
        let new = pipeline.then(work)

        /// append this work to the pipeline, discarding errors as the pipeline
        //// does not care about them
        pipeline = new.catchMap { err in
            return ()
        }

        /// return the newly enqueued work's future result
        return new
    }

    /// Closes this client.
    public func close() {
        _ = executeCloseHandlersThenClose()
    }

    /// Executes close handlers before closing.
    private  func executeCloseHandlersThenClose() -> Future<Void> {
        if let beforeClose = closeHandlers.popLast() {
            return beforeClose(self).then { _ in
                self.executeCloseHandlersThenClose()
            }
        } else {
            return channel.close(mode: .all)
        }
    }

    /// Called when this class deinitializes.
    deinit {
        close()
    }

}

// MARK: Private

private let closeError = PostgreSQLError(identifier: "closed", reason: "Connection is closed.")
