# Swift Nextcloud Manager

[![](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2Fi2h3%2Fnextcloud-container-manager%2Fbadge%3Ftype%3Dswift-versions)](https://swiftpackageindex.com/i2h3/nextcloud-container-manager)
[![](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2Fi2h3%2Fnextcloud-container-manager%2Fbadge%3Ftype%3Dplatforms)](https://swiftpackageindex.com/i2h3/nextcloud-container-manager)

Control the local deployment of Nextcloud Docker containers programmatically from Swift.

## What does it do?

Talk to the [Docker Engine API](https://docs.docker.com/reference/api/engine/) on macOS to deploy ephemeral Nextcloud containers for running automated tests against them.

## Who is this for?

This package targets developers working on native Nextcloud client apps.
It helps them to implement tests running against a real Nextcloud server and enables end-to-end testing.

## License

See [LICENSE](LICENSE).

## Contributing

[SwiftFormat](https://github.com/nicklockwood/SwiftFormat) was introduced into this project.
Before submitting a pull request, please ensure that your code changes comply with the currently configured code style.
You can run the following command in the root of the package repository clone:

```bash
swift package plugin --allow-writing-to-package-directory swiftformat --verbose --cache ignore
```

Also, there is a GitHub action run automatically which lints code changes in pull requests.
