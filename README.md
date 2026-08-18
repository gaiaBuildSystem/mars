# Mars

<p align="center">
    <img
        src="./assets/image.png"
        height="212"
    />
</p>

Mars is a CLI tool for managing PhobOS ostree repositories under a target machine. It makes it easy to create new commits, deploys and rollbacks. Also provides a nice output for checking the status of the deployment.

It comes pre-installed with PhobOS images, so if you have a device with PhobOS, you already have Mars!

Mars is a key component of the PhobOS ecosystem, enabling easy development and deployment workflows.

## Subcommands

Below is a list of available subcommands and a short description:

- `commit`: Commit a development diff (need to be in dev mode).
- `dev`: Set the device on development mode.
- `deploy`: Deploy the head of the default branch (need to be in dev mode).
- `deploy-hash`: Print the booted deployment hash.
- `help`: Print a help message.
- `status`: Show the status of the current state of deployment.
- `rollback`: Rollback the deployment to the previous commit (not implemented).
- `version`: Print the Mars version.

## Examples of Use

A common workflow is using PhobOS for development and evaluation on a target device:

1. Put the device into development mode. This unlocks the root filesystem for changes, such as `apt update` / `apt install`:

    ```sh
    mars dev
    apt update
    apt install <package>
    ```

2. Once you're happy with the changes, commit them to create a new ostree commit:

    ```sh
    mars commit
    ```

3. Deploy the new commit as the next boot target:

    ```sh
    mars deploy
    ```

4. Restart the device so it boots into the newly deployed commit:

    ```sh
    reboot
    ```

You can check the state of the deployment at any point with `mars status`.

## Building

Mars is written in Zig and uses the Zig build system. To build Mars, you need to have Zig installed on your system, and then run the build on the root of the project:

```sh
zig build
```

## License

Mars is licensed under the MIT License. See the [LICENSE](./LICENSE) file for more information.

## Contributing

Contributions are welcome! If you find a bug or have a feature request, please open an issue on the [GitHub repository](https://github.com/gaiaBuildSystem/mars/issues).
