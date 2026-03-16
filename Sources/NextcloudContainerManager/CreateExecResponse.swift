///
/// The response body returned by `POST /containers/{id}/exec`.
///
struct CreateExecResponse: Decodable {
    /// The identifier of the created exec instance.
    let Id: String
}
