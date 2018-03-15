import Foundation
import Alamofire

extension DataRequest: Cancellable{}

/// A network transport that uses HTTP POST requests to send GraphQL operations to a server, and that uses `Alamofire` as the networking implementation.
public class AlamofireNetworkTransport: NetworkTransport {
    
    let url: URL
    let serializationFormat = JSONSerializationFormat.self
    var manager: SessionManager
    
    /// Creates a network transport with the specified server URL and session configuration.
    ///
    /// - Parameters:
    ///   - url: The URL of a GraphQL server to connect to.
    ///   - requestAdapter: Alamofire's request adapter
    ///   - requestRetrier: Alamofire's request retrier
    ///   - configuration: A session configuration used to configure the session. Defaults to `URLSessionConfiguration.default`.
    ///   - sendOperationIdentifiers: Whether to send operation identifiers rather than full operation text, for use with servers that support query persistence. Defaults to false.
    public init(url: URL, configuration: URLSessionConfiguration = URLSessionConfiguration.default, requestAdapter: RequestAdapter?, requestRetrier: RequestRetrier?, sendOperationIdentifiers: Bool = false) {
        self.url = url
        self.sendOperationIdentifiers = sendOperationIdentifiers
        self.manager = SessionManager(configuration: configuration)
        if let requestAdapter = requestAdapter{
            self.manager.adapter = requestAdapter
        }
        if let requestRetrier = requestRetrier{
            self.manager.retrier = requestRetrier
        }
    }
    
    /// Send a GraphQL operation to a server and return a response.
    ///
    /// - Parameters:
    ///   - operation: The operation to send.
    ///   - completionHandler: A closure to call when a request completes.
    ///   - response: The response received from the server, or `nil` if an error occurred.
    ///   - error: An error that indicates why a request failed, or `nil` if the request was succesful.
    /// - Returns: An object that can be used to cancel an in progress request.
    public func send<Operation>(operation: Operation, completionHandler: @escaping (_ response: GraphQLResponse<Operation>?, _ error: Error?) -> Void) -> Cancellable {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body = requestBody(for: operation)
        request.httpBody = try! serializationFormat.serialize(value: body)
        
        return manager
            .request(request)
            .validate(statusCode: 200..<300)
            .responseData(completionHandler: { (dataResponse) in
                
                if dataResponse.error != nil {
                    completionHandler(nil, dataResponse.error)
                    return
                }
                
                guard let httpResponse = dataResponse.response else {
                    fatalError("Response should be an HTTPURLResponse")
                }
                
                DispatchQueue.global(qos: .default).async {
                    switch dataResponse.result {
                    case .success(let value):
                        
                        do {
                            guard let body =  try self.serializationFormat.deserialize(data: value) as? JSONObject else {
                                throw GraphQLHTTPResponseError(body: value, response: httpResponse, kind: .invalidResponse)
                            }
                            let response = GraphQLResponse(operation: operation, body: body)
                            completionHandler(response, nil)
                        } catch {
                            completionHandler(nil, error)
                        }
                        
                    case .failure(_):
                        completionHandler(nil, GraphQLHTTPResponseError(body: dataResponse.data, response: httpResponse, kind: .errorResponse))
                    }
                }
            })
    }
    
    private let sendOperationIdentifiers: Bool
    
    private func requestBody<Operation: GraphQLOperation>(for operation: Operation) -> GraphQLMap {
        if sendOperationIdentifiers {
            guard let operationIdentifier = operation.operationIdentifier else {
                preconditionFailure("To send operation identifiers, Apollo types must be generated with operationIdentifiers")
            }
            return ["id": operationIdentifier, "variables": operation.variables]
        }
        return ["query": operation.queryDocument, "variables": operation.variables]
    }
}

