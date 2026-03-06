///
/// The response body returned by `POST /containers/create`.
///
struct CreateContainerResponse: Decodable {
    /// The full container identifier assigned by Docker.
    let Id: String
}
