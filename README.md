# Swift Nextcloud Test Containers

Control the local deployment of Nextcloud Docker containers programmatically from Swift.

## What does it do?

Talk to the [Docker Engine API](https://docs.docker.com/reference/api/engine/) on macOS to deploy ephemeral Nextcloud containers for automated tests.

## Who is this for?

This package targets developers working on native Nextcloud client apps.

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
